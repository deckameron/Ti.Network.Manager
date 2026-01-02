//
//  TNMBackgroundTransferManager.swift
//  TiNetworkManager
//
//  Created by Douglas Alves on 02/01/26.
//


/**
 * Ti.Network.Manager - Background Transfer Manager
 * Feature #6: Background Transfers
 * Handles downloads/uploads that continue when app is backgrounded
 */

import Foundation

class TNMBackgroundTransferManager: NSObject {
    
    // MARK: - Properties
    
    private var activeDownloads: [String: URLSessionDownloadTask] = [:]
    private var activeUploads: [String: URLSessionUploadTask] = [:]
    private var downloadDelegates: [String: BackgroundDownloadDelegate] = [:]
    private var uploadDelegates: [String: BackgroundUploadDelegate] = [:]
    private var backgroundSession: URLSession!
    
    // MARK: - Initialization
    
    override init() {
        super.init()
        
        // Create background session configuration
        let config = URLSessionConfiguration.background(withIdentifier: "ti.network.manager.background")
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        
        backgroundSession = URLSession(
            configuration: config,
            delegate: self,
            delegateQueue: nil
        )
        
        TNMLogger.info("Background transfer manager initialized", feature: "BackgroundTransfer", details: [
            "identifier": "ti.network.manager.background"
        ])
    }
    
    // MARK: - Download Methods
    
    /**
     * Start background download
     */
    func startDownload(
        transferId: String,
        url: URL,
        destination: String,
        headers: [String: String]?,
        certificateValidator: CertificateValidator?,
        onProgress: @escaping (Int64, Int64) -> Void,
        onComplete: @escaping (String) -> Void,
        onError: @escaping (Error) -> Void
    ) {
        TNMLogger.info("Starting background download", feature: "BackgroundTransfer", details: [
            "transferId": transferId,
            "url": url.absoluteString,
            "destination": destination
        ])
        
        // Create delegate
        let delegate = BackgroundDownloadDelegate(
            transferId: transferId,
            destination: destination,
            onProgress: onProgress,
            onComplete: onComplete,
            onError: onError,
            certificateValidator: certificateValidator
        )
        
        downloadDelegates[transferId] = delegate
        
        // Create request
        var request = URLRequest(url: url)
        
        // Add headers
        if let headers = headers {
            for (key, value) in headers {
                request.setValue(value, forHTTPHeaderField: key)
            }
        }
        
        // Create download task
        let task = backgroundSession.downloadTask(with: request)
        activeDownloads[transferId] = task
        
        TNMLogger.debug("Download task created", feature: "BackgroundTransfer", details: [
            "transferId": transferId,
            "taskIdentifier": task.taskIdentifier
        ])
        
        // Start download
        task.resume()
    }
    
    /**
     * Cancel download
     */
    func cancelDownload(transferId: String) {
        TNMLogger.info("Cancelling download", feature: "BackgroundTransfer", details: [
            "transferId": transferId
        ])
        
        activeDownloads[transferId]?.cancel()
        activeDownloads.removeValue(forKey: transferId)
        downloadDelegates.removeValue(forKey: transferId)
    }
    
    /**
     * Pause download
     */
    func pauseDownload(transferId: String, completion: @escaping (Data?) -> Void) {
        guard let task = activeDownloads[transferId] else {
            completion(nil)
            return
        }
        
        TNMLogger.info("Pausing download", feature: "BackgroundTransfer", details: [
            "transferId": transferId
        ])
        
        task.cancel(byProducingResumeData: { resumeData in
            completion(resumeData)
        })
    }
    
    /**
     * Resume download
     */
    func resumeDownload(transferId: String, resumeData: Data) {
        TNMLogger.info("Resuming download", feature: "BackgroundTransfer", details: [
            "transferId": transferId,
            "resumeDataSize": "\(resumeData.count) bytes"
        ])
        
        let task = backgroundSession.downloadTask(withResumeData: resumeData)
        activeDownloads[transferId] = task
        task.resume()
    }
    
    // MARK: - Upload Methods
    
    /**
     * Start background upload
     */
    func startUpload(
        transferId: String,
        url: URL,
        fileURL: URL,
        headers: [String: String]?,
        certificateValidator: CertificateValidator?,
        onProgress: @escaping (Int64, Int64) -> Void,
        onComplete: @escaping (Data?) -> Void,
        onError: @escaping (Error) -> Void
    ) {
        TNMLogger.info("Starting background upload", feature: "BackgroundTransfer", details: [
            "transferId": transferId,
            "url": url.absoluteString,
            "file": fileURL.path
        ])
        
        // Create delegate
        let delegate = BackgroundUploadDelegate(
            transferId: transferId,
            onProgress: onProgress,
            onComplete: onComplete,
            onError: onError,
            certificateValidator: certificateValidator
        )
        
        uploadDelegates[transferId] = delegate
        
        // Create request
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        // Add headers
        if let headers = headers {
            for (key, value) in headers {
                request.setValue(value, forHTTPHeaderField: key)
            }
        }
        
        // Create upload task
        let task = backgroundSession.uploadTask(with: request, fromFile: fileURL)
        activeUploads[transferId] = task
        
        TNMLogger.debug("Upload task created", feature: "BackgroundTransfer", details: [
            "transferId": transferId,
            "taskIdentifier": task.taskIdentifier
        ])
        
        // Start upload
        task.resume()
    }
    
    /**
     * Cancel upload
     */
    func cancelUpload(transferId: String) {
        TNMLogger.info("Cancelling upload", feature: "BackgroundTransfer", details: [
            "transferId": transferId
        ])
        
        activeUploads[transferId]?.cancel()
        activeUploads.removeValue(forKey: transferId)
        uploadDelegates.removeValue(forKey: transferId)
    }
    
    // MARK: - Helper Methods
    
    private func findDelegateForTask(_ task: URLSessionTask) -> (String, BackgroundDownloadDelegate)? {
        for (transferId, delegate) in downloadDelegates {
            if activeDownloads[transferId]?.taskIdentifier == task.taskIdentifier {
                return (transferId, delegate)
            }
        }
        return nil
    }
    
    private func findUploadDelegateForTask(_ task: URLSessionTask) -> (String, BackgroundUploadDelegate)? {
        for (transferId, delegate) in uploadDelegates {
            if activeUploads[transferId]?.taskIdentifier == task.taskIdentifier {
                return (transferId, delegate)
            }
        }
        return nil
    }
}

// MARK: - URLSessionDelegate

extension TNMBackgroundTransferManager: URLSessionDelegate {
    
    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        TNMLogger.info("Background session completed all events", feature: "BackgroundTransfer")
        
        DispatchQueue.main.async {
            // Notify app that background work is done
            // App delegate can call completion handler here
        }
    }
}

// MARK: - URLSessionDownloadDelegate

extension TNMBackgroundTransferManager: URLSessionDownloadDelegate {
    
    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let (transferId, delegate) = findDelegateForTask(downloadTask) else {
            TNMLogger.warning("No delegate found for download task", feature: "BackgroundTransfer")
            return
        }
        
        TNMLogger.success("Download completed", feature: "BackgroundTransfer", details: [
            "transferId": transferId,
            "temporaryLocation": location.path
        ])
        
        // Move file to destination
        do {
            let destinationURL = URL(fileURLWithPath: delegate.destination)
            
            // Remove existing file if present
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            
            // Move downloaded file
            try FileManager.default.moveItem(at: location, to: destinationURL)
            
            TNMLogger.success("File moved to destination", feature: "BackgroundTransfer", details: [
                "transferId": transferId,
                "destination": destinationURL.path
            ])
            
            delegate.onComplete(destinationURL.path)
            
            // Cleanup
            activeDownloads.removeValue(forKey: transferId)
            downloadDelegates.removeValue(forKey: transferId)
            
        } catch {
            TNMLogger.error("Failed to move downloaded file", feature: "BackgroundTransfer", error: error, details: [
                "transferId": transferId
            ])
            delegate.onError(error)
        }
    }
    
    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard let (transferId, delegate) = findDelegateForTask(downloadTask) else { return }
        
        let percentage = totalBytesExpectedToWrite > 0 ?
            Double(totalBytesWritten) / Double(totalBytesExpectedToWrite) * 100.0 : 0.0
        
        TNMLogger.debug("Download progress", feature: "BackgroundTransfer", details: [
            "transferId": transferId,
            "progress": String(format: "%.1f%%", percentage),
            "written": "\(totalBytesWritten) bytes",
            "total": "\(totalBytesExpectedToWrite) bytes"
        ])
        
        delegate.onProgress(totalBytesWritten, totalBytesExpectedToWrite)
    }
}

// MARK: - URLSessionTaskDelegate

extension TNMBackgroundTransferManager: URLSessionTaskDelegate {
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            // Handle download error
            if let (transferId, delegate) = findDelegateForTask(task) {
                TNMLogger.error("Download failed", feature: "BackgroundTransfer", error: error, details: [
                    "transferId": transferId
                ])
                delegate.onError(error)
                
                activeDownloads.removeValue(forKey: transferId)
                downloadDelegates.removeValue(forKey: transferId)
            }
            // Handle upload error
            else if let (transferId, delegate) = findUploadDelegateForTask(task) {
                TNMLogger.error("Upload failed", feature: "BackgroundTransfer", error: error, details: [
                    "transferId": transferId
                ])
                delegate.onError(error)
                
                activeUploads.removeValue(forKey: transferId)
                uploadDelegates.removeValue(forKey: transferId)
            }
        }
    }
    
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        guard let (transferId, delegate) = findUploadDelegateForTask(task) else { return }
        
        let percentage = totalBytesExpectedToSend > 0 ?
            Double(totalBytesSent) / Double(totalBytesExpectedToSend) * 100.0 : 0.0
        
        TNMLogger.debug("Upload progress", feature: "BackgroundTransfer", details: [
            "transferId": transferId,
            "progress": String(format: "%.1f%%", percentage),
            "sent": "\(totalBytesSent) bytes",
            "total": "\(totalBytesExpectedToSend) bytes"
        ])
        
        delegate.onProgress(totalBytesSent, totalBytesExpectedToSend)
    }
    
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        // Find appropriate certificate validator
        // For now, use default handling
        completionHandler(.performDefaultHandling, nil)
    }
}

// MARK: - Background Download Delegate

class BackgroundDownloadDelegate {
    let transferId: String
    let destination: String
    let onProgress: (Int64, Int64) -> Void
    let onComplete: (String) -> Void
    let onError: (Error) -> Void
    let certificateValidator: CertificateValidator?
    
    init(
        transferId: String,
        destination: String,
        onProgress: @escaping (Int64, Int64) -> Void,
        onComplete: @escaping (String) -> Void,
        onError: @escaping (Error) -> Void,
        certificateValidator: CertificateValidator?
    ) {
        self.transferId = transferId
        self.destination = destination
        self.onProgress = onProgress
        self.onComplete = onComplete
        self.onError = onError
        self.certificateValidator = certificateValidator
    }
}

// MARK: - Background Upload Delegate

class BackgroundUploadDelegate {
    let transferId: String
    let onProgress: (Int64, Int64) -> Void
    let onComplete: (Data?) -> Void
    let onError: (Error) -> Void
    let certificateValidator: CertificateValidator?
    
    init(
        transferId: String,
        onProgress: @escaping (Int64, Int64) -> Void,
        onComplete: @escaping (Data?) -> Void,
        onError: @escaping (Error) -> Void,
        certificateValidator: CertificateValidator?
    ) {
        self.transferId = transferId
        self.onProgress = onProgress
        self.onComplete = onComplete
        self.onError = onError
        self.certificateValidator = certificateValidator
    }
}
