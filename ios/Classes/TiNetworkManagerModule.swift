//
//  TiNetworkManagerModule.swift
//  Ti.Network.Manager
//
//  Created by Douglas Alves
//  Copyright (c) 2026 Upflix Inc. All rights reserved.
//


/**
 * Ti.Network.Manager - Advanced HTTP Module for Titanium SDK
 *
 * Features:
 * 1. Streaming Responses (SSE)
 * 2. Certificate Pinning
 * 3. Request/Response Interceptors
 * 4. Automatic Retry with Backoff
 * 5. Advanced Caching
 * 6. Background Transfers
 * 7. Request Prioritization
 * 8. Multipart Upload Progress
 * 9. HTTP/2 & HTTP/3 Support
 * 10. WebSocket Support
 */

import UIKit
import TitaniumKit
import Foundation

@objc(TiNetworkManagerModule)
class TiNetworkManagerModule: TiModule {
    
    // MARK: - Properties
    
    private var requestManager: TNMRequestManager!
    private var streamManager: TNMStreamManager!
    private var certificatePinningManager: TNMCertificatePinningManager!
    private var cacheManager: TNMCacheManager!
    private var interceptorManager: TNMInterceptorManager!
    private var websocketManager: TNMWebSocketManager!
    private var backgroundTransferManager: TNMBackgroundTransferManager!
    private var multipartUploadManager: TNMMultipartUploadManager!
    
    // MARK: - Lifecycle
    
    func moduleGUID() -> String {
        return "8e7c8f9a-1b2c-3d4e-5f6g-7h8i9j0k1l2m"
    }
    
    override func moduleId() -> String! {
        return "ti.network.manager"
    }
    
    override func startup() {
        super.startup()
        
        TNMLogger.info("Ti.Network.Manager initializing", details: [
            "version": "1.0.0",
            "moduleId": moduleId() ?? "unknown"
        ])
        
        // Initialize managers
        requestManager = TNMRequestManager()
        streamManager = TNMStreamManager()
        certificatePinningManager = TNMCertificatePinningManager()
        cacheManager = TNMCacheManager()
        interceptorManager = TNMInterceptorManager()
        websocketManager = TNMWebSocketManager()
        backgroundTransferManager = TNMBackgroundTransferManager()
        multipartUploadManager = TNMMultipartUploadManager()
        
        TNMLogger.success("Ti.Network.Manager initialized successfully", details: [
            "features": "Streaming, CertPinning, Interceptors, Retry, Cache, BackgroundTransfer, WebSocket, HTTP/2"
        ])
    }
    
    // MARK: - Public API
    
    /**
     * Create a standard HTTP request
     *
     * @param arguments Array containing request configuration dictionary
     * @return TiHTTPRequestProxy
     */
    @objc(createRequest:)
    func createRequest(arguments: [Any]?) -> TNMRequestProxy {
        guard let arguments = arguments,
              let params = arguments.first as? [String: Any] else {
            TNMLogger.error("createRequest called without parameters")
            fatalError("[Ti.Network.Manager] createRequest requires parameters dictionary")
        }
        
        TNMLogger.debug("Creating standard HTTP request", details: [
            "url": params["url"] as? String ?? "unknown",
            "method": params["method"] as? String ?? "GET"
        ])
        
        let proxy = TNMRequestProxy(
            params: params,
            requestManager: requestManager,
            interceptorManager: interceptorManager,
            cacheManager: cacheManager,
            certificatePinningManager: certificatePinningManager
        )
        
        return proxy
    }
    
    /**
     * Create a streaming request (for SSE, AI APIs, etc)
     *
     * @param arguments Array containing streaming configuration dictionary
     * @return TiHTTPStreamProxy
     */
    @objc(createStreamRequest:)
    func createStreamRequest(arguments: [Any]?) -> TiHTTPStreamProxy {
        guard let arguments = arguments,
              let params = arguments.first as? [String: Any] else {
            TNMLogger.error("createStreamRequest called without parameters")
            fatalError("[Ti.Network.Manager] createStreamRequest requires parameters dictionary")
        }
        
        TNMLogger.debug("Creating streaming HTTP request", details: [
            "url": params["url"] as? String ?? "unknown",
            "method": params["method"] as? String ?? "GET"
        ])
        
        let proxy = TiHTTPStreamProxy(
            params: params,
            streamManager: streamManager,
            interceptorManager: interceptorManager,
            certificatePinningManager: certificatePinningManager
        )
        
        return proxy
    }
    
    /**
     * Create a WebSocket connection
     *
     * @param arguments Array containing WebSocket configuration dictionary
     * @return TiHTTPWebSocketProxy
     */
    @objc(createWebSocket:)
    func createWebSocket(arguments: [Any]?) -> TNMWebSocketProxy {
        guard let arguments = arguments,
              let params = arguments.first as? [String: Any] else {
            TNMLogger.error("createWebSocket called without parameters")
            fatalError("[Ti.Network.Manager] createWebSocket requires parameters dictionary")
        }
        
        TNMLogger.debug("Creating WebSocket connection", details: [
            "url": params["url"] as? String ?? "unknown"
        ])
        
        let proxy = TNMWebSocketProxy(
            params: params,
            websocketManager: websocketManager
        )
        
        return proxy
    }
    
    /**
     * Create a background transfer (download or upload)
     *
     * @param arguments Array containing background transfer configuration dictionary
     * @return TNMBackgroundTransferProxy
     */
    @objc(createBackgroundTransfer:)
    func createBackgroundTransfer(arguments: [Any]?) -> TNMBackgroundTransferProxy {
        guard let arguments = arguments,
              let params = arguments.first as? [String: Any] else {
            TNMLogger.error("createBackgroundTransfer called without parameters")
            fatalError("[Ti.Network.Manager] createBackgroundTransfer requires parameters dictionary")
        }
        
        let transferType = params["type"] as? String ?? "download"
        
        TNMLogger.debug("Creating background transfer", details: [
            "type": transferType,
            "url": params["url"] as? String ?? "unknown"
        ])
        
        let proxy = TNMBackgroundTransferProxy(
            params: params,
            transferManager: backgroundTransferManager,
            certificatePinningManager: certificatePinningManager
        )
        
        return proxy
    }
    
    /**
     * Create a multipart upload
     *
     * @param arguments Array containing multipart upload configuration dictionary
     * @return TNMMultipartUploadProxy
     */
    @objc(createMultipartUpload:)
    func createMultipartUpload(arguments: [Any]?) -> TNMMultipartUploadProxy {
        guard let arguments = arguments,
              let params = arguments.first as? [String: Any] else {
            TNMLogger.error("createMultipartUpload called without parameters")
            fatalError("[Ti.Network.Manager] createMultipartUpload requires parameters dictionary")
        }
        
        TNMLogger.debug("Creating multipart upload", details: [
            "url": params["url"] as? String ?? "unknown"
        ])
        
        let proxy = TNMMultipartUploadProxy(
            params: params,
            multipartManager: multipartUploadManager,
            certificatePinningManager: certificatePinningManager
        )
        
        return proxy
    }
    
    /**
     * Add global request interceptor
     *
     * @param arguments Array containing callback function
     */
    @objc(addRequestInterceptor:)
    func addRequestInterceptor(arguments: [Any]?) {
        guard let arguments = arguments,
              let callback = arguments.first as? KrollCallback else {
            TNMLogger.error("addRequestInterceptor called without callback function")
            return
        }
        
        interceptorManager.addRequestInterceptor(callback)
        TNMLogger.Interceptor.requestInterceptorAdded(count: interceptorManager.requestInterceptorCount)
    }
    
    /**
     * Add global response interceptor
     *
     * @param arguments Array containing callback function
     */
    @objc(addResponseInterceptor:)
    func addResponseInterceptor(arguments: [Any]?) {
        guard let arguments = arguments,
              let callback = arguments.first as? KrollCallback else {
            TNMLogger.error("addResponseInterceptor called without callback function")
            return
        }
        
        interceptorManager.addResponseInterceptor(callback)
        TNMLogger.Interceptor.responseInterceptorAdded(count: interceptorManager.responseInterceptorCount)
    }
    
    /**
     * Configure certificate pinning for domain
     *
     * @param arguments Array containing [domain: String, hashes: [String]]
     */
    @objc(setCertificatePinning:)
    func setCertificatePinning(arguments: [Any]?) {
        guard let arguments = arguments,
              arguments.count >= 2,
              let domain = arguments[0] as? String,
              let hashes = arguments[1] as? [String] else {
            TNMLogger.error("setCertificatePinning called with invalid parameters", details: [
                "expected": "domain (String), hashes (Array of String)"
            ])
            return
        }
        
        certificatePinningManager.setPinning(for: domain, hashes: hashes)
        TNMLogger.CertificatePinning.configured(domain: domain, hashCount: hashes.count)
    }
    
    /**
     * Clear cache
     *
     * @param arguments Array optionally containing domain string to clear specific cache
     */
    @objc(clearCache:)
    func clearCache(arguments: [Any]?) {
        if let arguments = arguments,
           let domain = arguments.first as? String {
            cacheManager.clearCache(for: domain)
            TNMLogger.Cache.cleared(domain: domain)
        } else {
            cacheManager.clearAllCache()
            TNMLogger.Cache.cleared(domain: nil)
        }
    }
    
    // MARK: - Constants
    
    @objc public let PRIORITY_LOW = "low"
    @objc public let PRIORITY_NORMAL = "normal"
    @objc public let PRIORITY_HIGH = "high"
    
    @objc public let CACHE_POLICY_NETWORK_ONLY = "network-only"
    @objc public let CACHE_POLICY_CACHE_FIRST = "cache-first"
    @objc public let CACHE_POLICY_NETWORK_FIRST = "network-first"
    
    @objc public let RETRY_BACKOFF_LINEAR = "linear"
    @objc public let RETRY_BACKOFF_EXPONENTIAL = "exponential"
}
