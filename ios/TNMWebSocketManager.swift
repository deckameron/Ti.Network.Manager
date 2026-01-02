//
//  TNMWebSocketManager.swift
//  TiNetworkManager
//
//  Created by Douglas Alves on 02/01/26.
//


/**
 * Ti.Network.Manager - WebSocket Manager
 * Handles WebSocket connections
 * Feature #10: WebSocket support for real-time bidirectional communication
 */

import Foundation

class TNMWebSocketManager: NSObject {
    
    // MARK: - Properties
    
    private var activeConnections: [String: URLSessionWebSocketTask] = [:]
    private var websocketDelegates: [String: WebSocketDelegate] = [:]
    private var sessions: [String: URLSession] = [:]
    
    // MARK: - Public Methods
    
    /**
     * Connect to WebSocket
     */
    func connect(
        connectionId: String,
        url: URL,
        headers: [String: String]?,
        onMessage: @escaping (String) -> Void,
        onBinary: @escaping (Data) -> Void,
        onOpen: @escaping () -> Void,
        onClose: @escaping (Int, String) -> Void,
        onError: @escaping (Error) -> Void
    ) {
        TNMLogger.WebSocket.connecting(url: url.absoluteString)
        
        // Create delegate
        let delegate = WebSocketDelegate(
            connectionId: connectionId,
            onMessage: onMessage,
            onBinary: onBinary,
            onOpen: onOpen,
            onClose: onClose,
            onError: onError
        )
        
        websocketDelegates[connectionId] = delegate
        
        // Create request
        var request = URLRequest(url: url)
        
        // Add headers
        if let headers = headers {
            for (key, value) in headers {
                request.setValue(value, forHTTPHeaderField: key)
            }
            
            TNMLogger.debug("WebSocket headers configured", feature: "WebSocket", details: [
                "connectionId": connectionId,
                "headerCount": headers.count
            ])
        }
        
        // Create session
        let session = URLSession(
            configuration: .default,
            delegate: delegate,
            delegateQueue: nil
        )
        
        sessions[connectionId] = session
        
        // Create WebSocket task
        let task = session.webSocketTask(with: request)
        
        activeConnections[connectionId] = task
        
        TNMLogger.debug("WebSocket task created", feature: "WebSocket", details: [
            "connectionId": connectionId,
            "taskIdentifier": task.taskIdentifier
        ])
        
        // Start receiving messages
        receiveMessage(connectionId: connectionId, task: task, delegate: delegate)
        
        // Connect
        task.resume()
        
        // Notify connection opened
        TNMLogger.WebSocket.connected(url: url.absoluteString)
        onOpen()
    }
    
    /**
     * Send text message
     */
    func sendMessage(connectionId: String, message: String, completion: @escaping (Error?) -> Void) {
        guard let task = activeConnections[connectionId] else {
            let error = NSError(
                domain: "TNMWebSocketManager",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "WebSocket not connected"]
            )
            TNMLogger.error("Cannot send message - not connected", feature: "WebSocket", error: error, details: [
                "connectionId": connectionId
            ])
            completion(error)
            return
        }
        
        let messageData = URLSessionWebSocketTask.Message.string(message)
        
        task.send(messageData) { [weak self] error in
            if let error = error {
                TNMLogger.WebSocket.error(error: error)
            } else {
                let size = message.utf8.count
                self?.logMessageSent(connectionId: connectionId, type: "text", size: size)
            }
            completion(error)
        }
    }
    
    /**
     * Send binary data
     */
    func sendBinary(connectionId: String, data: Data, completion: @escaping (Error?) -> Void) {
        guard let task = activeConnections[connectionId] else {
            let error = NSError(
                domain: "TNMWebSocketManager",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "WebSocket not connected"]
            )
            TNMLogger.error("Cannot send binary - not connected", feature: "WebSocket", error: error, details: [
                "connectionId": connectionId
            ])
            completion(error)
            return
        }
        
        let message = URLSessionWebSocketTask.Message.data(data)
        
        task.send(message) { [weak self] error in
            if let error = error {
                TNMLogger.WebSocket.error(error: error)
            } else {
                self?.logMessageSent(connectionId: connectionId, type: "binary", size: data.count)
            }
            completion(error)
        }
    }
    
    /**
     * Close WebSocket connection
     */
    func close(connectionId: String, code: URLSessionWebSocketTask.CloseCode = .normalClosure, reason: String? = nil) {
        guard let task = activeConnections[connectionId] else {
            TNMLogger.debug("WebSocket already closed or not found", feature: "WebSocket", details: [
                "connectionId": connectionId
            ])
            return
        }
        
        let reasonData = reason?.data(using: .utf8)
        task.cancel(with: code, reason: reasonData)
        
        TNMLogger.WebSocket.closed(code: code.rawValue, reason: reason ?? "No reason")
        
        activeConnections.removeValue(forKey: connectionId)
        websocketDelegates.removeValue(forKey: connectionId)
        sessions[connectionId]?.invalidateAndCancel()
        sessions.removeValue(forKey: connectionId)
    }
    
    /**
     * Ping server
     */
    func ping(connectionId: String, completion: @escaping (Error?) -> Void) {
        guard let task = activeConnections[connectionId] else {
            let error = NSError(
                domain: "TNMWebSocketManager",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "WebSocket not connected"]
            )
            completion(error)
            return
        }
        
        TNMLogger.debug("Sending ping", feature: "WebSocket", details: [
            "connectionId": connectionId
        ])
        
        task.sendPing { error in
            if let error = error {
                TNMLogger.WebSocket.error(error: error)
            } else {
                TNMLogger.debug("Pong received", feature: "WebSocket", details: [
                    "connectionId": connectionId
                ])
            }
            completion(error)
        }
    }
    
    // MARK: - Private Methods
    
    private func receiveMessage(connectionId: String, task: URLSessionWebSocketTask, delegate: WebSocketDelegate) {
        task.receive { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    let size = text.utf8.count
                    self.logMessageReceived(connectionId: connectionId, type: "text", size: size)
                    delegate.onMessage(text)
                    
                case .data(let data):
                    self.logMessageReceived(connectionId: connectionId, type: "binary", size: data.count)
                    delegate.onBinary(data)
                    
                @unknown default:
                    TNMLogger.debug("Unknown message type received", feature: "WebSocket", details: [
                        "connectionId": connectionId
                    ])
                }
                
                // Continue receiving
                self.receiveMessage(connectionId: connectionId, task: task, delegate: delegate)
                
            case .failure(let error):
                TNMLogger.WebSocket.error(error: error)
                delegate.onError(error)
                
                self.activeConnections.removeValue(forKey: connectionId)
                self.websocketDelegates.removeValue(forKey: connectionId)
                self.sessions[connectionId]?.invalidateAndCancel()
                self.sessions.removeValue(forKey: connectionId)
            }
        }
    }
    
    private func logMessageSent(connectionId: String, type: String, size: Int) {
        TNMLogger.WebSocket.messageSent(type: type, size: size)
        
        TNMLogger.debug("Message sent", feature: "WebSocket", details: [
            "connectionId": connectionId,
            "type": type,
            "size": "\(size) bytes"
        ])
    }
    
    private func logMessageReceived(connectionId: String, type: String, size: Int) {
        TNMLogger.WebSocket.messageReceived(type: type, size: size)
        
        TNMLogger.debug("Message received", feature: "WebSocket", details: [
            "connectionId": connectionId,
            "type": type,
            "size": "\(size) bytes"
        ])
    }
}

// MARK: - WebSocket Delegate

class WebSocketDelegate: NSObject, URLSessionWebSocketDelegate {
    
    let connectionId: String
    let onMessage: (String) -> Void
    let onBinary: (Data) -> Void
    let onOpen: () -> Void
    let onClose: (Int, String) -> Void
    let onError: (Error) -> Void
    
    init(
        connectionId: String,
        onMessage: @escaping (String) -> Void,
        onBinary: @escaping (Data) -> Void,
        onOpen: @escaping () -> Void,
        onClose: @escaping (Int, String) -> Void,
        onError: @escaping (Error) -> Void
    ) {
        self.connectionId = connectionId
        self.onMessage = onMessage
        self.onBinary = onBinary
        self.onOpen = onOpen
        self.onClose = onClose
        self.onError = onError
    }
    
    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        let reasonString = reason.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        
        TNMLogger.WebSocket.closed(code: closeCode.rawValue, reason: reasonString)
        TNMLogger.debug("WebSocket closed by server", feature: "WebSocket", details: [
            "connectionId": connectionId,
            "closeCode": closeCode.rawValue
        ])
        
        onClose(closeCode.rawValue, reasonString)
    }
    
    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol protocol: String?
    ) {
        TNMLogger.debug("WebSocket opened with protocol", feature: "WebSocket", details: [
            "connectionId": connectionId,
            "protocol": `protocol` ?? "none"
        ])
    }
}
