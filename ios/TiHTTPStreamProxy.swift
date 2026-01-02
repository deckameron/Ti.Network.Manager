//
//  TiHTTPStreamProxy.swift
//  TiNetworkManager
//
//  Created by Douglas Alves on 02/01/26.
//


/**
 * Ti.Network.Manager - Stream Proxy
 * Proxy for streaming HTTP requests
 * Exposed to JavaScript for creating streaming connections (SSE, AI APIs, etc.)
 */

import TitaniumKit
import Foundation

@objc(TiHTTPStreamProxy)
class TiHTTPStreamProxy: TiProxy {
    
    // MARK: - Properties
    
    private var streamManager: TNMStreamManager
    private var interceptorManager: TNMInterceptorManager
    private var certificatePinningManager: TNMCertificatePinningManager
    
    private var requestId: String
    private var url: String
    private var method: String
    private var headers: [String: String]
    private var body: String?
    private var priority: String
    
    private var isActive = false
    private var startTime: Date?
    
    // MARK: - Initialization
    
    init(
        params: [String: Any],
        streamManager: TNMStreamManager,
        interceptorManager: TNMInterceptorManager,
        certificatePinningManager: TNMCertificatePinningManager
    ) {
        self.streamManager = streamManager
        self.interceptorManager = interceptorManager
        self.certificatePinningManager = certificatePinningManager
        
        // Generate unique request ID
        self.requestId = UUID().uuidString
        
        // Extract parameters with proper unwrapping
        self.url = params["url"] as? String ?? ""
        self.method = (params["method"] as? String ?? "GET").uppercased()
        self.headers = params["headers"] as? [String: String] ?? [:]
        self.body = params["body"] as? String
        self.priority = params["priority"] as? String ?? "normal"
        
        super.init()
        
        TNMLogger.debug("Stream proxy created", feature: "Streaming", details: [
            "requestId": requestId,
            "url": url,
            "method": method,
            "priority": priority
        ])
    }
    
    // MARK: - Public API
    
    /**
     * Start the streaming request
     * 
     * @param arguments Unused arguments array (required by Titanium)
     */
    @objc(start:)
    func start(arguments: [Any]?) {
        guard !isActive else {
            TNMLogger.warning("Stream already started", feature: "Streaming", details: [
                "requestId": requestId
            ])
            return
        }
        
        guard let url = URL(string: self.url) else {
            TNMLogger.error("Invalid URL for streaming request", feature: "Streaming", details: [
                "requestId": requestId,
                "url": self.url
            ])
            fireEvent("error", with: ["error": "Invalid URL"])
            return
        }
        
        isActive = true
        startTime = Date()
        
        TNMLogger.Streaming.started(requestId: requestId, url: self.url)
        
        // Apply request interceptors
        var modifiedHeaders = headers
        var modifiedBody = body
        
        interceptorManager.interceptRequest(
            url: self.url,
            method: method,
            headers: &modifiedHeaders,
            body: &modifiedBody
        )
        
        // Convert priority
        let urlPriority: Float
        switch priority {
        case "high":
            urlPriority = URLSessionTask.highPriority
        case "low":
            urlPriority = URLSessionTask.lowPriority
        default:
            urlPriority = URLSessionTask.defaultPriority
        }
        
        TNMLogger.debug("Stream priority set", feature: "Streaming", details: [
            "requestId": requestId,
            "priority": priority
        ])
        
        // Convert body to Data
        var bodyData: Data?
        if let bodyString = modifiedBody {
            bodyData = bodyString.data(using: .utf8)
        }
        
        // Get certificate validator if needed
        let certificateValidator = certificatePinningManager.getValidator(for: url.host ?? "")
        
        // Start streaming
        streamManager.startStream(
            requestId: requestId,
            url: url,
            method: method,
            headers: modifiedHeaders,
            body: bodyData,
            priority: urlPriority,
            certificateValidator: certificateValidator,
            onChunk: { [weak self] chunk in
                self?.handleChunk(chunk)
            },
            onComplete: { [weak self] statusCode, headers in
                self?.handleComplete(statusCode: statusCode, headers: headers)
            },
            onError: { [weak self] error in
                self?.handleError(error)
            }
        )
    }
    
    /**
     * Cancel the streaming request
     * 
     * @param arguments Unused arguments array (required by Titanium)
     */
    @objc(cancel:)
    func cancel(arguments: [Any]?) {
        guard isActive else { return }
        
        TNMLogger.Streaming.cancelled(requestId: requestId)
        
        streamManager.cancelStream(requestId: requestId)
        isActive = false
        
        fireEvent("cancelled", with: [:])
    }
    
    // MARK: - Event Handlers
    
    private func handleChunk(_ chunk: String) {
        guard isActive else { return }
        
        TNMLogger.Streaming.chunkReceived(
            requestId: requestId,
            size: chunk.utf8.count,
            totalSize: 0 // We don't track total in streaming
        )
        
        // Fire chunk event to JavaScript
        fireEvent("chunk", with: [
            "data": chunk
        ])
    }
    
    private func handleComplete(statusCode: Int, headers: [String: String]) {
        guard isActive else { return }
        
        isActive = false
        
        let duration = startTime.map { Date().timeIntervalSince($0) } ?? 0
        
        TNMLogger.Streaming.completed(
            requestId: requestId,
            statusCode: statusCode,
            totalBytes: 0 // Total bytes not tracked in streaming
        )
        
        // Apply response interceptors
        var modifiedStatusCode = statusCode
        var modifiedHeaders = headers
        
        interceptorManager.interceptResponse(
            statusCode: &modifiedStatusCode,
            headers: &modifiedHeaders,
            body: nil
        )
        
        // Fire complete event
        fireEvent("complete", with: [
            "statusCode": modifiedStatusCode,
            "headers": modifiedHeaders,
            "duration": duration
        ])
    }
    
    private func handleError(_ error: Error) {
        guard isActive else { return }
        
        isActive = false
        
        TNMLogger.Streaming.error(requestId: requestId, error: error)
        
        fireEvent("error", with: [
            "error": error.localizedDescription,
            "code": (error as NSError).code
        ])
    }
}
