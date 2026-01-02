//
//  TNMBackgroundTransferProxy.swift
//  TiNetworkManager
//
//  Created by Douglas Alves on 02/01/26.
//


/**
 * Ti.Network.Manager - Background Transfer Proxy
 * Proxy for background download/upload operations
 * Exposed to JavaScript for creating background transfers
 */

import TitaniumKit
import Foundation

@objc(TNMBackgroundTransferProxy)
class TNMBackgroundTransferProxy: TiProxy {
    
    // MARK: - Properties
    
    private var transferManager: TNMBackgroundTransferManager
    private var certificatePinningManager: TNMCertificatePinningManager
    
    private var transferId: String
    private var url: String
    private var transferType: String // "download" or "upload"
    private var destination: String?
    private var fileURL: String?
    private var headers: [String: String]
    
    private var isActive = false
    private var resumeData: Data?
    
    // MARK: - Initialization
    
    init(
        params: [String: Any],
        transferManager: TNMBackgroundTransferManager,
        certificatePinningManager: TNMCertificatePinningManager
    ) {
        self.transferManager = transferManager
        self.certificatePinningManager = certificatePinningManager
        
        // Generate unique transfer ID
        self.transferId = UUID().uuidString
        
        // Extract parameters with proper unwrapping
        self.url = params["url"] as? String ?? ""
        self.transferType = params["type"] as? String ?? "download"
        self.destination = params["destination"] as? String
        self.fileURL = params["file"] as? String
        self.headers = params["headers"] as? [String: String] ?? [:]
        
        super.init()
        
        TNMLogger.debug("Background transfer proxy created", feature: "BackgroundTransfer", details: [
            "transferId": transferId,
            "type": transferType,
            "url": url
        ])
    }
    
    // MARK: - Public API
    
    /**
     * Start the background transfer
     * 
     * @param arguments Unused arguments array (required by Titanium)
     */
    @objc(start:)
    func start(arguments: [Any]?) {
        guard !isActive else {
            TNMLogger.warning("Background transfer already started", feature: "BackgroundTransfer", details: [
                "transferId": transferId
            ])
            return
        }
        
        guard let url = URL(string: self.url) else {
            TNMLogger.error("Invalid URL for background transfer", feature: "BackgroundTransfer", details: [
                "transferId": transferId,
                "url": self.url
            ])
            fireEvent("error", with: ["error": "Invalid URL"])
            return
        }
        
        isActive = true
        
        // Get certificate validator if needed
        let certificateValidator = certificatePinningManager.getValidator(for: url.host ?? "")
        
        if transferType == "download" {
            startDownload(url: url, certificateValidator: certificateValidator)
        } else if transferType == "upload" {
            startUpload(url: url, certificateValidator: certificateValidator)
        } else {
            TNMLogger.error("Invalid transfer type", feature: "BackgroundTransfer", details: [
                "transferId": transferId,
                "type": transferType
            ])
            fireEvent("error", with: ["error": "Invalid transfer type. Use 'download' or 'upload'"])
            isActive = false
        }
    }
    
    /**
     * Cancel the background transfer
     * 
     * @param arguments Unused arguments array (required by Titanium)
     */
    @objc(cancel:)
    func cancel(arguments: [Any]?) {
        guard isActive else { return }
        
        TNMLogger.BackgroundTransfer.cancelled(transferId: transferId)
        
        if transferType == "download" {
            transferManager.cancelDownload(transferId: transferId)
        } else {
            transferManager.cancelUpload(transferId: transferId)
        }
        
        isActive = false
        fireEvent("cancelled", with: [:])
    }
    
    /**
     * Pause the background download
     * 
     * @param arguments Unused arguments array (required by Titanium)
     */
    @objc(pause:)
    func pause(arguments: [Any]?) {
        guard isActive, transferType == "download" else {
            TNMLogger.warning("Cannot pause - transfer not active or not a download", feature: "BackgroundTransfer", details: [
                "transferId": transferId,
                "isActive": isActive,
                "type": transferType
            ])
            return
        }
        
        transferManager.pauseDownload(transferId: transferId) { [weak self] data in
            guard let self = self else { return }
            
            self.resumeData = data
            self.isActive = false
            
            TNMLogger.BackgroundTransfer.paused(transferId: self.transferId)
            self.fireEvent("paused", with: [:])
        }
    }
    
    /**
     * Resume the background download
     * 
     * @param arguments Unused arguments array (required by Titanium)
     */
    @objc(resume:)
    func resume(arguments: [Any]?) {
        guard !isActive, transferType == "download", let data = resumeData else {
            TNMLogger.warning("Cannot resume - no resume data available", feature: "BackgroundTransfer", details: [
                "transferId": transferId,
                "hasResumeData": resumeData != nil
            ])
            return
        }
        
        isActive = true
        transferManager.resumeDownload(transferId: transferId, resumeData: data)
        
        TNMLogger.BackgroundTransfer.resumed(transferId: transferId)
        fireEvent("resumed", with: [:])
    }
    
    // MARK: - Private Methods
    
    private func startDownload(url: URL, certificateValidator: CertificateValidator?) {
        guard let destination = self.destination else {
            TNMLogger.error("Download requires destination path", feature: "BackgroundTransfer", details: [
                "transferId": transferId
            ])
            fireEvent("error", with: ["error": "Destination path required for downloads"])
            isActive = false
            return
        }
        
        TNMLogger.BackgroundTransfer.downloadStarted(
            transferId: transferId,
            url: url.absoluteString,
            destination: destination
        )
        
        transferManager.startDownload(
            transferId: transferId,
            url: url,
            destination: destination,
            headers: headers,
            certificateValidator: certificateValidator,
            onProgress: { [weak self] sent, total in
                self?.handleProgress(sent: sent, total: total)
            },
            onComplete: { [weak self] path in
                self?.handleComplete(path: path)
            },
            onError: { [weak self] error in
                self?.handleError(error)
            }
        )
    }
    
    private func startUpload(url: URL, certificateValidator: CertificateValidator?) {
        guard let fileURLString = self.fileURL,
              let fileURL = URL(string: fileURLString) else {
            TNMLogger.error("Upload requires file URL", feature: "BackgroundTransfer", details: [
                "transferId": transferId
            ])
            fireEvent("error", with: ["error": "File URL required for uploads"])
            isActive = false
            return
        }
        
        TNMLogger.BackgroundTransfer.uploadStarted(
            transferId: transferId,
            url: url.absoluteString,
            file: fileURL.path
        )
        
        transferManager.startUpload(
            transferId: transferId,
            url: url,
            fileURL: fileURL,
            headers: headers,
            certificateValidator: certificateValidator,
            onProgress: { [weak self] sent, total in
                self?.handleProgress(sent: sent, total: total)
            },
            onComplete: { [weak self] data in
                self?.handleUploadComplete(data: data)
            },
            onError: { [weak self] error in
                self?.handleError(error)
            }
        )
    }
    
    // MARK: - Event Handlers
    
    private func handleProgress(sent: Int64, total: Int64) {
        guard isActive else { return }
        
        let progress = total > 0 ? Double(sent) / Double(total) : 0.0
        
        fireEvent("progress", with: [
            "sent": sent,
            "total": total,
            "progress": progress
        ])
    }
    
    private func handleComplete(path: String) {
        guard isActive else { return }
        
        isActive = false
        
        TNMLogger.BackgroundTransfer.completed(
            transferId: transferId,
            type: "download",
            destination: path
        )
        
        fireEvent("complete", with: [
            "path": path,
            "type": "download"
        ])
    }
    
    private func handleUploadComplete(data: Data?) {
        guard isActive else { return }
        
        isActive = false
        
        TNMLogger.BackgroundTransfer.completed(
            transferId: transferId,
            type: "upload",
            destination: nil
        )
        
        var eventData: [String: Any] = ["type": "upload"]
        
        if let data = data, let response = String(data: data, encoding: .utf8) {
            eventData["response"] = response
        }
        
        fireEvent("complete", with: eventData)
    }
    
    private func handleError(_ error: Error) {
        guard isActive else { return }
        
        isActive = false
        
        TNMLogger.BackgroundTransfer.error(transferId: transferId, error: error)
        
        fireEvent("error", with: [
            "error": error.localizedDescription,
            "code": (error as NSError).code
        ])
    }
}
