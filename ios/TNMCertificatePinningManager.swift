//
//  TNMCertificatePinningManager.swift
//  TiNetworkManager
//
//  Created by Douglas Alves on 02/01/26.
//


/**
 * Ti.Network.Manager - Certificate Pinning Manager
 * Handles certificate pinning for domains
 * Prevents man-in-the-middle attacks by validating certificate public key hashes
 */

import Foundation
import CommonCrypto

class TNMCertificatePinningManager {
    
    // MARK: - Properties
    
    private var pinnedDomains: [String: [String]] = [:]
    
    // MARK: - Public Methods
    
    /**
     * Set certificate pins for a domain
     */
    func setPinning(for domain: String, hashes: [String]) {
        pinnedDomains[domain] = hashes
        TNMLogger.CertificatePinning.configured(domain: domain, hashCount: hashes.count)
    }
    
    /**
     * Remove pinning for a domain
     */
    func removePinning(for domain: String) {
        pinnedDomains.removeValue(forKey: domain)
        
        TNMLogger.info("Certificate pinning removed", feature: "CertPinning", details: [
            "domain": domain
        ])
    }
    
    /**
     * Clear all pinning
     */
    func clearAll() {
        let count = pinnedDomains.count
        pinnedDomains.removeAll()
        
        TNMLogger.info("All certificate pinning cleared", feature: "CertPinning", details: [
            "domainsCleared": count
        ])
    }
    
    /**
     * Get certificate validator for domain
     */
    func getValidator(for domain: String) -> CertificateValidator? {
        guard let hashes = pinnedDomains[domain] else {
            TNMLogger.debug("No certificate pinning configured", feature: "CertPinning", details: [
                "domain": domain
            ])
            return nil
        }
        
        TNMLogger.debug("Certificate validator created", feature: "CertPinning", details: [
            "domain": domain,
            "hashCount": hashes.count
        ])
        
        return CertificateValidator(pinnedHashes: hashes)
    }
}

// MARK: - Certificate Validator

class CertificateValidator {
    
    private let pinnedHashes: [String]
    
    init(pinnedHashes: [String]) {
        self.pinnedHashes = pinnedHashes
    }
    
    /**
     * Validate server trust against pinned hashes
     */
    func validate(serverTrust: SecTrust, for domain: String) -> Bool {
        TNMLogger.CertificatePinning.validationStarted(domain: domain)
        
        // Get certificate chain
        guard let certificates = getCertificates(from: serverTrust) else {
            TNMLogger.CertificatePinning.validationFailed(
                domain: domain,
                reason: "Failed to get certificates from server trust"
            )
            return false
        }
        
        // Extract public key hashes from certificate chain
        var foundMatch = false
        
        for certificate in certificates {
            if let publicKeyHash = getPublicKeyHash(from: certificate) {
                TNMLogger.debug("Checking certificate hash", feature: "CertPinning", details: [
                    "domain": domain,
                    "hash": publicKeyHash.prefix(20) + "..."
                ])
                
                // Check if hash matches any pinned hash
                if pinnedHashes.contains(publicKeyHash) {
                    foundMatch = true
                    break
                }
            }
        }
        
        if foundMatch {
            TNMLogger.CertificatePinning.validationSuccess(domain: domain)
        } else {
            TNMLogger.CertificatePinning.validationFailed(
                domain: domain,
                reason: "No matching certificate hash found in pinned hashes"
            )
        }
        
        return foundMatch
    }
    
    // MARK: - Private Helpers
    
    private func getCertificates(from serverTrust: SecTrust) -> [SecCertificate]? {
        var certificates: [SecCertificate] = []
        
        if #available(iOS 15.0, *) {
            // iOS 15+ API
            guard let certificateChain = SecTrustCopyCertificateChain(serverTrust) as? [SecCertificate] else {
                TNMLogger.debug("Failed to get certificate chain (iOS 15+)", feature: "CertPinning")
                return nil
            }
            certificates = certificateChain
        } else {
            // Legacy API for iOS < 15
            let certificateCount = SecTrustGetCertificateCount(serverTrust)
            
            TNMLogger.debug("Getting certificates (iOS < 15)", feature: "CertPinning", details: [
                "certificateCount": certificateCount
            ])
            
            for i in 0..<certificateCount {
                if let certificate = SecTrustGetCertificateAtIndex(serverTrust, i) {
                    certificates.append(certificate)
                }
            }
        }
        
        if certificates.isEmpty {
            TNMLogger.debug("No certificates found in chain", feature: "CertPinning")
            return nil
        }
        
        TNMLogger.debug("Certificates retrieved", feature: "CertPinning", details: [
            "count": certificates.count
        ])
        
        return certificates
    }
    
    private func getPublicKeyHash(from certificate: SecCertificate) -> String? {
        // Get public key from certificate
        guard let publicKey = SecCertificateCopyKey(certificate) else {
            TNMLogger.debug("Failed to get public key from certificate", feature: "CertPinning")
            return nil
        }
        
        // Get public key data
        guard let publicKeyData = SecKeyCopyExternalRepresentation(publicKey, nil) as Data? else {
            TNMLogger.debug("Failed to get public key data", feature: "CertPinning")
            return nil
        }
        
        // Calculate SHA-256 hash
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        publicKeyData.withUnsafeBytes {
            _ = CC_SHA256($0.baseAddress, CC_LONG(publicKeyData.count), &hash)
        }
        
        // Convert to base64 string (format: sha256/BASE64HASH)
        let hashData = Data(hash)
        let base64Hash = hashData.base64EncodedString()
        
        return "sha256/\(base64Hash)"
    }
}
