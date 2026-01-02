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
        
        // Store delegate
        streamDelegates[requestId] = delegate
        
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
        
        activeSessions[requestId] = session
        
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
        
        activeDataTasks[requestId] = task
        
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
        
        activeDataTasks[requestId]?.cancel()
        activeSessions[requestId]?.invalidateAndCancel()
        
        activeDataTasks.removeValue(forKey: requestId)
        activeSessions.removeValue(forKey: requestId)
        streamDelegates.removeValue(forKey: requestId)
    }
    
    /**
     * Cancel all active streams
     */
    func cancelAllStreams() {
        TNMLogger.info("Cancelling all streams", feature: "Streaming", details: [
            "activeStreams": activeSessions.count
        ])
        
        for (requestId, _) in activeSessions {
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
