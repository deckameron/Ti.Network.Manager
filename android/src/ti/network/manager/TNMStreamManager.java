/**
 * Ti.Network.Manager - Stream Manager
 * Manages Server-Sent Events (SSE) streaming
 * Uses OkHttp SSE library
 */

package ti.network.manager;

import android.os.Handler;
import android.os.Looper;
import okhttp3.*;
import okhttp3.sse.EventSource;
import okhttp3.sse.EventSourceListener;
import okhttp3.sse.EventSources;
import org.jetbrains.annotations.NotNull;
import org.jetbrains.annotations.Nullable;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.TimeUnit;

public class TNMStreamManager {

    private final OkHttpClient client;
    private final ConcurrentHashMap<String, EventSource> activeStreams = new ConcurrentHashMap<>();
    private final Handler mainHandler = new Handler(Looper.getMainLooper());

    public TNMStreamManager(OkHttpClient.Builder clientBuilder) {
        this.client = clientBuilder
                .readTimeout(0, TimeUnit.SECONDS) // No timeout for SSE
                .build();

        TNMLogger.info("Stream manager initialized", "Stream");
    }

    /**
     * Start SSE stream
     */
    public void startStream(
            String streamId,
            String url,
            String method,
            Map<String, String> headers,
            String body,
            float priority,
            StreamCallback callback
    ) {
        TNMLogger.info("Starting SSE stream", "Stream", Map.of(
                "streamId", streamId,
                "url", url,
                "method", method
        ));

        // Build request
        Request.Builder requestBuilder = new Request.Builder().url(url);

        // Add headers
        if (headers != null) {
            for (Map.Entry<String, String> entry : headers.entrySet()) {
                requestBuilder.header(entry.getKey(), entry.getValue());
            }
        }

        // For POST requests with body
        if ("POST".equals(method) && body != null) {
            RequestBody requestBody = RequestBody.create(
                    body,
                    MediaType.get("application/json; charset=utf-8")
            );
            requestBuilder.post(requestBody);
        }

        Request request = requestBuilder.build();

        // Create EventSource listener
        EventSourceListener listener = new EventSourceListener() {
            @Override
            public void onOpen(@NotNull EventSource eventSource, @NotNull Response response) {
                TNMLogger.success("Stream opened", "Stream", Map.of(
                        "streamId", streamId
                ));

                mainHandler.post(() -> callback.onOpen());
            }

            @Override
            public void onEvent(@NotNull EventSource eventSource,
                                @Nullable String id,
                                @Nullable String type,
                                @NotNull String data) {
                TNMLogger.debug("Stream chunk received", "Stream", Map.of(
                        "streamId", streamId,
                        "event", type != null ? type : "message",
                        "dataLength", data.length()
                ));

                final String eventType = type != null ? type : "message";
                mainHandler.post(() -> callback.onChunk(data, eventType));
            }

            @Override
            public void onClosed(@NotNull EventSource eventSource) {
                activeStreams.remove(streamId);

                TNMLogger.info("Stream closed", "Stream", Map.of(
                        "streamId", streamId
                ));

                mainHandler.post(() -> callback.onClose());
            }

            @Override
            public void onFailure(@NotNull EventSource eventSource,
                                  @Nullable Throwable t,
                                  @Nullable Response response) {
                activeStreams.remove(streamId);

                TNMLogger.error("Stream error", "Stream", t);

                mainHandler.post(() -> callback.onError(t != null ? t : new Exception("Unknown error")));
            }
        };

        // Create EventSource
        EventSource.Factory factory = EventSources.createFactory(client);
        EventSource eventSource = factory.newEventSource(request, listener);

        activeStreams.put(streamId, eventSource);
    }

    /**
     * Cancel stream
     */
    public void cancelStream(String streamId) {
        EventSource eventSource = activeStreams.get(streamId);
        if (eventSource != null) {
            eventSource.cancel();
            activeStreams.remove(streamId);

            TNMLogger.info("Stream cancelled", "Stream", Map.of(
                    "streamId", streamId
            ));
        }
    }

    /**
     * Stream callback interface
     */
    public interface StreamCallback {
        void onOpen();
        void onChunk(String data, String eventType);
        void onClose();
        void onError(Throwable error);
    }
}