/**
 * Ti.Network.Manager - Request Proxy
 * JavaScript proxy for HTTP requests
 * Mirrors iOS TNMRequestProxy
 */

package ti.network.manager;

import android.os.Handler;
import android.os.Looper;
import org.appcelerator.kroll.KrollDict;
import org.appcelerator.kroll.KrollProxy;
import org.appcelerator.kroll.annotations.Kroll;
import java.util.HashMap;
import java.util.Map;
import java.util.Objects;
import java.util.UUID;

@Kroll.proxy(creatableInModule = TiNetworkManagerModule.class)
public class TNMRequestProxy extends KrollProxy {

    private final TNMRequestManager requestManager;
    private final TNMCacheManager cacheManager;

    private final String requestId;
    private final String url;
    private final String method;
    private final Map<String, String> headers;
    private final String body;
    private final String priority;
    private String cachePolicy;
    private Long cacheTTL;
    private TNMRequestManager.RetryConfiguration retryConfig;

    private boolean isActive = false;
    private long startTime;

    private final Handler mainHandler = new Handler(Looper.getMainLooper());

    public TNMRequestProxy(
            KrollDict params,
            TNMRequestManager requestManager,
            TNMCacheManager cacheManager
    ) {
        super();

        this.requestManager = requestManager;
        this.cacheManager = cacheManager;

        this.requestId = UUID.randomUUID().toString();
        this.url = params.optString("url", "");
        this.method = params.optString("method", "GET").toUpperCase();
        this.priority = params.optString("priority", "normal");

        // Headers
        if (params.containsKey("headers")) {
            @SuppressWarnings("unchecked")
            Map<String, String> headersMap = (Map<String, String>) params.get("headers");
            this.headers = headersMap;
        } else {
            this.headers = new HashMap<>();
        }

        // Body
        this.body = params.optString("body", null);

        // Cache configuration
        if (params.containsKey("cache")) {
            @SuppressWarnings("unchecked")
            Map<String, Object> cacheConfig = (Map<String, Object>) params.get("cache");
            assert cacheConfig != null;
            this.cachePolicy = (String) cacheConfig.get("policy");
            if (cacheConfig.containsKey("ttl")) {
                this.cacheTTL = ((Number) Objects.requireNonNull(cacheConfig.get("ttl"))).longValue();
            }
        }

        // Retry configuration
        if (params.containsKey("retry")) {
            @SuppressWarnings("unchecked")
            Map<String, Object> retryParams = (Map<String, Object>) params.get("retry");
            assert retryParams != null;
            this.retryConfig = new TNMRequestManager.RetryConfiguration(retryParams);
        }

        Map<String, Object> details = new HashMap<>();
        details.put("requestId", requestId);
        details.put("url", url);
        details.put("method", method);
        details.put("priority", priority);
        details.put("cachePolicy", cachePolicy != null ? cachePolicy : "none");
        TNMLogger.debug("Request proxy created", "Request", details);
    }

    @Kroll.method
    public void send() {
        if (isActive) {
            TNMLogger.warning("Request already active", "Request",
                    Map.of("requestId", requestId));
            return;
        }

        isActive = true;
        startTime = System.currentTimeMillis();

        // Generate cache key
        final String cacheKey = cacheManager.generateKey(url, method);

        // Check cache policy
        if ("cache-first".equals(cachePolicy)) {
            TNMCacheManager.CacheEntry cachedEntry =
                    cacheManager.getCachedResponse(cacheKey, cacheTTL);

            if (cachedEntry != null) {
                // ✅ Return cached response asynchronously (critical for autorelease pool drainage)
                mainHandler.post(() -> {
                    handleCachedResponse(cachedEntry);
                });
                return;
            }
        }

        // Convert priority
        float urlPriority = 0.5f; // Normal
        if ("high".equals(priority)) {
            urlPriority = 0.75f;
        } else if ("low".equals(priority)) {
            urlPriority = 0.25f;
        }

        // Execute request (interceptors run automatically via OkHttp chain)
        requestManager.executeRequest(
                requestId,
                url,
                method,
                headers,
                body,
                urlPriority,
                retryConfig,
                new TNMRequestManager.RequestCallback() {
                    @Override
                    public void onProgress(long sent, long total) {
                        handleProgress(sent, total);
                    }

                    @Override
                    public void onComplete(int statusCode, Map<String, String> headers, String body) {
                        handleComplete(statusCode, headers, body, cacheKey);
                    }

                    @Override
                    public void onError(Exception error, boolean willRetry) {
                        handleError(error, willRetry);
                    }
                }
        );
    }

    @Kroll.method
    public void cancel() {
        if (!isActive) return;

        requestManager.cancelRequest(requestId);
        isActive = false;

        KrollDict event = new KrollDict();
        fireEvent("cancelled", event);
    }

    private void handleProgress(long received, long total) {
        if (!isActive) return;

        double progress = total > 0 ? (double) received / total : 0.0;

        KrollDict event = new KrollDict();
        event.put("received", received);
        event.put("total", total);
        event.put("progress", progress);

        fireEvent("progress", event);
    }

    private void handleComplete(int statusCode, Map<String, String> headers,
                                String body, String cacheKey) {
        if (!isActive) return;

        isActive = false;

        // Cache if policy allows
        if (cachePolicy != null && !"network-only".equals(cachePolicy) && statusCode == 200) {
            String etag = headers.get("ETag");
            cacheManager.cacheResponse(cacheKey, statusCode, headers, body, etag);
        }

        long duration = System.currentTimeMillis() - startTime;

        KrollDict event = new KrollDict();
        event.put("statusCode", statusCode);
        event.put("headers", headers);
        event.put("body", body != null ? body : "");
        event.put("success", statusCode >= 200 && statusCode < 300);
        event.put("duration", duration / 1000.0);
        event.put("cached", false);

        fireEvent("complete", event);
    }

    private void handleCachedResponse(TNMCacheManager.CacheEntry entry) {
        isActive = false;

        TNMLogger.debug("Returning cached response", "Request", Map.of(
                "requestId", requestId,
                "statusCode", entry.statusCode
        ));

        KrollDict event = new KrollDict();
        event.put("statusCode", entry.statusCode);
        event.put("headers", entry.headers);
        event.put("body", entry.bodyString);
        event.put("success", true);
        event.put("cached", true);
        event.put("duration", 0);

        fireEvent("complete", event);
    }

    private void handleError(Exception error, boolean willRetry) {
        if (!willRetry) {
            isActive = false;
        }

        KrollDict event = new KrollDict();
        event.put("error", error.getMessage());
        event.put("willRetry", willRetry);

        fireEvent("error", event);
    }
}