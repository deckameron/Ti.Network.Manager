//
//  TNMRequestProxy.swift
//  TiNetworkManager
//
//  Created by Douglas Alves on 02/01/26.
//


/**
 * Ti.Network.Manager - Request Proxy
 * Proxy for standard HTTP requests
 * Supports caching, retry, prioritization, and all advanced features
 */

import TitaniumKit
import Foundation

@objc(TiHTTPRequestProxy)
class TNMRequestProxy: TiProxy {
    
    // MARK: - Properties
    
    private var requestManager: TNMRequestManager
    private var interceptorManager: TNMInterceptorManager
    private var cacheManager: TNMCacheManager
    private var certificatePinningManager: TNMCertificatePinningManager
    
    private var requestId: String
    private var url: String
    private var method: String
    private var headers: [String: String]
    private var body: String?
    private var priority: String
    private var cachePolicy: String?
    private var cacheTTL: TimeInterval?
    private var retryConfig: RetryConfiguration?
    
    private var isActive = false
    private var startTime: Date?
    
    // MARK: - Initialization
    
    init(
        params: [String: Any],
        requestManager: TNMRequestManager,
        interceptorManager: TNMInterceptorManager,
        cacheManager: TNMCacheManager,
        certificatePinningManager: TNMCertificatePinningManager
    ) {
        self.requestManager = requestManager
        self.interceptorManager = interceptorManager
        self.cacheManager = cacheManager
        self.certificatePinningManager = certificatePinningManager
        
        self.requestId = UUID().uuidString
        self.url = params["url"] as? String ?? ""
        self.method = (params["method"] as? String ?? "GET").uppercased()
        self.headers = params["headers"] as? [String: String] ?? [:]
        self.body = params["body"] as? String
        self.priority = params["priority"] as? String ?? "normal"
        
        // Cache configuration
        if let cacheConfig = params["cache"] as? [String: Any] {
            self.cachePolicy = cacheConfig["policy"] as? String
            self.cacheTTL = cacheConfig["ttl"] as? TimeInterval
        }
        
        // Retry configuration
        if let retryParams = params["retry"] as? [String: Any] {
            self.retryConfig = RetryConfiguration(params: retryParams)
        }
        
        super.init()
        
        TNMLogger.debug("Request proxy created", feature: "Request", details: [
            "requestId": requestId,
            "url": url,
            "method": method,
            "priority": priority,
            "cachePolicy": cachePolicy ?? "none"
        ])
    }
    
    // MARK: - Public API
    
    /**
     * Send the request
     *
     * @param arguments Unused arguments array (required by Titanium)
     */
    @objc(send:)
    func send(arguments: [Any]?) {
        guard !isActive else {
            TNMLogger.warning("Request already active", feature: "Request", details: [
                "requestId": requestId
            ])
            return
        }
        
        guard let url = URL(string: self.url) else {
            TNMLogger.error("Invalid URL for request", feature: "Request", details: [
                "requestId": requestId,
                "url": self.url
            ])
            fireEvent("error", with: ["error": "Invalid URL"])
            return
        }
        
        isActive = true
        startTime = Date()
        
        // Generate cache key
        let cacheKey = cacheManager.generateKey(url: self.url, method: method)
        
        // Check cache policy
        if let policy = cachePolicy, policy == "cache-first" {
            if let cachedEntry = cacheManager.getCachedResponse(for: cacheKey, maxAge: cacheTTL) {
                DispatchQueue.main.async { [weak self] in
                    autoreleasepool {
                        self?.handleCachedResponse(cachedEntry)
                    }
                }
                return
            }
        }
        
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
        
        TNMLogger.debug("Request priority set", feature: "Request", details: [
            "requestId": requestId,
            "priority": priority
        ])
        
        // Convert body
        var bodyData: Data?
        if let bodyString = modifiedBody {
            bodyData = bodyString.data(using: .utf8)
        }
        
        // Get certificate validator
        let certificateValidator = certificatePinningManager.getValidator(for: url.host ?? "")
        
        // Execute request
        requestManager.executeRequest(
            requestId: requestId,
            url: url,
            method: method,
            headers: modifiedHeaders,
            body: bodyData,
            priority: urlPriority,
            retryConfig: retryConfig,
            certificateValidator: certificateValidator,
            onProgress: { [weak self] received, total in
                self?.handleProgress(received: received, total: total)
            },
            onComplete: { [weak self] statusCode, headers, data in
                self?.handleComplete(
                    statusCode: statusCode,
                    headers: headers,
                    data: data,
                    cacheKey: cacheKey
                )
            },
            onError: { [weak self] error, willRetry in
                self?.handleError(error, willRetry: willRetry)
            }
        )
    }
    
    /**
     * Cancel the request
     *
     * @param arguments Unused arguments array (required by Titanium)
     */
    @objc(cancel:)
    func cancel(arguments: [Any]?) {
        guard isActive else { return }
        
        TNMLogger.Request.cancelled(requestId: requestId)
        
        requestManager.cancelRequest(requestId: requestId)
        isActive = false
        
        fireEvent("cancelled", with: [:])
    }
    
    // MARK: - Event Handlers
    
    private func handleProgress(received: Int64, total: Int64) {
        guard isActive else { return }
        
        let progress = total > 0 ? Double(received) / Double(total) : 0.0
        
        fireEvent("progress", with: [
            "received": received,
            "total": total,
            "progress": progress
        ])
    }
    
    private func handleComplete(
        statusCode: Int,
        headers: [String: String],
        data: Data?,
        cacheKey: String
    ) {
        guard isActive else { return }
        
        isActive = false
        
        // Apply response interceptors
        var modifiedStatusCode = statusCode
        var modifiedHeaders = headers
        var bodyString: String?
        
        if let data = data {
            bodyString = String(data: data, encoding: .utf8)
        }
        
        interceptorManager.interceptResponse(
            statusCode: &modifiedStatusCode,
            headers: &modifiedHeaders,
            body: bodyString
        )
        
        // Cache if policy allows and status is 200
        if let policy = cachePolicy,
           policy != "network-only",
           modifiedStatusCode == 200,
           let data = data {
            
            let etag = modifiedHeaders["ETag"]
            cacheManager.cacheResponse(
                for: cacheKey,
                statusCode: modifiedStatusCode,
                headers: modifiedHeaders,
                body: data,
                etag: etag
            )
        }
        
        let duration = startTime.map { Date().timeIntervalSince($0) } ?? 0
        
        // Fire event
        fireEvent("complete", with: [
            "statusCode": modifiedStatusCode,
            "headers": modifiedHeaders,
            "body": bodyString ?? "",
            "success": modifiedStatusCode >= 200 && modifiedStatusCode < 300,
            "duration": duration,
            "cached": false
        ])
    }
    
    private func handleCachedResponse(_ entry: CacheEntry) {
        
        isActive = false
        
        TNMLogger.debug("Returning cached response", feature: "Request", details: [
            "requestId": requestId,
            "statusCode": entry.statusCode
        ])
        
       
        fireEvent("complete", with: [
            "statusCode": entry.statusCode,
            "headers": entry.headers,
            "body": entry.bodyString,
            "success": true,
            "cached": true,
            "duration": 0
        ])
    }
    
    private func handleError(_ error: Error, willRetry: Bool) {
        if !willRetry {
            isActive = false
        }
        
        fireEvent("error", with: [
            "error": error.localizedDescription,
            "code": (error as NSError).code,
            "willRetry": willRetry
        ])
    }
}
