//
//  TNMWebSocketProxy.swift
//  TiNetworkManager
//
//  Created by Douglas Alves on 02/01/26.
//


/**
 * Ti.Network.Manager - WebSocket Proxy
 * Proxy for WebSocket connections
 * Exposed to JavaScript for creating real-time bidirectional communication
 */

import TitaniumKit
import Foundation

@objc(TiHTTPWebSocketProxy)
class TNMWebSocketProxy: TiProxy {
    
    // MARK: - Properties
    
    private var websocketManager: TNMWebSocketManager
    private var connectionId: String
    private var url: String
    private var headers: [String: String]
    private var isConnected = false
    
    // MARK: - Initialization
    
    init(params: [String: Any], websocketManager: TNMWebSocketManager) {
        self.websocketManager = websocketManager
        self.connectionId = UUID().uuidString
        self.url = params["url"] as? String ?? ""
        self.headers = params["headers"] as? [String: String] ?? [:]
        
        super.init()
        
        TNMLogger.debug("WebSocket proxy created", feature: "WebSocket", details: [
            "connectionId": connectionId,
            "url": url,
            "headerCount": headers.count
        ])
    }
    
    // MARK: - Public API
    
    /**
     * Connect to WebSocket server
     * 
     * @param arguments Unused arguments array (required by Titanium)
     */
    @objc(connect:)
    func connect(arguments: [Any]?) {
        guard !isConnected else {
            TNMLogger.warning("WebSocket already connected", feature: "WebSocket", details: [
                "connectionId": connectionId
            ])
            return
        }
        
        guard let url = URL(string: self.url) else {
            TNMLogger.error("Invalid WebSocket URL", feature: "WebSocket", details: [
                "connectionId": connectionId,
                "url": self.url
            ])
            fireEvent("error", with: ["error": "Invalid WebSocket URL"])
            return
        }
        
        TNMLogger.WebSocket.connecting(url: self.url)
        
        websocketManager.connect(
            connectionId: connectionId,
            url: url,
            headers: headers,
            onMessage: { [weak self] message in
                self?.handleMessage(message)
            },
            onBinary: { [weak self] data in
                self?.handleBinary(data)
            },
            onOpen: { [weak self] in
                self?.handleOpen()
            },
            onClose: { [weak self] code, reason in
                self?.handleClose(code: code, reason: reason)
            },
            onError: { [weak self] error in
                self?.handleError(error)
            }
        )
    }
    
    /**
     * Send text message
     * 
     * @param arguments Array containing the message string
     */
    @objc(send:)
    func send(arguments: [Any]?) {
        guard let arguments = arguments,
              let message = arguments.first as? String else {
            TNMLogger.error("send() requires a string message", feature: "WebSocket", details: [
                "connectionId": connectionId
            ])
            return
        }
        
        guard isConnected else {
            TNMLogger.warning("Cannot send - WebSocket not connected", feature: "WebSocket", details: [
                "connectionId": connectionId
            ])
            fireEvent("error", with: ["error": "WebSocket not connected"])
            return
        }
        
        TNMLogger.debug("Sending message", feature: "WebSocket", details: [
            "connectionId": connectionId,
            "messageLength": message.count
        ])
        
        websocketManager.sendMessage(connectionId: connectionId, message: message) { [weak self] error in
            if let error = error {
                self?.fireEvent("error", with: ["error": error.localizedDescription])
            }
        }
    }
    
    /**
     * Send binary data
     * 
     * @param arguments Array containing base64 encoded string
     */
    @objc(sendBinary:)
    func sendBinary(arguments: [Any]?) {
        guard let arguments = arguments,
              let base64String = arguments.first as? String,
              let data = Data(base64Encoded: base64String) else {
            TNMLogger.error("sendBinary() requires base64 encoded string", feature: "WebSocket", details: [
                "connectionId": connectionId
            ])
            return
        }
        
        guard isConnected else {
            TNMLogger.warning("Cannot send binary - WebSocket not connected", feature: "WebSocket", details: [
                "connectionId": connectionId
            ])
            fireEvent("error", with: ["error": "WebSocket not connected"])
            return
        }
        
        TNMLogger.debug("Sending binary data", feature: "WebSocket", details: [
            "connectionId": connectionId,
            "dataSize": "\(data.count) bytes"
        ])
        
        websocketManager.sendBinary(connectionId: connectionId, data: data) { [weak self] error in
            if let error = error {
                self?.fireEvent("error", with: ["error": error.localizedDescription])
            }
        }
    }
    
    /**
     * Close connection
     * 
     * @param arguments Optional array containing [code: Int, reason: String]
     */
    @objc(close:)
    func close(arguments: [Any]?) {
        guard isConnected else {
            TNMLogger.debug("WebSocket already closed", feature: "WebSocket", details: [
                "connectionId": connectionId
            ])
            return
        }
        
        let code = arguments?.first as? Int ?? 1000
        let reason = (arguments?.count ?? 0) > 1 ? arguments?[1] as? String : nil
        
        let closeCode = URLSessionWebSocketTask.CloseCode(rawValue: code) ?? .normalClosure
        
        TNMLogger.debug("Closing WebSocket", feature: "WebSocket", details: [
            "connectionId": connectionId,
            "code": code,
            "reason": reason ?? "none"
        ])
        
        websocketManager.close(connectionId: connectionId, code: closeCode, reason: reason)
        isConnected = false
    }
    
    /**
     * Ping server
     * 
     * @param arguments Unused arguments array (required by Titanium)
     */
    @objc(ping:)
    func ping(arguments: [Any]?) {
        guard isConnected else {
            TNMLogger.warning("Cannot ping - WebSocket not connected", feature: "WebSocket", details: [
                "connectionId": connectionId
            ])
            return
        }
        
        TNMLogger.debug("Sending ping", feature: "WebSocket", details: [
            "connectionId": connectionId
        ])
        
        websocketManager.ping(connectionId: connectionId) { [weak self] error in
            if let error = error {
                self?.fireEvent("error", with: ["error": error.localizedDescription])
            } else {
                self?.fireEvent("pong", with: [:])
            }
        }
    }
    
    // MARK: - Event Handlers
    
    private func handleOpen() {
        isConnected = true
        
        TNMLogger.success("WebSocket opened", feature: "WebSocket", details: [
            "connectionId": connectionId
        ])
        
        fireEvent("open", with: [:])
    }
    
    private func handleMessage(_ message: String) {
        TNMLogger.debug("Message received", feature: "WebSocket", details: [
            "connectionId": connectionId,
            "messageLength": message.count
        ])
        
        fireEvent("message", with: [
            "data": message
        ])
    }
    
    private func handleBinary(_ data: Data) {
        TNMLogger.debug("Binary data received", feature: "WebSocket", details: [
            "connectionId": connectionId,
            "dataSize": "\(data.count) bytes"
        ])
        
        // Convert to base64 for JavaScript
        let base64 = data.base64EncodedString()
        
        fireEvent("binary", with: [
            "data": base64
        ])
    }
    
    private func handleClose(code: Int, reason: String) {
        isConnected = false
        
        TNMLogger.info("WebSocket closed", feature: "WebSocket", details: [
            "connectionId": connectionId,
            "code": code,
            "reason": reason.isEmpty ? "none" : reason
        ])
        
        fireEvent("close", with: [
            "code": code,
            "reason": reason
        ])
    }
    
    private func handleError(_ error: Error) {
        TNMLogger.error("WebSocket error", feature: "WebSocket", error: error, details: [
            "connectionId": connectionId
        ])
        
        fireEvent("error", with: [
            "error": error.localizedDescription,
            "code": (error as NSError).code
        ])
    }
}
