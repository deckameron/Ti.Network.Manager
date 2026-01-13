/**
 * Ti.Network.Manager - Cache Manager
 * Manages HTTP response caching with TTL support
 * Uses OkHttp's Cache + custom in-memory cache
 */

package ti.network.manager;

import android.content.Context;
import com.google.gson.Gson;
import okhttp3.Cache;
import java.io.File;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.Date;
import java.util.HashMap;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

public class TNMCacheManager {

    private static final int MAX_MEMORY_CACHE_SIZE = 50 * 1024 * 1024; // 50 MB
    private static final int MAX_DISK_CACHE_SIZE = 100 * 1024 * 1024;  // 100 MB

    private final ConcurrentHashMap<String, CacheEntry> memoryCache = new ConcurrentHashMap<>();
    private int memoryCacheSize = 0;
    private final Cache diskCache;
    private final Gson gson = new Gson();
    private final File cacheDir;

    public TNMCacheManager(Context context) {
        // Setup disk cache
        cacheDir = new File(context.getCacheDir(), "TNMCache");
        if (!cacheDir.exists()) {
            cacheDir.mkdirs();
        }

        diskCache = new Cache(cacheDir, MAX_DISK_CACHE_SIZE);

        Map<String, Object> details = new HashMap<>();
        details.put("diskPath", cacheDir.getAbsolutePath());
        details.put("memoryLimit", "50 MB");
        TNMLogger.info("Cache manager initialized", "Cache", details);
    }

    /**
     * Get OkHttp disk cache
     */
    public Cache getDiskCache() {
        return diskCache;
    }

    /**
     * Get cached response
     */
    public CacheEntry getCachedResponse(String key, Long maxAge) {
        // Try memory cache first
        CacheEntry entry = memoryCache.get(key);

        if (entry != null) {
            if (!entry.isExpired(maxAge)) {
                double age = (new Date().getTime() - entry.timestamp.getTime()) / 1000.0;
                TNMLogger.Cache.hit(key, age);
                return entry.sanitized();
            } else {
                // Expired, remove
                memoryCache.remove(key);
                memoryCacheSize -= entry.bodyString.length();
                TNMLogger.debug("Cache entry expired (memory)", "Cache",
                        Map.of("key", key));
            }
        }

        // Try disk cache
        CacheEntry diskEntry = loadFromDisk(key);
        if (diskEntry != null) {
            if (!diskEntry.isExpired(maxAge)) {
                // Store in memory for faster access
                CacheEntry sanitized = diskEntry.sanitized();
                memoryCache.put(key, sanitized);
                memoryCacheSize += sanitized.bodyString.length();
                evictIfNeeded();

                double age = (new Date().getTime() - sanitized.timestamp.getTime()) / 1000.0;
                TNMLogger.Cache.hit(key, age);
                return sanitized;
            } else {
                // Expired, remove
                removeFromDisk(key);
                TNMLogger.debug("Cache entry expired (disk)", "Cache",
                        Map.of("key", key));
            }
        }

        TNMLogger.Cache.miss(key);
        return null;
    }

    /**
     * Cache response
     */
    public void cacheResponse(String key, int statusCode, Map<String, String> headers,
                              String body, String etag) {
        CacheEntry entry = new CacheEntry(statusCode, headers, body, etag, new Date());

        // Store in memory
        memoryCache.put(key, entry);
        memoryCacheSize += body.length();
        evictIfNeeded();

        // Store on disk (async)
        new Thread(() -> saveToDisk(key, entry)).start();

        TNMLogger.Cache.stored(key, body.length());
    }

    /**
     * Generate cache key
     */
    public String generateKey(String url, String method) {
        return sha256(method + "-" + url);
    }

    /**
     * Clear cache for domain
     */
    public void clearCache(String domain) {
        TNMLogger.debug("Clearing cache for domain", "Cache",
                Map.of("domain", domain));

        // Clear memory
        memoryCache.clear();
        memoryCacheSize = 0;

        // Clear disk (matching domain)
        int clearedCount = 0;
        File[] files = cacheDir.listFiles();
        if (files != null) {
            for (File file : files) {
                if (file.getName().contains(sanitizeKey(domain))) {
                    file.delete();
                    clearedCount++;
                }
            }
        }

        TNMLogger.Cache.cleared(domain);
    }

    /**
     * Clear all cache
     */
    public void clearAllCache() {
        TNMLogger.debug("Clearing all cache", "Cache");

        memoryCache.clear();
        memoryCacheSize = 0;

        int clearedCount = 0;
        File[] files = cacheDir.listFiles();
        if (files != null) {
            for (File file : files) {
                file.delete();
                clearedCount++;
            }
        }

        TNMLogger.Cache.cleared(null);
    }

    // Private methods

    private CacheEntry loadFromDisk(String key) {
        try {
            File file = new File(cacheDir, sanitizeKey(key));
            if (!file.exists()) return null;

            java.io.FileReader reader = new java.io.FileReader(file);
            CacheEntry entry = gson.fromJson(reader, CacheEntry.class);
            reader.close();
            return entry;
        } catch (Exception e) {
            return null;
        }
    }

    private void saveToDisk(String key, CacheEntry entry) {
        try {
            File file = new File(cacheDir, sanitizeKey(key));
            java.io.FileWriter writer = new java.io.FileWriter(file);
            gson.toJson(entry, writer);
            writer.close();
        } catch (Exception e) {
            TNMLogger.error("Failed to save cache to disk", "Cache", e);
        }
    }

    private void removeFromDisk(String key) {
        File file = new File(cacheDir, sanitizeKey(key));
        file.delete();
    }

    private String sanitizeKey(String key) {
        return key.replaceAll("[/:\\?]", "-");
    }

    private void evictIfNeeded() {
        // Simple LRU-like eviction when over limit
        if (memoryCacheSize > MAX_MEMORY_CACHE_SIZE) {
            // Remove oldest entries
            int removed = 0;
            for (Map.Entry<String, CacheEntry> entry : memoryCache.entrySet()) {
                memoryCache.remove(entry.getKey());
                memoryCacheSize -= entry.getValue().bodyString.length();
                removed++;

                if (memoryCacheSize <= MAX_MEMORY_CACHE_SIZE / 2) {
                    break;
                }
            }

            TNMLogger.debug("Cache evicted by size", "Cache",
                    Map.of("removed", removed, "newSize", memoryCacheSize + " bytes"));
        }
    }

    private String sha256(String input) {
        try {
            MessageDigest digest = MessageDigest.getInstance("SHA-256");
            byte[] hash = digest.digest(input.getBytes(StandardCharsets.UTF_8));
            StringBuilder hexString = new StringBuilder();
            for (byte b : hash) {
                String hex = Integer.toHexString(0xff & b);
                if (hex.length() == 1) hexString.append('0');
                hexString.append(hex);
            }
            return hexString.toString();
        } catch (Exception e) {
            return input;
        }
    }

    /**
     * Cache Entry class
     */
    public static class CacheEntry {
        public int statusCode;
        public Map<String, String> headers;
        public String bodyString;
        public String etag;
        public Date timestamp;

        public CacheEntry(int statusCode, Map<String, String> headers, String bodyString,
                          String etag, Date timestamp) {
            this.statusCode = statusCode;
            this.headers = headers;
            this.bodyString = bodyString;
            this.etag = etag;
            this.timestamp = timestamp;
        }

        public boolean isExpired(Long maxAge) {
            if (maxAge == null) return false;

            long age = (new Date().getTime() - timestamp.getTime()) / 1000;
            return age > maxAge;
        }

        public CacheEntry sanitized() {
            // Create new instance with copied data
            Map<String, String> newHeaders = new HashMap<>(headers);
            String newBody = new String(bodyString);
            String newEtag = etag != null ? new String(etag) : null;

            return new CacheEntry(statusCode, newHeaders, newBody, newEtag, timestamp);
        }
    }
}