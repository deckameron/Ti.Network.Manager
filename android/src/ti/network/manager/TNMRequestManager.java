/**
 * Ti.Network.Manager - Request Manager
 * Manages HTTP requests with retry logic and priority queue
 * Uses OkHttp with custom Dispatcher for priority handling
 */

package ti.network.manager;

import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import okhttp3.*;
import java.io.IOException;
import java.util.HashMap;
import java.util.Map;
import java.util.PriorityQueue;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;

public class TNMRequestManager {

    private final OkHttpClient client;
    private final ConcurrentHashMap<String, Call> activeRequests = new ConcurrentHashMap<>();
    private final Handler mainHandler = new Handler(Looper.getMainLooper());

    // Priority queue for requests
    private final PriorityQueue<PriorityRequest> requestQueue = new PriorityQueue<>();
    private final ExecutorService executorService = Executors.newFixedThreadPool(4);
    private int activeCount = 0;
    private final Object queueLock = new Object();

    public TNMRequestManager(OkHttpClient.Builder clientBuilder) {
        // Build client with custom dispatcher
        Dispatcher dispatcher = new Dispatcher();
        dispatcher.setMaxRequests(10);
        dispatcher.setMaxRequestsPerHost(5);

        this.client = clientBuilder
                .dispatcher(dispatcher)
                .connectTimeout(30, TimeUnit.SECONDS)
                .readTimeout(30, TimeUnit.SECONDS)
                .writeTimeout(30, TimeUnit.SECONDS)
                .build();

        TNMLogger.info("Request manager initialized", "Request");
    }

    /**
     * Execute HTTP request with retry logic and priority
     */
    public void executeRequest(
            String requestId,
            String url,
            String method,
            Map<String, String> headers,
            String body,
            float priority,
            RetryConfiguration retryConfig,
            RequestCallback callback
    ) {
        TNMLogger.Request.started(requestId, url, method);

        // Build request
        Request.Builder requestBuilder = new Request.Builder().url(url);

        // Add headers
        if (headers != null) {
            for (Map.Entry<String, String> entry : headers.entrySet()) {
                requestBuilder.header(entry.getKey(), entry.getValue());
            }
        }

        // Add body
        RequestBody requestBody = null;
        if (body != null && !method.equals("GET")) {
            requestBody = RequestBody.create(body, MediaType.get("application/json; charset=utf-8"));
        }

        // Set method
        switch (method) {
            case "GET":
                requestBuilder.get();
                break;
            case "POST":
                requestBuilder.post(requestBody != null ? requestBody :
                        RequestBody.create("", null));
                break;
            case "PUT":
                requestBuilder.put(requestBody != null ? requestBody :
                        RequestBody.create("", null));
                break;
            case "DELETE":
                requestBuilder.delete(requestBody);
                break;
            case "PATCH":
                requestBuilder.patch(requestBody != null ? requestBody :
                        RequestBody.create("", null));
                break;
            case "HEAD":
                requestBuilder.head();
                break;
            default:
                requestBuilder.method(method, requestBody);
        }

        Request request = requestBuilder.build();

        // Create priority request
        PriorityRequest priorityRequest = new PriorityRequest(
                requestId,
                request,
                priority,
                retryConfig,
                0,
                callback
        );

        // Add to priority queue
        synchronized (queueLock) {
            requestQueue.offer(priorityRequest);
            processQueue();
        }
    }

    /**
     * Process priority queue
     */
    private void processQueue() {
        synchronized (queueLock) {
            int MAX_CONCURRENT = 4;
            while (activeCount < MAX_CONCURRENT && !requestQueue.isEmpty()) {
                PriorityRequest priorityRequest = requestQueue.poll();
                if (priorityRequest != null) {
                    activeCount++;
                    executorService.submit(() -> {
                        executeWithRetry(priorityRequest);
                    });
                }
            }
        }
    }

    /**
     * Execute request with retry logic
     */
    private void executeWithRetry(PriorityRequest priorityRequest) {
        String requestId = priorityRequest.requestId;
        Request request = priorityRequest.request;
        RetryConfiguration retryConfig = priorityRequest.retryConfig;
        int currentAttempt = priorityRequest.currentAttempt;
        RequestCallback callback = priorityRequest.callback;

        Call call = client.newCall(request);
        activeRequests.put(requestId, call);

        try {
            Response response = call.execute();

            activeRequests.remove(requestId);

            // Read body
            String bodyString = null;
            if (response.body() != null) {
                bodyString = response.body().string();
            }

            // Convert headers
            Map<String, String> responseHeaders = new HashMap<>();
            for (String name : response.headers().names()) {
                responseHeaders.put(name, response.header(name));
            }

            final int statusCode = response.code();
            final String finalBody = bodyString;
            final Map<String, String> finalHeaders = responseHeaders;

            // Check if should retry
            boolean shouldRetry = false;
            if (retryConfig != null && currentAttempt < retryConfig.maxRetries) {
                if (retryConfig.retryOn != null) {
                    for (int code : retryConfig.retryOn) {
                        if (code == statusCode) {
                            shouldRetry = true;
                            break;
                        }
                    }
                }
            }

            if (shouldRetry) {
                // Calculate delay
                long delay = calculateDelay(retryConfig, currentAttempt);

                TNMLogger.warning("Request will retry", "Request", Map.of(
                        "requestId", requestId,
                        "attempt", currentAttempt + 1,
                        "delay", delay + "ms"
                ));

                // Notify will retry
                mainHandler.post(() -> {
                    callback.onError(new Exception("HTTP " + statusCode), true);
                });

                // Schedule retry with higher priority
                mainHandler.postDelayed(() -> {
                    synchronized (queueLock) {
                        activeCount--;

                        PriorityRequest retryRequest = new PriorityRequest(
                                requestId,
                                request,
                                priorityRequest.priority + 0.1f, // Boost priority on retry
                                retryConfig,
                                currentAttempt + 1,
                                callback
                        );

                        requestQueue.offer(retryRequest);
                        processQueue();
                    }
                }, delay);
            } else {
                // Success or no more retries
                TNMLogger.Request.completed(requestId, statusCode);

                synchronized (queueLock) {
                    activeCount--;
                    processQueue();
                }

                mainHandler.post(() -> {
                    callback.onComplete(statusCode, finalHeaders, finalBody);
                });
            }

        } catch (IOException e) {
            activeRequests.remove(requestId);

            // Check if should retry
            boolean shouldRetry = false;
            if (retryConfig != null && currentAttempt < retryConfig.maxRetries) {
                shouldRetry = true;
            }

            if (shouldRetry) {
                // Calculate delay
                long delay = calculateDelay(retryConfig, currentAttempt);

                TNMLogger.warning("Request failed, will retry", "Request", Map.of(
                        "requestId", requestId,
                        "attempt", currentAttempt + 1,
                        "delay", delay + "ms"
                ));

                // Notify will retry
                mainHandler.post(() -> {
                    callback.onError(e, true);
                });

                // Schedule retry
                mainHandler.postDelayed(() -> {
                    synchronized (queueLock) {
                        activeCount--;

                        PriorityRequest retryRequest = new PriorityRequest(
                                requestId,
                                request,
                                priorityRequest.priority + 0.1f, // Boost priority on retry
                                retryConfig,
                                currentAttempt + 1,
                                callback
                        );

                        requestQueue.offer(retryRequest);
                        processQueue();
                    }
                }, delay);
            } else {
                // Failed
                TNMLogger.Request.failed(requestId, e);

                synchronized (queueLock) {
                    activeCount--;
                    processQueue();
                }

                mainHandler.post(() -> {
                    callback.onError(e, false);
                });
            }
        }
    }

    private long calculateDelay(RetryConfiguration config, int attempt) {
        long baseDelay = (long) (config.baseDelay * 1000); // Convert to ms

        if ("exponential".equals(config.backoff)) {
            return baseDelay * (long) Math.pow(2, attempt);
        } else {
            // Linear
            return baseDelay * (attempt + 1);
        }
    }

    /**
     * Cancel request
     */
    public void cancelRequest(String requestId) {
        Call call = activeRequests.get(requestId);
        if (call != null) {
            call.cancel();
            activeRequests.remove(requestId);
            TNMLogger.Request.cancelled(requestId);
        }

        // Remove from queue if pending
        synchronized (queueLock) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                requestQueue.removeIf(pr -> pr.requestId.equals(requestId));
            }
        }
    }

    /**
     * Priority Request wrapper
     */
    private static class PriorityRequest implements Comparable<PriorityRequest> {
        String requestId;
        Request request;
        float priority;
        RetryConfiguration retryConfig;
        int currentAttempt;
        RequestCallback callback;
        long timestamp;

        PriorityRequest(String requestId, Request request, float priority,
                        RetryConfiguration retryConfig, int currentAttempt,
                        RequestCallback callback) {
            this.requestId = requestId;
            this.request = request;
            this.priority = priority;
            this.retryConfig = retryConfig;
            this.currentAttempt = currentAttempt;
            this.callback = callback;
            this.timestamp = System.currentTimeMillis();
        }

        @Override
        public int compareTo(PriorityRequest other) {
            // Higher priority first (reverse order)
            int priorityCompare = Float.compare(other.priority, this.priority);
            if (priorityCompare != 0) {
                return priorityCompare;
            }
            // If same priority, FIFO
            return Long.compare(this.timestamp, other.timestamp);
        }
    }

    /**
     * Retry configuration
     */
    public static class RetryConfiguration {
        public int maxRetries = 0;
        public String backoff = "exponential";
        public double baseDelay = 1.0;
        public int[] retryOn;

        public RetryConfiguration(Map<String, Object> params) {
            if (params.containsKey("max")) {
                maxRetries = ((Number) params.get("max")).intValue();
            }
            if (params.containsKey("backoff")) {
                backoff = (String) params.get("backoff");
            }
            if (params.containsKey("baseDelay")) {
                baseDelay = ((Number) params.get("baseDelay")).doubleValue();
            }
            if (params.containsKey("retryOn")) {
                Object[] retryArray = (Object[]) params.get("retryOn");
                retryOn = new int[retryArray.length];
                for (int i = 0; i < retryArray.length; i++) {
                    retryOn[i] = ((Number) retryArray[i]).intValue();
                }
            }
        }
    }

    /**
     * Request callback interface
     */
    public interface RequestCallback {
        void onProgress(long sent, long total);
        void onComplete(int statusCode, Map<String, String> headers, String body);
        void onError(Exception error, boolean willRetry);
    }
}