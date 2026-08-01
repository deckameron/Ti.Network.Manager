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
    private var timeout: TimeInterval
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
        
        // Timeout: JS sends milliseconds (Ti.Network.createHTTPClient convention),
        // internally we work in seconds (TimeInterval). Defaults to 60s when absent.
        if let timeoutMs = params["timeout"] as? Double {
            self.timeout = timeoutMs / 1000.0
        } else if let timeoutMs = params["timeout"] as? Int {
            self.timeout = TimeInterval(timeoutMs) / 1000.0
        } else {
            self.timeout = 60.0
        }
        
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
            "timeout": String(format: "%.1f seconds", timeout),
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
            // ✅ Mesma razão do fix acima: nunca disparar fireEvent(...) de forma
            // síncrona a partir de send(), já que send() costuma ser chamado a
            // partir de um handler de toque/click ainda em andamento.
            DispatchQueue.main.async { [weak self] in
                self?.fireEvent("error", with: ["error": "Invalid URL"])
            }
            return
        }
        
        isActive = true
        startTime = Date()
        
        // Generate cache key
        let cacheKey = cacheManager.generateKey(url: self.url, method: method)
        
        // Check cache policy
        if let policy = cachePolicy, policy == "cache-first" {
            if let cachedEntry = cacheManager.getCachedResponse(for: cacheKey, maxAge: cacheTTL) {
                // ✅ Despachar para o próximo ciclo do run loop, igual ao caminho de
                // rede (TNMRequestManager sempre usa DispatchQueue.main.async para
                // onComplete/onError). Antes, um cache hit chamava handleCachedResponse()
                // direto, de forma síncrona — e como send() normalmente é chamado a
                // partir de um handler de toque/click, o fireEvent("complete", ...)
                // (e tudo que ele desencadeia no JS, incluindo abrir uma window nova
                // inteira) rodava REENTRANTE, ainda dentro da pilha de chamada do
                // próprio touchesEnded:withEvent: do UIKit, antes dele terminar de
                // desempilhar. Essa reentrância é a causa raiz do crash
                // "pointer authentication failure" / KrollBridge com classe de
                // objeto variável: abrir uma árvore de proxies nova no meio do
                // processamento do toque corrompe estado do UIKit/KrollContext.
                DispatchQueue.main.async { [weak self] in
                    self?.handleCachedResponse(cachedEntry)
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
        //
        // IMPORTANT: capture self strongly (not weakly) in these callbacks.
        // Titanium's JS runtime can GC the proxy before an async response or
        // timeout arrives — especially in Classic apps where proxies have no
        // UI attachment to keep them alive. A weak capture would let the proxy
        // (and its requestManager) be deallocated, causing the URLSession
        // completion handler's `guard let self = self else { return }` to exit
        // silently, with no complete/error event ever firing.
        //
        // The resulting temporary retain cycle
        //   proxy → requestManager → activeTasks → task closure → proxy
        // is intentional and safe: it breaks as soon as the task completes and
        // is removed from activeTasks.
        let retainedSelf = self
        
        requestManager.executeRequest(
            requestId: requestId,
            url: url,
            method: method,
            headers: modifiedHeaders,
            body: bodyData,
            priority: urlPriority,
            timeout: timeout,
            retryConfig: retryConfig,
            certificateValidator: certificateValidator,
            onProgress: { received, total in
                retainedSelf.handleProgress(received: received, total: total)
            },
            onComplete: { statusCode, headers, data in
                retainedSelf.handleComplete(
                    statusCode: statusCode,
                    headers: headers,
                    data: data,
                    cacheKey: cacheKey
                )
            },
            onError: { error, willRetry in
                retainedSelf.handleError(error, willRetry: willRetry, cacheKey: cacheKey)
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
        
        let bodyString = entry.bodyString
        
        TNMLogger.debug("Returning cached response", feature: "Request", details: [
            "requestId": requestId,
            "statusCode": entry.statusCode
        ])
        
        fireEvent("complete", with: [
            "statusCode": entry.statusCode,
            "headers": entry.headers,
            "body": bodyString,
            "success": true,
            "cached": true,
            "duration": 0
        ])
    }
    
    private func handleError(_ error: Error, willRetry: Bool, cacheKey: String) {
        // Intermediate retry attempt — just notify, nothing else to do yet.
        if willRetry {
            fireEvent("error", with: [
                "error": error.localizedDescription,
                "code": (error as NSError).code,
                "willRetry": willRetry
            ])
            return
        }

        // Guard against a delayed/cancelled URLSessionTask completion arriving
        // after this proxy already finished via handleComplete/handleCachedResponse
        // (mirrors the guard in handleComplete). Without this, a stale error
        // callback could fire a spurious extra 'error' — or, for network-first
        // policy, a spurious extra 'complete' via the cache fallback below —
        // after the request had already resolved successfully.
        guard isActive else { return }

        isActive = false
        
        // network-first fallback: the network attempt (plus all configured retries)
        // has definitively failed. If a cached entry exists for this key, serve it
        // instead of failing outright — regardless of its age/TTL, since at this
        // point any data is better than none. The 'stale' flag lets the JS side
        // distinguish this from a normal cache-first hit if it cares to.
        if cachePolicy == "network-first",
           let cachedEntry = cacheManager.getCachedResponse(for: cacheKey, maxAge: nil) {
            
            TNMLogger.warning("Network request failed, falling back to cache", feature: "Request", details: [
                "requestId": requestId,
                "cacheKey": cacheKey
            ])
            
            fireEvent("complete", with: [
                "statusCode": cachedEntry.statusCode,
                "headers": cachedEntry.headers,
                "body": cachedEntry.bodyString,
                "success": true,
                "cached": true,
                "stale": true,
                "duration": 0
            ])
            return
        }
        
        fireEvent("error", with: [
            "error": error.localizedDescription,
            "code": (error as NSError).code,
            "willRetry": willRetry
        ])
    }
}
