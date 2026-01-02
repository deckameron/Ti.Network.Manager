//
//  TNMMultipartUploadProxy.swift
//  TiNetworkManager
//
//  Created by Douglas Alves on 02/01/26.
//


/**
 * Ti.Network.Manager - Multipart Upload Proxy
 * Proxy for multipart/form-data uploads with per-file progress
 * Exposed to JavaScript for creating multipart uploads
 */

import TitaniumKit
import Foundation

@objc(TiHTTPMultipartUploadProxy)
class TNMMultipartUploadProxy: TiProxy {
    
    // MARK: - Properties
    
    private var multipartManager: TNMMultipartUploadManager
    private var certificatePinningManager: TNMCertificatePinningManager
    
    private var uploadId: String
    private var url: String
    private var fields: [MultipartField]
    private var headers: [String: String]
    private var priority: String
    
    private var isActive = false
    
    // MARK: - Initialization
    
    init(
        params: [String: Any],
        multipartManager: TNMMultipartUploadManager,
        certificatePinningManager: TNMCertificatePinningManager
    ) {
        self.multipartManager = multipartManager
        self.certificatePinningManager = certificatePinningManager
        
        self.uploadId = UUID().uuidString
        self.url = params["url"] as? String ?? ""
        self.headers = params["headers"] as? [String: String] ?? [:]
        self.priority = params["priority"] as? String ?? "normal"
        
        // Parse fields
        var parsedFields: [MultipartField] = []
        
        if let fieldsArray = params["fields"] as? [[String: Any]] {
            for fieldDict in fieldsArray {
                if let type = fieldDict["type"] as? String {
                    if type == "text" {
                        // Text field
                        if let name = fieldDict["name"] as? String,
                           let value = fieldDict["value"] as? String {
                            parsedFields.append(.text(name: name, value: value))
                        }
                    } else if type == "file" {
                        // File field
                        if let name = fieldDict["name"] as? String,
                           let filename = fieldDict["filename"] as? String,
                           let mimeType = fieldDict["mimeType"] as? String {
                            
                            // Get file data (can be base64 or file path)
                            if let base64 = fieldDict["data"] as? String,
                               let data = Data(base64Encoded: base64) {
                                parsedFields.append(.file(name: name, filename: filename, data: data, mimeType: mimeType))
                            } else if let filePath = fieldDict["file"] as? String,
                                      let fileURL = URL(string: filePath),
                                      let data = try? Data(contentsOf: fileURL) {
                                parsedFields.append(.file(name: name, filename: filename, data: data, mimeType: mimeType))
                            }
                        }
                    }
                }
            }
        }
        
        self.fields = parsedFields
        
        super.init()
        
        TNMLogger.debug("Multipart upload proxy created", feature: "MultipartUpload", details: [
            "uploadId": uploadId,
            "url": url,
            "fieldCount": parsedFields.count,
            "priority": priority
        ])
    }
    
    // MARK: - Public API
    
    /**
     * Start the multipart upload
     * 
     * @param arguments Unused arguments array (required by Titanium)
     */
    @objc(upload:)
    func upload(arguments: [Any]?) {
        guard !isActive else {
            TNMLogger.warning("Multipart upload already active", feature: "MultipartUpload", details: [
                "uploadId": uploadId
            ])
            return
        }
        
        guard let url = URL(string: self.url) else {
            TNMLogger.error("Invalid URL for multipart upload", feature: "MultipartUpload", details: [
                "uploadId": uploadId,
                "url": self.url
            ])
            fireEvent("error", with: ["error": "Invalid URL"])
            return
        }
        
        guard !fields.isEmpty else {
            TNMLogger.error("No fields provided for multipart upload", feature: "MultipartUpload", details: [
                "uploadId": uploadId
            ])
            fireEvent("error", with: ["error": "No fields provided"])
            return
        }
        
        isActive = true
        
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
        
        // Get certificate validator
        let certificateValidator = certificatePinningManager.getValidator(for: url.host ?? "")
        
        // Start upload
        multipartManager.startUpload(
            uploadId: uploadId,
            url: url,
            fields: fields,
            headers: headers,
            priority: urlPriority,
            certificateValidator: certificateValidator,
            onProgress: { [weak self] progress in
                self?.handleProgress(progress)
            },
            onFileProgress: { [weak self] filename, sent, total in
                self?.handleFileProgress(filename: filename, sent: sent, total: total)
            },
            onComplete: { [weak self] statusCode, headers, data in
                self?.handleComplete(statusCode: statusCode, headers: headers, data: data)
            },
            onError: { [weak self] error in
                self?.handleError(error)
            }
        )
    }
    
    /**
     * Cancel the upload
     * 
     * @param arguments Unused arguments array (required by Titanium)
     */
    @objc(cancel:)
    func cancel(arguments: [Any]?) {
        guard isActive else { return }
        
        TNMLogger.info("Cancelling multipart upload", feature: "MultipartUpload", details: [
            "uploadId": uploadId
        ])
        
        multipartManager.cancelUpload(uploadId: uploadId)
        isActive = false
        
        fireEvent("cancelled", with: [:])
    }
    
    // MARK: - Event Handlers
    
    private func handleProgress(_ progress: MultipartUploadProgress) {
        guard isActive else { return }
        
        var eventData: [String: Any] = [
            "sent": progress.totalBytesSent,
            "total": progress.totalBytesExpected,
            "progress": progress.overallProgress
        ]
        
        if let currentFile = progress.currentFile {
            eventData["currentFile"] = currentFile
            eventData["fileProgress"] = progress.fileProgress
        }
        
        fireEvent("progress", with: eventData)
    }
    
    private func handleFileProgress(filename: String, sent: Int64, total: Int64) {
        guard isActive else { return }
        
        let progress = Double(sent) / Double(total)
        
        fireEvent("fileprogress", with: [
            "filename": filename,
            "sent": sent,
            "total": total,
            "progress": progress
        ])
    }
    
    private func handleComplete(statusCode: Int, headers: [String: String], data: Data?) {
        guard isActive else { return }
        
        isActive = false
        
        var eventData: [String: Any] = [
            "statusCode": statusCode,
            "headers": headers,
            "success": statusCode >= 200 && statusCode < 300
        ]
        
        if let data = data, let response = String(data: data, encoding: .utf8) {
            eventData["body"] = response
        }
        
        TNMLogger.success("Multipart upload completed", feature: "MultipartUpload", details: [
            "uploadId": uploadId,
            "statusCode": statusCode
        ])
        
        fireEvent("complete", with: eventData)
    }
    
    private func handleError(_ error: Error) {
        guard isActive else { return }
        
        isActive = false
        
        TNMLogger.error("Multipart upload error", feature: "MultipartUpload", error: error, details: [
            "uploadId": uploadId
        ])
        
        fireEvent("error", with: [
            "error": error.localizedDescription,
            "code": (error as NSError).code
        ])
    }
}
