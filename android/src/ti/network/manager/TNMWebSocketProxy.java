/**
 * Ti.Network.Manager - WebSocket Proxy
 * JavaScript proxy for WebSocket connections
 * Mirrors iOS TNMWebSocketProxy
 */

package ti.network.manager;

import org.appcelerator.kroll.KrollDict;
import org.appcelerator.kroll.KrollProxy;
import org.appcelerator.kroll.annotations.Kroll;
import java.util.HashMap;
import java.util.Map;
import java.util.UUID;

@Kroll.proxy(creatableInModule = TiNetworkManagerModule.class)
public class TNMWebSocketProxy extends KrollProxy {

    private final TNMWebSocketManager webSocketManager;
    private final String connectionId;
    private final String url;
    private final Map<String, String> headers;
    private boolean isConnected = false;

    public TNMWebSocketProxy(KrollDict params, TNMWebSocketManager webSocketManager) {
        super();

        this.webSocketManager = webSocketManager;
        this.connectionId = UUID.randomUUID().toString();
        this.url = params.optString("url", "");

        if (params.containsKey("headers")) {
            @SuppressWarnings("unchecked")
            Map<String, String> headersMap = (Map<String, String>) params.get("headers");
            this.headers = headersMap;
        } else {
            this.headers = new HashMap<>();
        }

        TNMLogger.debug("WebSocket proxy created", "WebSocket", Map.of(
                "connectionId", connectionId,
                "url", url
        ));
    }

    @Kroll.method
    public void connect() {
        if (isConnected) {
            TNMLogger.warning("WebSocket already connected", "WebSocket",
                    Map.of("connectionId", connectionId));
            return;
        }

        webSocketManager.connect(
                connectionId,
                url,
                headers,
                new TNMWebSocketManager.WebSocketCallback() {
                    @Override
                    public void onOpen() {
                        isConnected = true;
                        KrollDict event = new KrollDict();
                        fireEvent("open", event);
                    }

                    @Override
                    public void onMessage(String data, boolean isBinary) {
                        KrollDict event = new KrollDict();
                        event.put("data", data);

                        if (isBinary) {
                            fireEvent("binary", event);
                        } else {
                            fireEvent("message", event);
                        }
                    }

                    @Override
                    public void onClose(int code, String reason) {
                        isConnected = false;
                        KrollDict event = new KrollDict();
                        event.put("code", code);
                        event.put("reason", reason);
                        fireEvent("close", event);
                    }

                    @Override
                    public void onError(Throwable error) {
                        isConnected = false;
                        KrollDict event = new KrollDict();
                        event.put("error", error.getMessage());
                        fireEvent("error", event);
                    }
                }
        );
    }

    @Kroll.method
    public void send(String message) {
        if (!isConnected) {
            TNMLogger.warning("WebSocket not connected", "WebSocket");
            return;
        }

        boolean success = webSocketManager.sendMessage(connectionId, message);
        if (!success) {
            TNMLogger.error("Failed to send WebSocket message", "WebSocket");
        }
    }

    @Kroll.method
    public void sendBinary(String base64Data) {
        if (!isConnected) {
            TNMLogger.warning("WebSocket not connected", "WebSocket");
            return;
        }

        boolean success = webSocketManager.sendBinary(connectionId, base64Data);
        if (!success) {
            TNMLogger.error("Failed to send WebSocket binary", "WebSocket");
        }
    }

    @Kroll.method
    public void ping() {
        if (!isConnected) {
            TNMLogger.warning("WebSocket not connected", "WebSocket");
            return;
        }

        boolean success = webSocketManager.ping(connectionId);
        if (success) {
            KrollDict event = new KrollDict();
            fireEvent("pong", event);
        }
    }

    @Kroll.method
    public void close(Object[] args) {
        if (!isConnected) return;

        int code = 1000; // Normal closure
        String reason = "";

        if (args != null && args.length > 0 && args[0] instanceof Number) {
            code = ((Number) args[0]).intValue();
        }
        if (args != null && args.length > 1 && args[1] instanceof String) {
            reason = (String) args[1];
        }

        webSocketManager.close(connectionId, code, reason);
        isConnected = false;
    }
}