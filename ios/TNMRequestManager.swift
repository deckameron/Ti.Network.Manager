//
//  TNMRequestManager.swift
//  TiNetworkManager
//
//  Created by Douglas Alves on 02/01/26.
//

/**
 * Ti.Network.Manager - Request Manager
 * Handles standard HTTP requests with retry logic
 * Supports automatic retry with exponential/linear backoff
 * Session pool: one URLSession per host+timeout, reusing TCP/TLS connections
 */

import Foundation

class TNMRequestManager {
    
    // MARK: - Properties
    
    // activeTasks/retryState are touched from three threads: the caller's thread
    // (registration), the URLSession delegate queue (completion handler) and whatever
    // thread calls cancelRequest. A Swift Dictionary is not thread-safe -- concurrent
    // mutation corrupts its storage and the process later crashes while releasing the
    // stale buffer, deep inside the task teardown. Everything goes through stateLock.
    private var activeTasks: [String: URLSessionDataTask] = [:]
    private var retryState: [String: RetryState] = [:]
    private let stateLock = NSLock()
    
    // Session pool: keyed by "host_timeout" to reuse TCP/TLS connections
    // across requests to the same host with the same timeout setting.
    // One SessionDelegate per session routes progress events to the right task.
    private var sessionPool: [String: URLSession] = [:]
    private var delegatePool: [String: SessionDelegate] = [:]
    private let sessionPoolLock = NSLock()
    
    // MARK: - Synchronized State Access

    private func setActiveTask(_ task: URLSessionDataTask, for requestId: String) {
        stateLock.lock()
        defer { stateLock.unlock() }
        activeTasks[requestId] = task
    }

    private func activeTask(for requestId: String) -> URLSessionDataTask? {
        stateLock.lock()
        defer { stateLock.unlock() }
        return activeTasks[requestId]
    }

    @discardableResult
    private func removeActiveTask(for requestId: String) -> URLSessionDataTask? {
        stateLock.lock()
        defer { stateLock.unlock() }
        return activeTasks.removeValue(forKey: requestId)
    }

    private func removeRetryState(for requestId: String) {
        stateLock.lock()
        defer { stateLock.unlock() }
        retryState.removeValue(forKey: requestId)
    }

    // MARK: - Public Methods
    
    /**
     * Execute HTTP request with retry logic
     */
    func executeRequest(
        requestId: String,
        url: URL,
        method: String,
        headers: [String: String]?,
        body: Data?,
        priority: Float,
        timeout: Double,
        retryConfig: RetryConfiguration?,
        certificateValidator: CertificateValidator?,
        onProgress: ((Int64, Int64) -> Void)?,
        onComplete: @escaping (Int, [String: String], Data?) -> Void,
        onError: @escaping (Error, Bool) -> Void
    ) {
        TNMLogger.Request.created(requestId: requestId, url: url.absoluteString, method: method)
        
        let priorityString = priorityToString(priority)
        TNMLogger.Request.started(requestId: requestId, priority: priorityString)
        
        let (session, delegate) = getOrCreateSession(
            for: url,
            timeout: timeout,
            certificateValidator: certificateValidator
        )
        
        executeWithRetry(
            currentAttempt: 0,
            requestId: requestId,
            session: session,
            sessionDelegate: delegate,
            url: url,
            method: method,
            headers: headers,
            body: body,
            priority: priority,
            retryConfig: retryConfig,
            onProgress: onProgress,
            attempt: 1,
            startTime: Date(),
            onComplete: onComplete,
            onError: onError
        )
    }
    
    /**
     * Cancel request
     */
    func cancelRequest(requestId: String) {
        TNMLogger.Request.cancelled(requestId: requestId)
        
        // Remove first, then cancel: never hold stateLock while calling out into
        // URLSession or the delegate pool.
        if let task = removeActiveTask(for: requestId) {
            // Unregister progress handler from the shared session delegate
            // before cancelling, so no stale callbacks fire.
            sessionPoolLock.lock()
            for delegate in delegatePool.values {
                delegate.unregister(taskIdentifier: task.taskIdentifier)
            }
            sessionPoolLock.unlock()
            
            task.cancel()
        }
        
        removeRetryState(for: requestId)
    }
    
    // MARK: - Session Pool
    
    /**
     * Returns an existing session for the given host+timeout combination,
     * or creates a new one. Each session owns a SessionDelegate that routes
     * per-task progress events without needing a new URLSession per request.
     */
    private func getOrCreateSession(
        for url: URL,
        timeout: Double,
        certificateValidator: CertificateValidator?
    ) -> (URLSession, SessionDelegate) {
        let host = url.host ?? "default"
        let poolKey = "\(host)_\(timeout)"
        
        sessionPoolLock.lock()
        defer { sessionPoolLock.unlock() }
        
        if let existingSession = sessionPool[poolKey],
           let existingDelegate = delegatePool[poolKey] {
            TNMLogger.debug("Reusing session from pool", feature: "Request", details: [
                "host": host,
                "timeout": String(format: "%.1f seconds", timeout)
            ])
            return (existingSession, existingDelegate)
        }
        
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout
        
        let delegate = SessionDelegate(certificateValidator: certificateValidator)
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        
        sessionPool[poolKey] = session
        delegatePool[poolKey] = delegate
        
        TNMLogger.debug("Created new session in pool", feature: "Request", details: [
            "host": host,
            "timeout": String(format: "%.1f seconds", timeout),
            "poolSize": sessionPool.count
        ])
        
        return (session, delegate)
    }
    
    // MARK: - Private Methods
    
    private func executeWithRetry(
        currentAttempt: Int,
        requestId: String,
        session: URLSession,
        sessionDelegate: SessionDelegate,
        url: URL,
        method: String,
        headers: [String: String]?,
        body: Data?,
        priority: Float,
        retryConfig: RetryConfiguration?,
        onProgress: ((Int64, Int64) -> Void)?,
        attempt: Int,
        startTime: Date,
        onComplete: @escaping (Int, [String: String], Data?) -> Void,
        onError: @escaping (Error, Bool) -> Void
    ) {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        
        var currentAttemptCounter = currentAttempt
        
        if let headers = headers {
            for (key, value) in headers {
                request.setValue(value, forHTTPHeaderField: key)
            }
        }
        
        TNMLogger.debug("Creating request task", feature: "Request", details: [
            "requestId": requestId,
            "attempt": attempt,
            "hasRetryConfig": retryConfig != nil,
            "currentAttemptCounter": currentAttemptCounter
        ])
        
        let task = session.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            
            // Unregister progress handler now that the task is done
            sessionDelegate.unregister(taskIdentifier: (self.activeTask(for: requestId)?.taskIdentifier ?? -1))
            
            if let error = error {
                let errorCopy = NSError(
                    domain: (error as NSError).domain,
                    code: (error as NSError).code,
                    userInfo: (error as NSError).userInfo
                )

                let willActuallyRetry = retryConfig != nil
                    && attempt < retryConfig!.maxRetries
                    && self.shouldRetry(error: errorCopy, retryConfig: retryConfig!)

                DispatchQueue.main.async {
                    onError(errorCopy, willActuallyRetry)
                }

                if willActuallyRetry {
                    currentAttemptCounter = currentAttemptCounter + 1

                    let delay = self.calculateRetryDelay(
                        attempt: attempt,
                        backoffType: retryConfig!.backoffType,
                        baseDelay: retryConfig!.baseDelay
                    )

                    TNMLogger.Retry.attempting(
                        attempt: attempt + 1,
                        maxAttempts: retryConfig!.maxRetries,
                        delay: delay
                    )

                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                        self.executeWithRetry(
                            currentAttempt: currentAttemptCounter,
                            requestId: requestId,
                            session: session,
                            sessionDelegate: sessionDelegate,
                            url: url,
                            method: method,
                            headers: headers,
                            body: body,
                            priority: priority,
                            retryConfig: retryConfig,
                            onProgress: onProgress,
                            attempt: attempt + 1,
                            startTime: startTime,
                            onComplete: onComplete,
                            onError: onError
                        )
                    }
                } else {
                    if let retryConfig = retryConfig, attempt >= retryConfig.maxRetries {
                        TNMLogger.Retry.exhausted(attempts: attempt)
                    }

                    self.removeActiveTask(for: requestId)
                    self.removeRetryState(for: requestId)

                    TNMLogger.Request.error(requestId: requestId, error: errorCopy)
                }
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                let error = NSError(
                    domain: "TNMRequestManager",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Invalid response"]
                )
                self.removeActiveTask(for: requestId)
                
                TNMLogger.Request.error(requestId: requestId, error: error)
                
                DispatchQueue.main.async {
                    onError(error, false)
                }
                return
            }
            
            let statusCode = httpResponse.statusCode
            
            if let retryConfig = retryConfig,
               attempt < retryConfig.maxRetries,
               retryConfig.retryOn.contains(statusCode) {
                
                let delay = self.calculateRetryDelay(
                    attempt: attempt,
                    backoffType: retryConfig.backoffType,
                    baseDelay: retryConfig.baseDelay
                )
                
                TNMLogger.Retry.attempting(
                    attempt: attempt + 1,
                    maxAttempts: retryConfig.maxRetries,
                    delay: delay
                )
                
                let error = NSError(
                    domain: "TNMRequestManager",
                    code: statusCode,
                    userInfo: [NSLocalizedDescriptionKey: "HTTP \(statusCode)"]
                )
                
                DispatchQueue.main.async {
                    onError(error, true)
                }
                
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    self.executeWithRetry(
                        currentAttempt: currentAttemptCounter,
                        requestId: requestId,
                        session: session,
                        sessionDelegate: sessionDelegate,
                        url: url,
                        method: method,
                        headers: headers,
                        body: body,
                        priority: priority,
                        retryConfig: retryConfig,
                        onProgress: onProgress,
                        attempt: attempt + 1,
                        startTime: startTime,
                        onComplete: onComplete,
                        onError: onError
                    )
                }
                return
            }
            
            // Success or non-retryable status
            let statusCodeValue = httpResponse.statusCode
            
            var responseHeaders: [String: String] = [:]
            for (key, value) in httpResponse.allHeaderFields {
                if let keyString = key as? String, let valueString = value as? String {
                    responseHeaders[String(keyString)] = String(valueString)
                }
            }
            
            let dataCopy: Data?
            if let data = data {
                dataCopy = Data(data)
            } else {
                dataCopy = nil
            }
            
            self.removeActiveTask(for: requestId)
            self.removeRetryState(for: requestId)
            
            let duration = Date().timeIntervalSince(startTime)
            TNMLogger.Request.completed(
                requestId: requestId,
                statusCode: statusCodeValue,
                duration: duration
            )
            
            DispatchQueue.main.async {
                onComplete(statusCodeValue, responseHeaders, dataCopy)
            }
        }
        
        // Register progress handler BEFORE resuming, to avoid missing early events
        if let onProgress = onProgress {
            sessionDelegate.register(
                taskIdentifier: task.taskIdentifier,
                requestId: requestId,
                onProgress: onProgress
            )
        }
        
        task.priority = priority
        setActiveTask(task, for: requestId)
        task.resume()
    }
    
    private func shouldRetry(error: Error, retryConfig: RetryConfiguration) -> Bool {
        let nsError = error as NSError
        
        // Transient network errors that make sense to retry automatically.
        // NSURLErrorTimedOut is intentionally excluded: the developer explicitly
        // chose a timeout value, so treating it as a retryable condition would
        // silently multiply the effective wait time by maxRetries. If the caller
        // wants to retry on timeout, they should include the HTTP status code
        // equivalent or handle it in their own error callback.
        let retryableErrors = [
            NSURLErrorCannotFindHost,
            NSURLErrorCannotConnectToHost,
            NSURLErrorNetworkConnectionLost,
            NSURLErrorDNSLookupFailed,
            NSURLErrorNotConnectedToInternet
        ]
        
        let isRetryable = retryableErrors.contains(nsError.code)
        
        TNMLogger.debug("Checking if error is retryable", feature: "Retry", details: [
            "errorCode": nsError.code,
            "errorDomain": nsError.domain,
            "isRetryable": isRetryable
        ])
        
        return isRetryable
    }
    
    private func calculateRetryDelay(
        attempt: Int,
        backoffType: String,
        baseDelay: Double
    ) -> TimeInterval {
        let delay: TimeInterval
        
        switch backoffType {
        case "exponential":
            delay = baseDelay * pow(2.0, Double(attempt - 1))
        case "linear":
            delay = baseDelay * Double(attempt)
        default:
            delay = baseDelay
        }
        
        TNMLogger.debug("Retry delay calculated", feature: "Retry", details: [
            "attempt": attempt,
            "backoffType": backoffType,
            "delay": String(format: "%.1f seconds", delay)
        ])
        
        return delay
    }
    
    private func priorityToString(_ priority: Float) -> String {
        if priority == URLSessionTask.highPriority {
            return "high"
        } else if priority == URLSessionTask.lowPriority {
            return "low"
        } else {
            return "normal"
        }
    }
}

// MARK: - Retry Configuration

struct RetryConfiguration {
    let maxRetries: Int
    let retryOn: [Int]
    let backoffType: String
    let baseDelay: TimeInterval
    
    init(params: [String: Any]) {
        // Titanium's Kroll bridge converts all JS numbers (which are doubles)
        // to NSNumber wrapping a Double. Swift's `as? Int` fails for those,
        // so we try Int first (direct integer NSNumber) and fall back to Double.
        if let v = params["max"] as? Int {
            maxRetries = v
        } else if let v = params["max"] as? Double {
            maxRetries = Int(v)
        } else {
            maxRetries = 3
        }
        
        // Same issue for the retryOn array: JS [500, 503] arrives as [NSNumber(double)],
        // so [Int] cast fails. Try both element types.
        if let array = params["retryOn"] as? [Int] {
            retryOn = array
        } else if let array = params["retryOn"] as? [Double] {
            retryOn = array.map { Int($0) }
        } else {
            retryOn = [500, 502, 503, 504]
        }
        
        backoffType = params["backoff"] as? String ?? "exponential"
        baseDelay = params["baseDelay"] as? TimeInterval ?? 1.0
        
        TNMLogger.debug("Retry configuration created", feature: "Retry", details: [
            "maxRetries": maxRetries,
            "retryOn": retryOn.map { String($0) }.joined(separator: ", "),
            "backoffType": backoffType,
            "baseDelay": String(format: "%.1f seconds", baseDelay)
        ])
    }
}

// MARK: - Retry State

struct RetryState {
    var attempts: Int
    var lastError: Error?
}

// MARK: - Session Delegate
//
// Shared across all requests to the same host. Routes progress and certificate
// events to the right per-task handler without needing a new URLSession per request.

class SessionDelegate: NSObject, URLSessionDataDelegate {
    
    private let certificateValidator: CertificateValidator?
    
    // taskIdentifier -> (requestId, progressCallback)
    private var progressHandlers: [Int: (String, (Int64, Int64) -> Void)] = [:]
    private let handlersLock = NSLock()
    
    init(certificateValidator: CertificateValidator?) {
        self.certificateValidator = certificateValidator
    }
    
    func register(
        taskIdentifier: Int,
        requestId: String,
        onProgress: @escaping (Int64, Int64) -> Void
    ) {
        handlersLock.lock()
        progressHandlers[taskIdentifier] = (requestId, onProgress)
        handlersLock.unlock()
    }
    
    func unregister(taskIdentifier: Int) {
        handlersLock.lock()
        progressHandlers.removeValue(forKey: taskIdentifier)
        handlersLock.unlock()
    }
    
    // Progress tracking — routed by taskIdentifier
    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive data: Data
    ) {
        handlersLock.lock()
        let entry = progressHandlers[dataTask.taskIdentifier]
        handlersLock.unlock()
        
        guard let (requestId, onProgress) = entry else { return }
        
        let received = dataTask.countOfBytesReceived
        let expected = dataTask.countOfBytesExpectedToReceive
        
        TNMLogger.Request.progress(
            requestId: requestId,
            received: received,
            total: expected
        )
        
        DispatchQueue.main.async {
            onProgress(received, expected)
        }
    }
    
    // Certificate validation — same for all tasks in this session (same host)
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard let certificateValidator = certificateValidator else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        
        if certificateValidator.validate(serverTrust: serverTrust, for: challenge.protectionSpace.host) {
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
        } else {
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }
}
