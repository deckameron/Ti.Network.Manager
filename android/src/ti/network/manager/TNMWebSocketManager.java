/**
 * Ti.Network.Manager - WebSocket Manager
 * Manages WebSocket connections
 * Uses OkHttp's WebSocket support
 */

package ti.network.manager;

import android.os.Handler;
import android.os.Looper;

import androidx.annotation.NonNull;

import okhttp3.*;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

public class TNMWebSocketManager {

    private final OkHttpClient client;
    private final ConcurrentHashMap<String, WebSocket> activeConnections = new ConcurrentHashMap<>();
    private final Handler mainHandler = new Handler(Looper.getMainLooper());

    public TNMWebSocketManager(OkHttpClient.Builder clientBuilder) {
        this.client = clientBuilder.build();
        TNMLogger.info("WebSocket manager initialized", "WebSocket");
    }

    /**
     * Create WebSocket connection
     */
    public void connect(
            String connectionId,
            String url,
            Map<String, String> headers,
            WebSocketCallback callback
    ) {
        TNMLogger.info("Creating WebSocket connection", "WebSocket", Map.of(
                "connectionId", connectionId,
                "url", url
        ));

        // Build request
        Request.Builder requestBuilder = new Request.Builder().url(url);

        if (headers != null) {
            for (Map.Entry<String, String> entry : headers.entrySet()) {
                requestBuilder.header(entry.getKey(), entry.getValue());
            }
        }

        Request request = requestBuilder.build();

        // Create WebSocket listener
        WebSocketListener listener = new WebSocketListener() {
            @Override
            public void onOpen(@NonNull WebSocket webSocket, @NonNull Response response) {
                TNMLogger.success("WebSocket opened", "WebSocket", Map.of(
                        "connectionId", connectionId
                ));

                mainHandler.post(callback::onOpen);
            }

            @Override
            public void onMessage(@NonNull WebSocket webSocket, String text) {
                TNMLogger.debug("WebSocket message received", "WebSocket", Map.of(
                        "connectionId", connectionId,
                        "length", text.length()
                ));

                mainHandler.post(() -> callback.onMessage(text, false));
            }

            @Override
            public void onMessage(@NonNull WebSocket webSocket, okio.ByteString bytes) {
                TNMLogger.debug("WebSocket binary message received", "WebSocket", Map.of(
                        "connectionId", connectionId,
                        "size", bytes.size()
                ));

                mainHandler.post(() -> callback.onMessage(bytes.base64(), true));
            }

            @Override
            public void onClosing(WebSocket webSocket, int code, @NonNull String reason) {
                TNMLogger.info("WebSocket closing", "WebSocket", Map.of(
                        "connectionId", connectionId,
                        "code", code,
                        "reason", reason
                ));

                webSocket.close(code, reason);
            }

            @Override
            public void onClosed(@NonNull WebSocket webSocket, int code, @NonNull String reason) {
                activeConnections.remove(connectionId);

                TNMLogger.info("WebSocket closed", "WebSocket", Map.of(
                        "connectionId", connectionId,
                        "code", code
                ));

                mainHandler.post(() -> callback.onClose(code, reason));
            }

            @Override
            public void onFailure(@NonNull WebSocket webSocket, @NonNull Throwable t, Response response) {
                activeConnections.remove(connectionId);

                TNMLogger.error("WebSocket error", "WebSocket", t);

                mainHandler.post(() -> callback.onError(t));
            }
        };

        // Create WebSocket
        WebSocket webSocket = client.newWebSocket(request, listener);
        activeConnections.put(connectionId, webSocket);
    }

    /**
     * Send text message
     */
    public boolean sendMessage(String connectionId, String message) {
        WebSocket webSocket = activeConnections.get(connectionId);
        if (webSocket != null) {
            return webSocket.send(message);
        }
        return false;
    }

    /**
     * Send binary message
     */
    public boolean sendBinary(String connectionId, String base64Data) {
        WebSocket webSocket = activeConnections.get(connectionId);
        if (webSocket != null) {
            okio.ByteString bytes = okio.ByteString.decodeBase64(base64Data);
            if (bytes != null) {
                return webSocket.send(bytes);
            }
        }
        return false;
    }

    /**
     * Send ping
     */
    public boolean ping(String connectionId) {
        WebSocket webSocket = activeConnections.get(connectionId);
        if (webSocket != null) {
            return webSocket.send(okio.ByteString.EMPTY);
        }
        return false;
    }

    /**
     * Close connection
     */
    public void close(String connectionId, int code, String reason) {
        WebSocket webSocket = activeConnections.get(connectionId);
        if (webSocket != null) {
            webSocket.close(code, reason);
            activeConnections.remove(connectionId);

            TNMLogger.info("WebSocket connection closed", "WebSocket", Map.of(
                    "connectionId", connectionId
            ));
        }
    }

    /**
     * WebSocket callback interface
     */
    public interface WebSocketCallback {
        void onOpen();
        void onMessage(String data, boolean isBinary);
        void onClose(int code, String reason);
        void onError(Throwable error);
    }
}