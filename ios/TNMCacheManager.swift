//
//  TNMCacheManager.swift
//  TiNetworkManager
//
//  Created by Douglas Alves on 02/01/26.
//


/**
 * Ti.Network.Manager - Cache Manager
 * Advanced caching with ETags and custom strategies
 * Supports: cache-first, network-first, network-only policies
 */

import Foundation

class TNMCacheManager {
    
    // MARK: - Properties
    
    private let memoryCache = NSCache<NSString, CacheEntry>()
    private let diskCachePath: URL
    private let fileManager = FileManager.default
    
    // MARK: - Initialization
    
    init() {
        // Setup disk cache directory
        let cachesDir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        diskCachePath = cachesDir.appendingPathComponent("TNMCache")
        
        // Create directory if needed
        if !fileManager.fileExists(atPath: diskCachePath.path) {
            try? fileManager.createDirectory(at: diskCachePath, withIntermediateDirectories: true)
        }
        
        // Configure memory cache
        memoryCache.countLimit = 100
        memoryCache.totalCostLimit = 50 * 1024 * 1024 // 50 MB
        
        TNMLogger.info("Cache manager initialized", feature: "Cache", details: [
            "diskPath": diskCachePath.path,
            "memoryLimit": "50 MB"
        ])
    }
    
    // MARK: - Public Methods
    
    /**
     * Get cached response
     */
    func getCachedResponse(
        for key: String,
        maxAge: TimeInterval?
    ) -> CacheEntry? {
        // Try memory cache first
        if let entry = memoryCache.object(forKey: key as NSString) {
            if !entry.isExpired(maxAge: maxAge) {
                let age = Date().timeIntervalSince(entry.timestamp)
                TNMLogger.Cache.hit(key: key, age: age)
                return entry
            } else {
                // Expired, remove
                memoryCache.removeObject(forKey: key as NSString)
                TNMLogger.debug("Cache entry expired (memory)", feature: "Cache", details: [
                    "key": key
                ])
            }
        }
        
        // Try disk cache
        if let entry = loadFromDisk(key: key) {
            if !entry.isExpired(maxAge: maxAge) {
                // Store in memory cache for faster access
                memoryCache.setObject(entry, forKey: key as NSString)
                
                let age = Date().timeIntervalSince(entry.timestamp)
                TNMLogger.Cache.hit(key: key, age: age)
                return entry
            } else {
                // Expired, remove
                removeFromDisk(key: key)
                TNMLogger.debug("Cache entry expired (disk)", feature: "Cache", details: [
                    "key": key
                ])
            }
        }
        
        TNMLogger.Cache.miss(key: key)
        return nil
    }
    
    /**
     * Store response in cache
     */
    func cacheResponse(
        for key: String,
        statusCode: Int,
        headers: [String: String],
        body: Data,
        etag: String?
    ) {
        let entry = CacheEntry(
            statusCode: statusCode,
            headers: headers,
            body: body,
            etag: etag,
            timestamp: Date()
        )
        
        // Store in memory
        memoryCache.setObject(entry, forKey: key as NSString, cost: body.count)
        
        // Store on disk
        saveToDisk(key: key, entry: entry)
        
        TNMLogger.Cache.stored(key: key, size: body.count)
    }
    
    /**
     * Clear cache for specific domain
     */
    func clearCache(for domain: String) {
        TNMLogger.debug("Clearing cache for domain", feature: "Cache", details: [
            "domain": domain
        ])
        
        // Clear from memory
        memoryCache.removeAllObjects()
        
        // Clear from disk (matching domain prefix)
        var clearedCount = 0
        if let files = try? fileManager.contentsOfDirectory(at: diskCachePath, includingPropertiesForKeys: nil) {
            for file in files {
                if file.lastPathComponent.hasPrefix(sanitizeKey(domain)) {
                    try? fileManager.removeItem(at: file)
                    clearedCount += 1
                }
            }
        }
        
        TNMLogger.Cache.cleared(domain: domain)
        TNMLogger.debug("Cache cleared", feature: "Cache", details: [
            "domain": domain,
            "filesRemoved": clearedCount
        ])
    }
    
    /**
     * Clear all cache
     */
    func clearAllCache() {
        TNMLogger.debug("Clearing all cache", feature: "Cache")
        
        memoryCache.removeAllObjects()
        
        var clearedCount = 0
        if let files = try? fileManager.contentsOfDirectory(at: diskCachePath, includingPropertiesForKeys: nil) {
            for file in files {
                try? fileManager.removeItem(at: file)
                clearedCount += 1
            }
        }
        
        TNMLogger.Cache.cleared(domain: nil)
        TNMLogger.debug("All cache cleared", feature: "Cache", details: [
            "filesRemoved": clearedCount
        ])
    }
    
    /**
     * Generate cache key from URL
     */
    func generateKey(url: String, method: String = "GET") -> String {
        return "\(method)-\(url)".sha256()
    }
    
    // MARK: - Private Methods
    
    private func loadFromDisk(key: String) -> CacheEntry? {
        let filePath = diskCachePath.appendingPathComponent(sanitizeKey(key))
        
        guard let data = try? Data(contentsOf: filePath) else {
            return nil
        }
        
        return try? JSONDecoder().decode(CacheEntry.self, from: data)
    }
    
    private func saveToDisk(key: String, entry: CacheEntry) {
        let filePath = diskCachePath.appendingPathComponent(sanitizeKey(key))
        
        if let data = try? JSONEncoder().encode(entry) {
            try? data.write(to: filePath)
        }
    }
    
    private func removeFromDisk(key: String) {
        let filePath = diskCachePath.appendingPathComponent(sanitizeKey(key))
        try? fileManager.removeItem(at: filePath)
    }
    
    private func sanitizeKey(_ key: String) -> String {
        // Remove invalid filename characters
        return key.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "?", with: "-")
    }
}

// MARK: - Cache Entry

class CacheEntry: NSObject, Codable {
    let statusCode: Int
    let headers: [String: String]
    let body: Data
    let etag: String?
    let timestamp: Date
    
    init(statusCode: Int, headers: [String: String], body: Data, etag: String?, timestamp: Date) {
        self.statusCode = statusCode
        self.headers = headers
        self.body = body
        self.etag = etag
        self.timestamp = timestamp
    }
    
    func isExpired(maxAge: TimeInterval?) -> Bool {
        guard let maxAge = maxAge else {
            return false
        }
        
        return Date().timeIntervalSince(timestamp) > maxAge
    }
}

// MARK: - String Extension for SHA256

extension String {
    func sha256() -> String {
        guard let data = self.data(using: .utf8) else {
            return self
        }
        
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes {
            _ = CC_SHA256($0.baseAddress, CC_LONG(data.count), &hash)
        }
        
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}

import CommonCrypto
