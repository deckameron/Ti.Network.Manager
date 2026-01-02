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
 */

import Foundation

class TNMRequestManager {
    
    // MARK: - Properties
    
    private var activeTasks: [String: URLSessionDataTask] = [:]
    private var retryState: [String: RetryState] = [:]
    
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
        retryConfig: RetryConfiguration?,
        certificateValidator: CertificateValidator?,
        onProgress: ((Int64, Int64) -> Void)?,
        onComplete: @escaping (Int, [String: String], Data?) -> Void,
        onError: @escaping (Error, Bool) -> Void // Bool indicates if will retry
    ) {
        TNMLogger.Request.created(requestId: requestId, url: url.absoluteString, method: method)
        
        let priorityString = priorityToString(priority)
        TNMLogger.Request.started(requestId: requestId, priority: priorityString)
        
        // Create session with certificate validation
        let delegate = RequestDelegate(
            requestId: requestId,
            certificateValidator: certificateValidator,
            onProgress: onProgress
        )
        
        let session = URLSession(
            configuration: .default,
            delegate: delegate,
            delegateQueue: nil
        )
        
        // Execute with retry
        executeWithRetry(
            requestId: requestId,
            session: session,
            url: url,
            method: method,
            headers: headers,
            body: body,
            priority: priority,
            retryConfig: retryConfig,
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
        
        activeTasks[requestId]?.cancel()
        activeTasks.removeValue(forKey: requestId)
        retryState.removeValue(forKey: requestId)
    }
    
    // MARK: - Private Methods
    
    private func executeWithRetry(
        requestId: String,
        session: URLSession,
        url: URL,
        method: String,
        headers: [String: String]?,
        body: Data?,
        priority: Float,
        retryConfig: RetryConfiguration?,
        attempt: Int,
        startTime: Date,
        onComplete: @escaping (Int, [String: String], Data?) -> Void,
        onError: @escaping (Error, Bool) -> Void
    ) {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        
        // Add headers
        if let headers = headers {
            for (key, value) in headers {
                request.setValue(value, forHTTPHeaderField: key)
            }
        }
        
        TNMLogger.debug("Creating request task", feature: "Request", details: [
            "requestId": requestId,
            "attempt": attempt,
            "hasRetryConfig": retryConfig != nil
        ])
        
        let task = session.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            
            if let error = error {
                // Check if should retry
                if let retryConfig = retryConfig,
                   attempt < retryConfig.maxRetries,
                   self.shouldRetry(error: error, retryConfig: retryConfig) {
                    
                    // Calculate delay
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
                    
                    // Notify that we will retry
                    onError(error, true)
                    
                    // Retry after delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                        self.executeWithRetry(
                            requestId: requestId,
                            session: session,
                            url: url,
                            method: method,
                            headers: headers,
                            body: body,
                            priority: priority,
                            retryConfig: retryConfig,
                            attempt: attempt + 1,
                            startTime: startTime,
                            onComplete: onComplete,
                            onError: onError
                        )
                    }
                } else {
                    // No retry, final error
                    if let retryConfig = retryConfig, attempt >= retryConfig.maxRetries {
                        TNMLogger.Retry.exhausted(attempts: attempt)
                    }
                    
                    self.activeTasks.removeValue(forKey: requestId)
                    self.retryState.removeValue(forKey: requestId)
                    
                    TNMLogger.Request.error(requestId: requestId, error: error)
                    onError(error, false)
                }
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                let error = NSError(
                    domain: "TNMRequestManager",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Invalid response"]
                )
                self.activeTasks.removeValue(forKey: requestId)
                
                TNMLogger.Request.error(requestId: requestId, error: error)
                onError(error, false)
                return
            }
            
            let statusCode = httpResponse.statusCode
            
            // Check if should retry based on status code
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
                
                onError(error, true)
                
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    self.executeWithRetry(
                        requestId: requestId,
                        session: session,
                        url: url,
                        method: method,
                        headers: headers,
                        body: body,
                        priority: priority,
                        retryConfig: retryConfig,
                        attempt: attempt + 1,
                        startTime: startTime,
                        onComplete: onComplete,
                        onError: onError
                    )
                }
                return
            }
            
            // Success or non-retryable status
            var responseHeaders: [String: String] = [:]
            for (key, value) in httpResponse.allHeaderFields {
                if let keyString = key as? String, let valueString = value as? String {
                    responseHeaders[keyString] = valueString
                }
            }
            
            self.activeTasks.removeValue(forKey: requestId)
            self.retryState.removeValue(forKey: requestId)
            
            let duration = Date().timeIntervalSince(startTime)
            TNMLogger.Request.completed(
                requestId: requestId,
                statusCode: statusCode,
                duration: duration
            )
            
            onComplete(statusCode, responseHeaders, data)
        }
        
        task.priority = priority
        activeTasks[requestId] = task
        task.resume()
    }
    
    private func shouldRetry(error: Error, retryConfig: RetryConfiguration) -> Bool {
        let nsError = error as NSError
        
        // Network errors that are retryable
        let retryableErrors = [
            NSURLErrorTimedOut,
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
            // 2^attempt * baseDelay (e.g., 1s, 2s, 4s, 8s)
            delay = baseDelay * pow(2.0, Double(attempt - 1))
        case "linear":
            // attempt * baseDelay (e.g., 1s, 2s, 3s, 4s)
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
    let retryOn: [Int] // HTTP status codes to retry on
    let backoffType: String // "exponential" or "linear"
    let baseDelay: TimeInterval // Base delay in seconds
    
    init(params: [String: Any]) {
        maxRetries = params["max"] as? Int ?? 3
        retryOn = params["retryOn"] as? [Int] ?? [500, 502, 503, 504]
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

// MARK: - Request Delegate

class RequestDelegate: NSObject, URLSessionDataDelegate {
    
    private let requestId: String
    private let certificateValidator: CertificateValidator?
    private let onProgress: ((Int64, Int64) -> Void)?
    
    init(
        requestId: String,
        certificateValidator: CertificateValidator?,
        onProgress: ((Int64, Int64) -> Void)?
    ) {
        self.requestId = requestId
        self.certificateValidator = certificateValidator
        self.onProgress = onProgress
    }
    
    // Progress tracking
    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive data: Data
    ) {
        if let onProgress = onProgress {
            let received = dataTask.countOfBytesReceived
            let expected = dataTask.countOfBytesExpectedToReceive
            
            TNMLogger.Request.progress(
                requestId: requestId,
                received: received,
                total: expected
            )
            
            onProgress(received, expected)
        }
    }
    
    // Certificate validation
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard let certificateValidator = certificateValidator else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust {
            if let serverTrust = challenge.protectionSpace.serverTrust {
                if certificateValidator.validate(serverTrust: serverTrust, for: challenge.protectionSpace.host) {
                    let credential = URLCredential(trust: serverTrust)
                    completionHandler(.useCredential, credential)
                } else {
                    completionHandler(.cancelAuthenticationChallenge, nil)
                }
            } else {
                completionHandler(.cancelAuthenticationChallenge, nil)
            }
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}
