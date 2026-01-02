//
//  TNMMultipartUploadManager.swift
//  TiNetworkManager
//
//  Created by Douglas Alves on 02/01/26.
//


/**
 * Ti.Network.Manager - Multipart Upload Manager
 * Feature #8: Multipart Upload Progress
 * Handles multipart/form-data uploads with per-file progress tracking
 */

import Foundation

class TNMMultipartUploadManager {
    
    // MARK: - Properties
    
    private var activeUploads: [String: URLSessionUploadTask] = [:]
    private var uploadDelegates: [String: MultipartUploadDelegate] = [:]
    private var sessions: [String: URLSession] = [:]
    
    // MARK: - Public Methods
    
    /**
     * Start multipart upload
     */
    func startUpload(
        uploadId: String,
        url: URL,
        fields: [MultipartField],
        headers: [String: String]?,
        priority: Float,
        certificateValidator: CertificateValidator?,
        onProgress: @escaping (MultipartUploadProgress) -> Void,
        onFileProgress: @escaping (String, Int64, Int64) -> Void,
        onComplete: @escaping (Int, [String: String], Data?) -> Void,
        onError: @escaping (Error) -> Void
    ) {
        TNMLogger.info("Starting multipart upload", feature: "MultipartUpload", details: [
            "uploadId": uploadId,
            "url": url.absoluteString,
            "fieldCount": fields.count
        ])
        
        // Build multipart body
        let builder = TNMMultipartBuilder()
        var fileFields: [(name: String, filename: String, size: Int64)] = []
        
        for field in fields {
            switch field {
            case .text(let name, let value):
                builder.addTextField(name: name, value: value)
                
            case .file(let name, let filename, let data, let mimeType):
                builder.addFileField(name: name, filename: filename, data: data, mimeType: mimeType)
                fileFields.append((name: name, filename: filename, size: Int64(data.count)))
            }
        }
        
        let multipartData = builder.finalize()
        let boundary = builder.boundary
        
        TNMLogger.debug("Multipart body built", feature: "MultipartUpload", details: [
            "uploadId": uploadId,
            "totalSize": "\(multipartData.count) bytes",
            "boundary": boundary,
            "fileCount": fileFields.count
        ])
        
        // Create delegate
        let delegate = MultipartUploadDelegate(
            uploadId: uploadId,
            fileFields: fileFields,
            totalSize: Int64(multipartData.count),
            onProgress: onProgress,
            onFileProgress: onFileProgress,
            onComplete: onComplete,
            onError: onError,
            certificateValidator: certificateValidator
        )
        
        uploadDelegates[uploadId] = delegate
        
        // Create session
        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = headers
        
        let session = URLSession(
            configuration: config,
            delegate: delegate,
            delegateQueue: nil
        )
        
        sessions[uploadId] = session
        
        // Create request
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        // Add custom headers
        if let headers = headers {
            for (key, value) in headers {
                request.setValue(value, forHTTPHeaderField: key)
            }
        }
        
        // Create upload task
        let task = session.uploadTask(with: request, from: multipartData)
        task.priority = priority
        
        activeUploads[uploadId] = task
        
        TNMLogger.debug("Upload task created", feature: "MultipartUpload", details: [
            "uploadId": uploadId,
            "taskIdentifier": task.taskIdentifier,
            "priority": priorityToString(priority)
        ])
        
        // Start upload
        task.resume()
    }
    
    /**
     * Cancel upload
     */
    func cancelUpload(uploadId: String) {
        TNMLogger.info("Cancelling multipart upload", feature: "MultipartUpload", details: [
            "uploadId": uploadId
        ])
        
        activeUploads[uploadId]?.cancel()
        activeUploads.removeValue(forKey: uploadId)
        uploadDelegates.removeValue(forKey: uploadId)
        sessions[uploadId]?.invalidateAndCancel()
        sessions.removeValue(forKey: uploadId)
    }
    
    // MARK: - Helpers
    
    private func priorityToString(_ priority: Float) -> String {
        if priority == URLSessionTask.highPriority {
            return "high"
        } else if priority == URLSessionTask.lowPriority {
            return "low"
        } else {
            return "normal"
        }
    }
}

// MARK: - Multipart Field

enum MultipartField {
    case text(name: String, value: String)
    case file(name: String, filename: String, data: Data, mimeType: String)
}

// MARK: - Multipart Upload Progress

struct MultipartUploadProgress {
    let uploadId: String
    let totalBytesSent: Int64
    let totalBytesExpected: Int64
    let overallProgress: Double
    let currentFile: String?
    let fileProgress: Double
}

// MARK: - Multipart Builder

class TNMMultipartBuilder {
    
    let boundary: String
    private var data = Data()
    
    init() {
        self.boundary = "Boundary-\(UUID().uuidString)"
    }
    
    func addTextField(name: String, value: String) {
        data.append("--\(boundary)\r\n".data(using: .utf8)!)
        data.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
        data.append("\(value)\r\n".data(using: .utf8)!)
        
        TNMLogger.debug("Text field added to multipart", feature: "MultipartUpload", details: [
            "name": name,
            "valueLength": value.count
        ])
    }
    
    func addFileField(name: String, filename: String, data fileData: Data, mimeType: String) {
        data.append("--\(boundary)\r\n".data(using: .utf8)!)
        data.append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        data.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        data.append(fileData)
        data.append("\r\n".data(using: .utf8)!)
        
        TNMLogger.debug("File field added to multipart", feature: "MultipartUpload", details: [
            "name": name,
            "filename": filename,
            "mimeType": mimeType,
            "size": "\(fileData.count) bytes"
        ])
    }
    
    func finalize() -> Data {
        var finalData = data
        finalData.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        TNMLogger.debug("Multipart body finalized", feature: "MultipartUpload", details: [
            "totalSize": "\(finalData.count) bytes"
        ])
        
        return finalData
    }
}

// MARK: - Multipart Upload Delegate

class MultipartUploadDelegate: NSObject, URLSessionTaskDelegate, URLSessionDataDelegate {
    
    let uploadId: String
    let fileFields: [(name: String, filename: String, size: Int64)]
    let totalSize: Int64
    let onProgress: (MultipartUploadProgress) -> Void
    let onFileProgress: (String, Int64, Int64) -> Void
    let onComplete: (Int, [String: String], Data?) -> Void
    let onError: (Error) -> Void
    let certificateValidator: CertificateValidator?
    
    private var responseData = Data()
    private var currentFileIndex = 0
    private var lastBytesSent: Int64 = 0
    
    init(
        uploadId: String,
        fileFields: [(name: String, filename: String, size: Int64)],
        totalSize: Int64,
        onProgress: @escaping (MultipartUploadProgress) -> Void,
        onFileProgress: @escaping (String, Int64, Int64) -> Void,
        onComplete: @escaping (Int, [String: String], Data?) -> Void,
        onError: @escaping (Error) -> Void,
        certificateValidator: CertificateValidator?
    ) {
        self.uploadId = uploadId
        self.fileFields = fileFields
        self.totalSize = totalSize
        self.onProgress = onProgress
        self.onFileProgress = onFileProgress
        self.onComplete = onComplete
        self.onError = onError
        self.certificateValidator = certificateValidator
    }
    
    // MARK: - URLSessionTaskDelegate
    
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        let overallProgress = Double(totalBytesSent) / Double(totalBytesExpectedToSend)
        
        // Calculate which file we're currently uploading
        var accumulatedSize: Int64 = 0
        var currentFile: String?
        var fileProgress: Double = 0.0
        
        for (index, field) in fileFields.enumerated() {
            let nextAccumulatedSize = accumulatedSize + field.size
            
            if totalBytesSent >= accumulatedSize && totalBytesSent < nextAccumulatedSize {
                // Currently uploading this file
                currentFile = field.filename
                let fileBytesSent = totalBytesSent - accumulatedSize
                fileProgress = Double(fileBytesSent) / Double(field.size)
                currentFileIndex = index
                
                // Fire per-file progress
                onFileProgress(field.filename, fileBytesSent, field.size)
                
                TNMLogger.debug("File upload progress", feature: "MultipartUpload", details: [
                    "uploadId": uploadId,
                    "filename": field.filename,
                    "fileProgress": String(format: "%.1f%%", fileProgress * 100),
                    "fileIndex": "\(index + 1)/\(fileFields.count)"
                ])
                
                break
            }
            
            accumulatedSize = nextAccumulatedSize
        }
        
        // Fire overall progress
        let progress = MultipartUploadProgress(
            uploadId: uploadId,
            totalBytesSent: totalBytesSent,
            totalBytesExpected: totalBytesExpectedToSend,
            overallProgress: overallProgress,
            currentFile: currentFile,
            fileProgress: fileProgress
        )
        
        onProgress(progress)
        
        // Log overall progress periodically (every 10% or so)
        let percentSent = Double(totalBytesSent) / Double(totalBytesExpectedToSend) * 100
        let lastPercent = Double(lastBytesSent) / Double(totalBytesExpectedToSend) * 100
        
        if Int(percentSent / 10) > Int(lastPercent / 10) {
            TNMLogger.debug("Overall upload progress", feature: "MultipartUpload", details: [
                "uploadId": uploadId,
                "progress": String(format: "%.1f%%", percentSent),
                "sent": "\(totalBytesSent) bytes",
                "total": "\(totalBytesExpectedToSend) bytes"
            ])
        }
        
        lastBytesSent = totalBytesSent
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            TNMLogger.error("Multipart upload failed", feature: "MultipartUpload", error: error, details: [
                "uploadId": uploadId
            ])
            onError(error)
            return
        }
        
        guard let httpResponse = task.response as? HTTPURLResponse else {
            let error = NSError(
                domain: "TNMMultipartUploadManager",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Invalid response"]
            )
            TNMLogger.error("Invalid response", feature: "MultipartUpload", error: error, details: [
                "uploadId": uploadId
            ])
            onError(error)
            return
        }
        
        let statusCode = httpResponse.statusCode
        var headers: [String: String] = [:]
        
        for (key, value) in httpResponse.allHeaderFields {
            if let keyString = key as? String, let valueString = value as? String {
                headers[keyString] = valueString
            }
        }
        
        TNMLogger.success("Multipart upload completed", feature: "MultipartUpload", details: [
            "uploadId": uploadId,
            "statusCode": statusCode,
            "responseSize": "\(responseData.count) bytes"
        ])
        
        onComplete(statusCode, headers, responseData)
    }
    
    // MARK: - URLSessionDataDelegate
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        responseData.append(data)
    }
    
    // MARK: - Certificate Validation
    
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard let certificateValidator = certificateValidator else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust {
            if let serverTrust = challenge.protectionSpace.serverTrust {
                if certificateValidator.validate(serverTrust: serverTrust, for: challenge.protectionSpace.host) {
                    let credential = URLCredential(trust: serverTrust)
                    completionHandler(.useCredential, credential)
                } else {
                    completionHandler(.cancelAuthenticationChallenge, nil)
                }
            } else {
                completionHandler(.cancelAuthenticationChallenge, nil)
            }
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}
