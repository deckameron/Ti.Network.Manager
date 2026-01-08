//
//  TNMLogger.swift
//  TiNetworkManager
//
//  Created by Douglas Alves on 02/01/26.
//


/**
 * Ti.Network.Manager - Logging System
 * Structured, clear, and informative logging for all module features
 */

import Foundation

class TNMLogger {
    
    // MARK: - Log Levels
    
    enum Level: String {
        case debug = "DEBUG"
        case info = "INFO"
        case warning = "WARNING"
        case error = "ERROR"
        case success = "SUCCESS"
    }
    
    // MARK: - ANSI Color Codes
    
    private enum Color: String {
        case reset = "\u{001B}[0m"
        case red = "\u{001B}[31m"
        case green = "\u{001B}[32m"
        case yellow = "\u{001B}[33m"
        case blue = "\u{001B}[34m"
        case magenta = "\u{001B}[35m"
        case cyan = "\u{001B}[36m"
        case white = "\u{001B}[37m"
        case gray = "\u{001B}[90m"
        
        case brightRed = "\u{001B}[91m"
        case brightGreen = "\u{001B}[92m"
        case brightYellow = "\u{001B}[93m"
        case brightBlue = "\u{001B}[94m"
        case brightMagenta = "\u{001B}[95m"
        case brightCyan = "\u{001B}[96m"
    }
    
    // MARK: - Configuration
    
    static var isEnabled = true
    static var minimumLevel: Level = .debug
    
    // MARK: - Logging Methods
    
    static func debug(_ message: String, feature: String? = nil, details: [String: Any]? = nil) {
        log(level: .debug, message: message, feature: feature, details: details)
    }
    
    static func info(_ message: String, feature: String? = nil, details: [String: Any]? = nil) {
        log(level: .info, message: message, feature: feature, details: details)
    }
    
    static func warning(_ message: String, feature: String? = nil, details: [String: Any]? = nil) {
        log(level: .warning, message: message, feature: feature, details: details)
    }
    
    static func error(_ message: String, feature: String? = nil, error: Error? = nil, details: [String: Any]? = nil) {
        var allDetails = details ?? [:]
        if let error = error {
            allDetails["error"] = error.localizedDescription
            allDetails["errorCode"] = (error as NSError).code
        }
        log(level: .error, message: message, feature: feature, details: allDetails)
    }
    
    static func success(_ message: String, feature: String? = nil, details: [String: Any]? = nil) {
        log(level: .success, message: message, feature: feature, details: details)
    }
    
    // MARK: - Core Logging
    
    private static func log(level: Level, message: String, feature: String?, details: [String: Any]?) {
        guard isEnabled else { return }
        
        let timestamp = dateFormatter.string(from: Date())
        let featureTag = feature != nil ? "[\(feature!)]" : ""
        let levelColor = colorForLevel(level)
        let featureColor = Color.cyan.rawValue
        
        // Format: [TIMESTAMP] [LEVEL] [FEATURE] Message
        var logMessage = "\(Color.gray.rawValue)[\(timestamp)]\(Color.reset.rawValue) "
        logMessage += "\(levelColor)[\(level.rawValue)]\(Color.reset.rawValue) "
        
        if !featureTag.isEmpty {
            logMessage += "\(featureColor)\(featureTag)\(Color.reset.rawValue) "
        }
        
        logMessage += message
        
        // Add details if present
        if let details = details, !details.isEmpty {
            logMessage += "\n"
            for (key, value) in details.sorted(by: { $0.key < $1.key }) {
                logMessage += "  \(Color.gray.rawValue)|\(Color.reset.rawValue) "
                logMessage += "\(Color.brightBlue.rawValue)\(key):\(Color.reset.rawValue) \(value)"
                logMessage += "\n"
            }
        }
        
        NSLog("%@", logMessage)
    }
    
    // MARK: - Helpers
    
    private static func colorForLevel(_ level: Level) -> String {
        switch level {
        case .debug:
            return Color.gray.rawValue
        case .info:
            return Color.blue.rawValue
        case .warning:
            return Color.yellow.rawValue
        case .error:
            return Color.red.rawValue
        case .success:
            return Color.green.rawValue
        }
    }
    
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()
    
    // MARK: - Feature-Specific Loggers
    
    struct Streaming {
        static func started(requestId: String, url: String) {
            TNMLogger.info("Streaming request started", feature: "Streaming", details: [
                "requestId": requestId,
                "url": url
            ])
        }
        
        static func chunkReceived(requestId: String, size: Int, totalSize: Int) {
            TNMLogger.debug("Chunk received", feature: "Streaming", details: [
                "requestId": requestId,
                "chunkSize": "\(size) bytes",
                "totalReceived": "\(totalSize) bytes"
            ])
        }
        
        static func completed(requestId: String, statusCode: Int, totalBytes: Int) {
            TNMLogger.success("Streaming completed", feature: "Streaming", details: [
                "requestId": requestId,
                "statusCode": statusCode,
                "totalBytes": "\(totalBytes) bytes"
            ])
        }
        
        static func cancelled(requestId: String) {
            TNMLogger.warning("Streaming cancelled", feature: "Streaming", details: [
                "requestId": requestId
            ])
        }
        
        static func error(requestId: String, error: Error) {
            TNMLogger.error("Streaming failed", feature: "Streaming", error: error, details: [
                "requestId": requestId
            ])
        }
    }
    
    struct CertificatePinning {
        static func configured(domain: String, hashCount: Int) {
            TNMLogger.info("Certificate pinning configured", feature: "CertPinning", details: [
                "domain": domain,
                "hashCount": hashCount
            ])
        }
        
        static func validationStarted(domain: String) {
            TNMLogger.debug("Validating certificate", feature: "CertPinning", details: [
                "domain": domain
            ])
        }
        
        static func validationSuccess(domain: String) {
            TNMLogger.success("Certificate validated", feature: "CertPinning", details: [
                "domain": domain
            ])
        }
        
        static func validationFailed(domain: String, reason: String) {
            TNMLogger.error("Certificate validation failed", feature: "CertPinning", details: [
                "domain": domain,
                "reason": reason
            ])
        }
    }
    
    struct Interceptor {
        static func requestInterceptorAdded(count: Int) {
            TNMLogger.info("Request interceptor added", feature: "Interceptor", details: [
                "totalInterceptors": count
            ])
        }
        
        static func responseInterceptorAdded(count: Int) {
            TNMLogger.info("Response interceptor added", feature: "Interceptor", details: [
                "totalInterceptors": count
            ])
        }
        
        static func requestIntercepted(url: String, method: String) {
            TNMLogger.debug("Request intercepted", feature: "Interceptor", details: [
                "method": method,
                "url": url
            ])
        }
        
        static func responseIntercepted(statusCode: Int) {
            TNMLogger.debug("Response intercepted", feature: "Interceptor", details: [
                "statusCode": statusCode
            ])
        }
    }
    
    struct Cache {
        static func hit(key: String, age: TimeInterval) {
            TNMLogger.success("Cache hit", feature: "Cache", details: [
                "key": key,
                "age": String(format: "%.1f seconds", age)
            ])
        }
        
        static func miss(key: String) {
            TNMLogger.debug("Cache miss", feature: "Cache", details: [
                "key": key
            ])
        }
        
        static func stored(key: String, size: Int) {
            TNMLogger.info("Response cached", feature: "Cache", details: [
                "key": key,
                "size": "\(size) bytes"
            ])
        }
        
        static func cleared(domain: String?) {
            if let domain = domain {
                TNMLogger.info("Cache cleared for domain", feature: "Cache", details: [
                    "domain": domain
                ])
            } else {
                TNMLogger.info("All cache cleared", feature: "Cache")
            }
        }
    }
    
    struct Retry {
        static func attempting(attempt: Int, maxAttempts: Int, delay: TimeInterval) {
            TNMLogger.warning("Retrying request", feature: "Retry", details: [
                "attempt": "\(attempt)/\(maxAttempts)",
                "delay": String(format: "%.1f seconds", delay)
            ])
        }
        
        static func exhausted(attempts: Int) {
            TNMLogger.error("Retry attempts exhausted", feature: "Retry", details: [
                "attempts": attempts
            ])
        }
    }
    
    struct WebSocket {
        static func connecting(url: String) {
            TNMLogger.info("WebSocket connecting", feature: "WebSocket", details: [
                "url": url
            ])
        }
        
        static func connected(url: String) {
            TNMLogger.success("WebSocket connected", feature: "WebSocket", details: [
                "url": url
            ])
        }
        
        static func messageSent(type: String, size: Int) {
            TNMLogger.debug("WebSocket message sent", feature: "WebSocket", details: [
                "type": type,
                "size": "\(size) bytes"
            ])
        }
        
        static func messageReceived(type: String, size: Int) {
            TNMLogger.debug("WebSocket message received", feature: "WebSocket", details: [
                "type": type,
                "size": "\(size) bytes"
            ])
        }
        
        static func closed(code: Int, reason: String) {
            TNMLogger.info("WebSocket closed", feature: "WebSocket", details: [
                "code": code,
                "reason": reason.isEmpty ? "No reason provided" : reason
            ])
        }
        
        static func error(error: Error) {
            TNMLogger.error("WebSocket error", feature: "WebSocket", error: error)
        }
    }
    
    struct Request {
        static func created(requestId: String, url: String, method: String) {
            TNMLogger.info("Request created", feature: "Request", details: [
                "requestId": requestId,
                "method": method,
                "url": url
            ])
        }
        
        static func started(requestId: String, priority: String) {
            TNMLogger.info("Request started", feature: "Request", details: [
                "requestId": requestId,
                "priority": priority
            ])
        }
        
        static func progress(requestId: String, received: Int64, total: Int64) {
            let percentage = total > 0 ? Double(received) / Double(total) * 100.0 : 0.0
            TNMLogger.debug("Request progress", feature: "Request", details: [
                "requestId": requestId,
                "progress": String(format: "%.1f%%", percentage),
                "received": "\(received) bytes",
                "total": "\(total) bytes"
            ])
        }
        
        static func completed(requestId: String, statusCode: Int, duration: TimeInterval) {
            TNMLogger.success("Request completed", feature: "Request", details: [
                "requestId": requestId,
                "statusCode": statusCode,
                "duration": String(format: "%.3f seconds", duration)
            ])
        }
        
        static func cancelled(requestId: String) {
            TNMLogger.warning("Request cancelled", feature: "Request", details: [
                "requestId": requestId
            ])
        }
        
        static func error(requestId: String, error: Error) {
            TNMLogger.error("Request failed", feature: "Request", error: error, details: [
                "requestId": requestId
            ])
        }
    }
    
    struct BackgroundTransfer {
        static func downloadStarted(transferId: String, url: String, destination: String) {
            TNMLogger.info("Background download started", feature: "BackgroundTransfer", details: [
                "transferId": transferId,
                "url": url,
                "destination": destination
            ])
        }
        
        static func uploadStarted(transferId: String, url: String, file: String) {
            TNMLogger.info("Background upload started", feature: "BackgroundTransfer", details: [
                "transferId": transferId,
                "url": url,
                "file": file
            ])
        }
        
        static func progress(transferId: String, type: String, sent: Int64, total: Int64) {
            let percentage = total > 0 ? Double(sent) / Double(total) * 100.0 : 0.0
            TNMLogger.debug("Background transfer progress", feature: "BackgroundTransfer", details: [
                "transferId": transferId,
                "type": type,
                "progress": String(format: "%.1f%%", percentage),
                "transferred": "\(sent) bytes",
                "total": "\(total) bytes"
            ])
        }
        
        static func completed(transferId: String, type: String, destination: String?) {
            var details: [String: Any] = [
                "transferId": transferId,
                "type": type
            ]
            if let dest = destination {
                details["destination"] = dest
            }
            TNMLogger.success("Background transfer completed", feature: "BackgroundTransfer", details: details)
        }
        
        static func paused(transferId: String) {
            TNMLogger.info("Background transfer paused", feature: "BackgroundTransfer", details: [
                "transferId": transferId
            ])
        }
        
        static func resumed(transferId: String) {
            TNMLogger.info("Background transfer resumed", feature: "BackgroundTransfer", details: [
                "transferId": transferId
            ])
        }
        
        static func cancelled(transferId: String) {
            TNMLogger.warning("Background transfer cancelled", feature: "BackgroundTransfer", details: [
                "transferId": transferId
            ])
        }
        
        static func error(transferId: String, error: Error) {
            TNMLogger.error("Background transfer failed", feature: "BackgroundTransfer", error: error, details: [
                "transferId": transferId
            ])
        }
    }
}
