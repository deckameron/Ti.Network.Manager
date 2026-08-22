//
//  TNMStreamManager.swift
//  TiNetworkManager
//
//  Created by Douglas Alves on 02/01/26.
//


/**
 * Ti.Network.Manager - Stream Manager
 * Handles streaming HTTP responses
 * Supports Server-Sent Events (SSE) and chunked transfer encoding
 */

import Foundation

class TNMStreamManager: NSObject {
    
    // MARK: - Properties
    
    private var activeSessions: [String: URLSession] = [:]
    private var activeDataTasks: [String: URLSessionDataTask] = [:]
    private var streamDelegates: [String: StreamDelegate] = [:]

    // Cleanup on completion arrives on the URLSession delegate queue while
    // startStream/cancelStream run on the caller's thread, so every access to the three
    // dictionaries above goes through stateLock. A Swift Dictionary is not thread-safe.
    private let stateLock = NSLock()

    // MARK: - Synchronized State Access

    private func registerStream(
        task: URLSessionDataTask,
        delegate: StreamDelegate,
        session: URLSession,
        for requestId: String
    ) {
        stateLock.lock()
        defer { stateLock.unlock() }
        activeDataTasks[requestId] = task
        streamDelegates[requestId] = delegate
        activeSessions[requestId] = session
    }

    /// Drops every entry for the stream and hands the task and session back so the
    /// caller can cancel/invalidate them *outside* the critical section.
    private func removeStream(for requestId: String) -> (URLSessionDataTask?, URLSession?) {
        stateLock.lock()
        defer { stateLock.unlock() }
        streamDelegates.removeValue(forKey: requestId)
        return (activeDataTasks.removeValue(forKey: requestId), activeSessions.removeValue(forKey: requestId))
    }

    private func activeStreamIds() -> [String] {
        stateLock.lock()
        defer { stateLock.unlock() }
        return Array(activeSessions.keys)
    }

    /// Called from the delegate once the task reached a terminal state. Without this the
    /// three entries lived forever and, because a URLSession retains its delegate until
    /// it is invalidated, every finished stream leaked its session, its delegate and all
    /// the callbacks the delegate captured.
    private func finishStream(requestId: String) {
        let (_, session) = removeStream(for: requestId)
        session?.finishTasksAndInvalidate()
    }

    // MARK: - Public Methods
    
    /**
     * Start a streaming request
     */
    func startStream(
        requestId: String,
        url: URL,
        method: String,
        headers: [String: String]?,
        body: Data?,
        priority: Float,
        certificateValidator: CertificateValidator?,
        onChunk: @escaping (String) -> Void,
        onComplete: @escaping (Int, [String: String]) -> Void,
        onError: @escaping (Error) -> Void
    ) {
        TNMLogger.Streaming.started(requestId: requestId, url: url.absoluteString)
        
        // Create delegate
        let delegate = StreamDelegate(
            requestId: requestId,
            onChunk: onChunk,
            onComplete: onComplete,
            onError: onError,
            certificateValidator: certificateValidator
        )
        
        // Weak self: the manager owns the delegate, so a strong capture would be a cycle.
        delegate.onFinished = { [weak self] finishedId in
            self?.finishStream(requestId: finishedId)
        }
        
        // Create session configuration
        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = headers
        config.timeoutIntervalForRequest = 300 // 5 minutes for long-running streams
        config.timeoutIntervalForResource = 300
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        
        TNMLogger.debug("Stream session configured", feature: "Streaming", details: [
            "requestId": requestId,
            "timeout": "300 seconds",
            "cachePolicy": "reloadIgnoringLocalCacheData"
        ])
        
        // Create session with delegate
        let session = URLSession(
            configuration: config,
            delegate: delegate,
            delegateQueue: nil
        )
        
        // Create request
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        
        // Add headers for SSE
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        
        // Create data task
        let task = session.dataTask(with: request)
        task.priority = priority
        
        // Register in one critical section, before resume(), so the delegate queue never
        // observes a half-registered stream.
        registerStream(task: task, delegate: delegate, session: session, for: requestId)
        
        TNMLogger.debug("Stream task created", feature: "Streaming", details: [
            "requestId": requestId,
            "priority": priorityToString(priority)
        ])
        
        // Start task
        task.resume()
    }
    
    /**
     * Cancel a streaming request
     */
    func cancelStream(requestId: String) {
        TNMLogger.debug("Cancelling stream", feature: "Streaming", details: [
            "requestId": requestId
        ])
        
        // Remove first, then call out: never hold stateLock while touching URLSession.
        let (task, session) = removeStream(for: requestId)
        task?.cancel()
        session?.invalidateAndCancel()
    }
    
    /**
     * Cancel all active streams
     */
    func cancelAllStreams() {
        TNMLogger.info("Cancelling all streams", feature: "Streaming", details: [
            "activeStreams": activeStreamIds().count
        ])
        
        for requestId in activeStreamIds() {
            cancelStream(requestId: requestId)
        }
    }
    
    // MARK: - Helpers
    
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

// MARK: - Stream Delegate

class StreamDelegate: NSObject, URLSessionDataDelegate {
    
    private let requestId: String
    private let onChunk: (String) -> Void
    private let onComplete: (Int, [String: String]) -> Void
    private let onError: (Error) -> Void
    private let certificateValidator: CertificateValidator?
    
    /// Set by the manager so it can drop its bookkeeping and invalidate the session
    /// once the task reaches a terminal state.
    var onFinished: ((String) -> Void)?
    
    private var buffer = Data()
    private var statusCode: Int = 0
    private var responseHeaders: [String: String] = [:]
    private var totalBytesReceived: Int = 0
    
    init(
        requestId: String,
        onChunk: @escaping (String) -> Void,
        onComplete: @escaping (Int, [String: String]) -> Void,
        onError: @escaping (Error) -> Void,
        certificateValidator: CertificateValidator?
    ) {
        self.requestId = requestId
        self.onChunk = onChunk
        self.onComplete = onComplete
        self.onError = onError
        self.certificateValidator = certificateValidator
    }
    
    // MARK: - URLSessionDataDelegate
    
    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        if let httpResponse = response as? HTTPURLResponse {
            statusCode = httpResponse.statusCode
            
            TNMLogger.debug("Stream response received", feature: "Streaming", details: [
                "requestId": requestId,
                "statusCode": statusCode
            ])
            
            // Convert headers
            for (key, value) in httpResponse.allHeaderFields {
                if let keyString = key as? String, let valueString = value as? String {
                    responseHeaders[keyString] = valueString
                }
            }
        }
        
        completionHandler(.allow)
    }
    
    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive data: Data
    ) {
        // Add to buffer
        buffer.append(data)
        totalBytesReceived += data.count
        
        TNMLogger.Streaming.chunkReceived(
            requestId: requestId,
            size: data.count,
            totalSize: totalBytesReceived
        )
        
        // Try to parse SSE chunks
        parseSSEChunks()
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            // Check if it was cancelled
            if (error as NSError).code == NSURLErrorCancelled {
                TNMLogger.debug("Stream was cancelled", feature: "Streaming", details: [
                    "requestId": requestId
                ])
                // cancelStream() already cleaned up, but a cancel can also come from
                // elsewhere (backgrounding, system teardown); the cleanup is idempotent.
                onFinished?(requestId)
                return
            }
            
            TNMLogger.Streaming.error(requestId: requestId, error: error)
            onError(error)
        } else {
            // Process any remaining data
            if !buffer.isEmpty {
                parseSSEChunks(flush: true)
            }
            
            TNMLogger.Streaming.completed(
                requestId: requestId,
                statusCode: statusCode,
                totalBytes: totalBytesReceived
            )
            
            onComplete(statusCode, responseHeaders)
        }
        
        onFinished?(requestId)
    }
    
    // MARK: - Certificate Pinning
    
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard let certificateValidator = certificateValidator else {
            // No pinning configured, use default handling
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
    
    // MARK: - SSE Parsing
    
    private func parseSSEChunks(flush: Bool = false) {
        // SSE format: "data: {...}\n\n"
        let delimiter = "\n\n".data(using: .utf8)!
        
        while true {
            guard let range = buffer.range(of: delimiter) else {
                // No complete chunk found
                if flush && !buffer.isEmpty {
                    // Flush remaining data
                    if let chunk = String(data: buffer, encoding: .utf8) {
                        processSSEChunk(chunk)
                    }
                    buffer.removeAll()
                }
                break
            }
            
            // Extract chunk
            let chunkData = buffer.subdata(in: 0..<range.lowerBound)
            
            // Remove chunk from buffer
            buffer.removeSubrange(0..<range.upperBound)
            
            // Convert to string and process
            if let chunk = String(data: chunkData, encoding: .utf8) {
                processSSEChunk(chunk)
            }
        }
    }
    
    private func processSSEChunk(_ chunk: String) {
        // Parse SSE lines
        let lines = chunk.components(separatedBy: "\n")
        var eventData = ""
        var eventType = "message"
        
        for line in lines {
            if line.hasPrefix("data:") {
                // Extract data
                let data = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                eventData += data
            } else if line.hasPrefix("event:") {
                // Extract event type
                eventType = line.dropFirst(6).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix(":") {
                // Comment, ignore
                continue
            }
        }
        
        if !eventData.isEmpty {
            // Log custom event types
            if eventType != "message" {
                TNMLogger.debug("SSE custom event type received", feature: "Streaming", details: [
                    "eventType": eventType,
                    "requestId": requestId
                ])
            }
            
            // Fire chunk event
            onChunk(eventData)
        }
    }
}
