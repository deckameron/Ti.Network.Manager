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
import CommonCrypto

class TNMCacheManager {
    
    // MARK: - Properties
    
    private var memoryCache: [String: CacheEntry] = [:]
    private let cacheLock = NSLock()
    private var memoryCacheSize: Int = 0
    private let maxMemoryCacheSize = 50 * 1024 * 1024 // 50 MB
    private let maxMemoryCacheCount = 100
    
    private let diskCachePath: URL
    private let fileManager = FileManager.default
    
    // MARK: - Initialization
    
    init() {
        let cachesDir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        diskCachePath = cachesDir.appendingPathComponent("TNMCache")
        
        if !fileManager.fileExists(atPath: diskCachePath.path) {
            try? fileManager.createDirectory(at: diskCachePath, withIntermediateDirectories: true)
        }
        
        TNMLogger.info("Cache manager initialized", feature: "Cache", details: [
            "diskPath": diskCachePath.path,
            "memoryLimit": "50 MB"
        ])
    }
    
    // MARK: - Public Methods
    
    func getCachedResponse(
        for key: String,
        maxAge: TimeInterval?
    ) -> CacheEntry? {
        cacheLock.lock()
        let entry = memoryCache[key]
        cacheLock.unlock()
        
        if let entry = entry {
            if !entry.isExpired(maxAge: maxAge) {
                let age = Date().timeIntervalSince(entry.timestamp)
                TNMLogger.Cache.hit(key: key, age: age)
                return entry.sanitized()
            } else {
                cacheLock.lock()
                memoryCache.removeValue(forKey: key)
                memoryCacheSize -= entry.bodyString.utf8.count
                cacheLock.unlock()
                
                TNMLogger.debug("Cache entry expired (memory)", feature: "Cache", details: ["key": key])
            }
        }
        
        if let diskEntry = loadFromDisk(key: key) {
            if !diskEntry.isExpired(maxAge: maxAge) {
               
                let sanitizedEntry = diskEntry.sanitized()
                
                cacheLock.lock()
                memoryCache[key] = sanitizedEntry
                memoryCacheSize += sanitizedEntry.bodyString.utf8.count
                evictIfNeeded()
                cacheLock.unlock()
                
                let age = Date().timeIntervalSince(sanitizedEntry.timestamp)
                TNMLogger.Cache.hit(key: key, age: age)
                return sanitizedEntry
            } else {
                removeFromDisk(key: key)
                TNMLogger.debug("Cache entry expired (disk)", feature: "Cache", details: ["key": key])
            }
        }
        
        TNMLogger.Cache.miss(key: key)
        return nil
    }
    
    func cacheResponse(
        for key: String,
        statusCode: Int,
        headers: [String: String],
        body: Data,
        etag: String?
    ) {
        
        let bodyString = String(data: body, encoding: .utf8) ?? ""
        
        let entry = CacheEntry(
            statusCode: statusCode,
            headers: headers,
            bodyString: bodyString,
            etag: etag,
            timestamp: Date()
        )
        
        cacheLock.lock()
        memoryCache[key] = entry
        memoryCacheSize += bodyString.utf8.count
        evictIfNeeded()
        cacheLock.unlock()
        
        DispatchQueue.global(qos: .utility).async { [weak self] in
            self?.saveToDisk(key: key, entry: entry)
        }
        
        TNMLogger.Cache.stored(key: key, size: bodyString.utf8.count)
    }
    
    func clearCache(for domain: String) {
        TNMLogger.debug("Clearing cache for domain", feature: "Cache", details: ["domain": domain])
        
        cacheLock.lock()
        memoryCache.removeAll()
        memoryCacheSize = 0
        cacheLock.unlock()
        
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
    }
    
    func clearAllCache() {
        TNMLogger.debug("Clearing all cache", feature: "Cache")
        
        cacheLock.lock()
        memoryCache.removeAll()
        memoryCacheSize = 0
        cacheLock.unlock()
        
        if let files = try? fileManager.contentsOfDirectory(at: diskCachePath, includingPropertiesForKeys: nil) {
            for file in files {
                try? fileManager.removeItem(at: file)
            }
        }
        
        TNMLogger.Cache.cleared(domain: nil)
    }
    
    func generateKey(url: String, method: String = "GET") -> String {
        return "\(method)-\(url)".sha256()
    }
    
    // MARK: - Private Methods
    
    private func loadFromDisk(key: String) -> CacheEntry? {
        let filePath = diskCachePath.appendingPathComponent(sanitizeKey(key))
        guard let data = try? Data(contentsOf: filePath) else { return nil }
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
        return key.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "?", with: "-")
    }
    
    private func evictIfNeeded() {
        if memoryCacheSize > maxMemoryCacheSize {
            let sortedEntries = memoryCache.sorted { $0.value.timestamp < $1.value.timestamp }
            
            for (key, entry) in sortedEntries {
                memoryCache.removeValue(forKey: key)
                memoryCacheSize -= entry.bodyString.utf8.count
                
                if memoryCacheSize <= maxMemoryCacheSize / 2 {
                    break
                }
            }
            
            TNMLogger.debug("Cache evicted by size", feature: "Cache", details: [
                "newSize": "\(memoryCacheSize) bytes"
            ])
        }
        
        if memoryCache.count > maxMemoryCacheCount {
            let sortedEntries = memoryCache.sorted { $0.value.timestamp < $1.value.timestamp }
            let toRemove = memoryCache.count - maxMemoryCacheCount
            
            for i in 0..<toRemove {
                let (key, entry) = sortedEntries[i]
                memoryCache.removeValue(forKey: key)
                memoryCacheSize -= entry.bodyString.utf8.count
            }
            
            TNMLogger.debug("Cache evicted by count", feature: "Cache", details: [
                "newCount": memoryCache.count
            ])
        }
    }
}

// MARK: - Cache Entry

struct CacheEntry: Codable {
    let statusCode: Int
    let headers: [String: String]
    let bodyString: String
    let etag: String?
    let timestamp: Date
    
    func isExpired(maxAge: TimeInterval?) -> Bool {
        guard let maxAge = maxAge else { return false }
        return Date().timeIntervalSince(timestamp) > maxAge
    }
    
    func sanitized() -> CacheEntry {
        // Forçar re-criação de todos os valores como Swift puros
        let pureHeaders: [String: String] = headers.reduce(into: [:]) { result, pair in
            // Força criação de String novos
            let key = String(pair.key)
            let value = String(pair.value)
            result[key] = value
        }
        
        return CacheEntry(
            statusCode: self.statusCode,
            headers: pureHeaders,
            bodyString: String(self.bodyString), // Nova instância
            etag: self.etag.map { String($0) },  // Nova instância se existir
            timestamp: self.timestamp
        )
    }
}

// MARK: - String Extension

extension String {
    func sha256() -> String {
        guard let data = self.data(using: .utf8) else { return self }
        
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes {
            _ = CC_SHA256($0.baseAddress, CC_LONG(data.count), &hash)
        }
        
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}
