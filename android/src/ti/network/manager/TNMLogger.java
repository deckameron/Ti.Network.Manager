/**
 * Ti.Network.Manager - Logger
 * Structured logging system with feature-specific loggers
 * Android version - mirrors iOS TNMLogger
 */

package ti.network.manager;

import android.util.Log;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.Locale;
import java.util.Map;

public class TNMLogger {

    private static final String TAG = "TiNetworkManager";
    private static boolean isEnabled = true;
    private static SimpleDateFormat dateFormatter = new SimpleDateFormat("HH:mm:ss.SSS", Locale.US);

    // Log Levels
    public enum LogLevel {
        INFO("[INFO]"),
        SUCCESS("[SUCCESS]"),
        WARNING("[WARN]"),
        ERROR("[ERROR]"),
        DEBUG("[DEBUG]");

        private final String prefix;

        LogLevel(String prefix) {
            this.prefix = prefix;
        }

        public String getPrefix() {
            return prefix;
        }
    }

    // Enable/Disable logging
    public static void setEnabled(boolean enabled) {
        isEnabled = enabled;
    }

    // Main log method
    private static void log(String message, LogLevel level, String feature, Map<String, Object> details, Throwable error) {
        if (!isEnabled) return;

        String timestamp = dateFormatter.format(new Date());
        String featureStr = feature != null ? "[" + feature + "] " : "";
        String logMessage = timestamp + " " + level.getPrefix() + " " + featureStr + message;

        // Add details
        if (details != null && !details.isEmpty()) {
            StringBuilder detailsStr = new StringBuilder();
            for (Map.Entry<String, Object> entry : details.entrySet()) {
                detailsStr.append("\n  | ").append(entry.getKey()).append(": ").append(entry.getValue());
            }
            logMessage += detailsStr.toString();
        }

        // Add error
        if (error != null) {
            logMessage += "\n  | Error: " + error.getMessage();
        }

        // Log based on level
        switch (level) {
            case INFO:
            case SUCCESS:
                Log.i(TAG, logMessage);
                break;
            case WARNING:
                Log.w(TAG, logMessage);
                break;
            case ERROR:
                Log.e(TAG, logMessage, error);
                break;
            case DEBUG:
                Log.d(TAG, logMessage);
                break;
        }
    }

    // Public log methods
    public static void info(String message) {
        log(message, LogLevel.INFO, null, null, null);
    }

    public static void info(String message, String feature) {
        log(message, LogLevel.INFO, feature, null, null);
    }

    public static void info(String message, String feature, Map<String, Object> details) {
        log(message, LogLevel.INFO, feature, details, null);
    }

    public static void success(String message, String feature) {
        log(message, LogLevel.SUCCESS, feature, null, null);
    }

    public static void success(String message, String feature, Map<String, Object> details) {
        log(message, LogLevel.SUCCESS, feature, details, null);
    }

    public static void warning(String message, String feature) {
        log(message, LogLevel.WARNING, feature, null, null);
    }

    public static void warning(String message, String feature, Map<String, Object> details) {
        log(message, LogLevel.WARNING, feature, details, null);
    }

    public static void error(String message, String feature) {
        log(message, LogLevel.ERROR, feature, null, null);
    }

    public static void error(String message, String feature, Throwable error) {
        log(message, LogLevel.ERROR, feature, null, error);
    }

    public static void error(String message, String feature, Map<String, Object> details) {
        log(message, LogLevel.ERROR, feature, details, null);
    }

    public static void debug(String message, String feature) {
        log(message, LogLevel.DEBUG, feature, null, null);
    }

    public static void debug(String message, String feature, Map<String, Object> details) {
        log(message, LogLevel.DEBUG, feature, details, null);
    }

    // Feature-specific loggers (mirrors iOS)
    public static class Cache {
        public static void hit(String key, double age) {
            Map<String, Object> details = new java.util.HashMap<>();
            details.put("key", key);
            details.put("age", String.format(Locale.US, "%.1f seconds", age));
            debug("Cache hit", "Cache", details);
        }

        public static void miss(String key) {
            Map<String, Object> details = new java.util.HashMap<>();
            details.put("key", key);
            debug("Cache miss", "Cache", details);
        }

        public static void stored(String key, int size) {
            Map<String, Object> details = new java.util.HashMap<>();
            details.put("key", key);
            details.put("size", size + " bytes");
            debug("Cache stored", "Cache", details);
        }

        public static void cleared(String domain) {
            if (domain != null) {
                Map<String, Object> details = new java.util.HashMap<>();
                details.put("domain", domain);
                info("Cache cleared for domain", "Cache", details);
            } else {
                info("All cache cleared", "Cache");
            }
        }
    }

    public static class Request {
        public static void started(String requestId, String url, String method) {
            Map<String, Object> details = new java.util.HashMap<>();
            details.put("requestId", requestId);
            details.put("url", url);
            details.put("method", method);
            info("Request started", "Request", details);
        }

        public static void completed(String requestId, int statusCode) {
            Map<String, Object> details = new java.util.HashMap<>();
            details.put("requestId", requestId);
            details.put("statusCode", statusCode);
            success("Request completed", "Request", details);
        }

        public static void cancelled(String requestId) {
            Map<String, Object> details = new java.util.HashMap<>();
            details.put("requestId", requestId);
            warning("Request cancelled", "Request", details);
        }

        public static void failed(String requestId, Throwable error) {
            Map<String, Object> details = new java.util.HashMap<>();
            details.put("requestId", requestId);
            error("Request failed", "Request", error);
        }
    }

    public static class CertificatePinning {
        public static void configured(String domain, int hashCount) {
            Map<String, Object> details = new java.util.HashMap<>();
            details.put("domain", domain);
            details.put("hashes", hashCount);
            info("Certificate pinning configured", "CertificatePinning", details);
        }

        public static void validated(String domain) {
            Map<String, Object> details = new java.util.HashMap<>();
            details.put("domain", domain);
            success("Certificate validated", "CertificatePinning", details);
        }

        public static void failed(String domain, Throwable error) {
            Map<String, Object> details = new java.util.HashMap<>();
            details.put("domain", domain);
            error("Certificate validation failed", "CertificatePinning", error);
        }
    }

    public static class Interceptor {
        public static void requestInterceptorAdded(int count) {
            Map<String, Object> details = new java.util.HashMap<>();
            details.put("totalCount", count);
            info("Request interceptor added", "Interceptor", details);
        }

        public static void responseInterceptorAdded(int count) {
            Map<String, Object> details = new java.util.HashMap<>();
            details.put("totalCount", count);
            info("Response interceptor added", "Interceptor", details);
        }
    }
}