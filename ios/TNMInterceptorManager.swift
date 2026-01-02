//
//  TNMInterceptorManager.swift
//  TiNetworkManager
//
//  Created by Douglas Alves on 02/01/26.
//


/**
 * Ti.Network.Manager - Interceptor Manager
 * Handles request/response interceptors
 * Allows global middleware for auth, logging, error handling, etc.
 */

import TitaniumKit
import Foundation

class TNMInterceptorManager {
    
    // MARK: - Properties
    
    private var requestInterceptors: [KrollCallback] = []
    private var responseInterceptors: [KrollCallback] = []
    
    var requestInterceptorCount: Int {
        return requestInterceptors.count
    }
    
    var responseInterceptorCount: Int {
        return responseInterceptors.count
    }
    
    // MARK: - Public Methods
    
    /**
     * Add request interceptor
     */
    func addRequestInterceptor(_ callback: KrollCallback) {
        requestInterceptors.append(callback)
    }
    
    /**
     * Add response interceptor
     */
    func addResponseInterceptor(_ callback: KrollCallback) {
        responseInterceptors.append(callback)
    }
    
    /**
     * Remove all request interceptors
     */
    func clearRequestInterceptors() {
        requestInterceptors.removeAll()
        
        TNMLogger.info("All request interceptors cleared", feature: "Interceptor")
    }
    
    /**
     * Remove all response interceptors
     */
    func clearResponseInterceptors() {
        responseInterceptors.removeAll()
        
        TNMLogger.info("All response interceptors cleared", feature: "Interceptor")
    }
    
    /**
     * Intercept outgoing request
     */
    func interceptRequest(
        url: String,
        method: String,
        headers: inout [String: String],
        body: inout String?
    ) {
        guard !requestInterceptors.isEmpty else { return }
        
        TNMLogger.Interceptor.requestIntercepted(url: url, method: method)
        
        for interceptor in requestInterceptors {
            // Create config object
            var config: [String: Any] = [
                "url": url,
                "method": method,
                "headers": headers
            ]
            
            if let body = body {
                config["body"] = body
            }
            
            // Call interceptor
            if let result = interceptor.call([config], thisObject: nil) as? [String: Any] {
                // Update headers if modified
                if let modifiedHeaders = result["headers"] as? [String: String] {
                    headers = modifiedHeaders
                }
                
                // Update body if modified
                if let modifiedBody = result["body"] as? String {
                    body = modifiedBody
                } else if result["body"] is NSNull {
                    body = nil
                }
            }
        }
    }
    
    /**
     * Intercept incoming response
     */
    func interceptResponse(
        statusCode: inout Int,
        headers: inout [String: String],
        body: String?
    ) {
        guard !responseInterceptors.isEmpty else { return }
        
        TNMLogger.Interceptor.responseIntercepted(statusCode: statusCode)
        
        for interceptor in responseInterceptors {
            // Create response object
            var response: [String: Any] = [
                "status": statusCode,
                "statusCode": statusCode,
                "headers": headers
            ]
            
            if let body = body {
                response["body"] = body
            }
            
            // Call interceptor
            if let result = interceptor.call([response], thisObject: nil) as? [String: Any] {
                // Update status code if modified
                if let modifiedStatus = result["status"] as? Int {
                    statusCode = modifiedStatus
                } else if let modifiedStatus = result["statusCode"] as? Int {
                    statusCode = modifiedStatus
                }
                
                // Update headers if modified
                if let modifiedHeaders = result["headers"] as? [String: String] {
                    headers = modifiedHeaders
                }
            }
        }
    }
}
