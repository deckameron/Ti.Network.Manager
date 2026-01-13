/**
 * Ti.Network.Manager - Stream Proxy
 * JavaScript proxy for SSE streaming
 * Mirrors iOS TiHTTPStreamProxy
 */

package ti.network.manager;

import org.appcelerator.kroll.KrollDict;
import org.appcelerator.kroll.KrollProxy;
import org.appcelerator.kroll.annotations.Kroll;
import java.util.HashMap;
import java.util.Map;
import java.util.UUID;

@Kroll.proxy(creatableInModule = TiNetworkManagerModule.class)
public class TiHTTPStreamProxy extends KrollProxy {

    private final TNMStreamManager streamManager;
    private final String streamId;
    private final String url;
    private final String method;
    private final Map<String, String> headers;
    private final String body;
    private final String priority;
    private boolean isActive = false;
    private int chunkCount = 0;
    private long totalBytes = 0;

    public TiHTTPStreamProxy(KrollDict params, TNMStreamManager streamManager) {
        super();

        this.streamManager = streamManager;
        this.streamId = UUID.randomUUID().toString();
        this.url = params.optString("url", "");
        this.method = params.optString("method", "GET").toUpperCase();
        this.priority = params.optString("priority", "normal");
        this.body = params.optString("body", null);

        // Headers
        if (params.containsKey("headers")) {
            @SuppressWarnings("unchecked")
            Map<String, String> headersMap = (Map<String, String>) params.get("headers");
            this.headers = headersMap;
        } else {
            this.headers = new HashMap<>();
        }

        Map<String, Object> details = new HashMap<>();
        details.put("streamId", streamId);
        details.put("url", url);
        details.put("method", method);
        TNMLogger.debug("Stream proxy created", "Stream", details);
    }

    @Kroll.method
    public void start() {
        if (isActive) {
            TNMLogger.warning("Stream already active", "Stream",
                    Map.of("streamId", streamId));
            return;
        }

        isActive = true;
        chunkCount = 0;
        totalBytes = 0;

        // Convert priority
        float urlPriority = 0.5f; // Normal
        if ("high".equals(priority)) {
            urlPriority = 0.75f;
        } else if ("low".equals(priority)) {
            urlPriority = 0.25f;
        }

        streamManager.startStream(
                streamId,
                url,
                method,
                headers,
                body,
                urlPriority,
                new TNMStreamManager.StreamCallback() {
                    @Override
                    public void onOpen() {
                        handleOpen();
                    }

                    @Override
                    public void onChunk(String data, String eventType) {
                        handleChunk(data, eventType);
                    }

                    @Override
                    public void onClose() {
                        handleClose();
                    }

                    @Override
                    public void onError(Throwable error) {
                        handleError(error);
                    }
                }
        );
    }

    @Kroll.method
    public void cancel() {
        if (!isActive) return;

        streamManager.cancelStream(streamId);
        isActive = false;

        KrollDict event = new KrollDict();
        fireEvent("cancelled", event);
    }

    private void handleOpen() {
        KrollDict event = new KrollDict();
        event.put("streamId", streamId);
        fireEvent("open", event);
    }

    private void handleChunk(String data, String eventType) {
        if (!isActive) return;

        chunkCount++;
        totalBytes += data.length();

        TNMLogger.debug("Stream chunk", "Stream", Map.of(
                "streamId", streamId,
                "chunkNumber", chunkCount,
                "size", data.length()
        ));

        KrollDict event = new KrollDict();
        event.put("streamId", streamId);
        event.put("data", data);
        event.put("eventType", eventType != null ? eventType : "message");
        event.put("chunkNumber", chunkCount);
        event.put("totalBytes", totalBytes);

        fireEvent("chunk", event);
    }

    private void handleClose() {
        isActive = false;

        TNMLogger.info("Stream completed", "Stream", Map.of(
                "streamId", streamId,
                "totalChunks", chunkCount,
                "totalBytes", totalBytes
        ));

        KrollDict event = new KrollDict();
        event.put("streamId", streamId);
        event.put("totalChunks", chunkCount);
        event.put("totalBytes", totalBytes);

        fireEvent("complete", event);
    }

    private void handleError(Throwable error) {
        if (!isActive) return;

        isActive = false;

        KrollDict event = new KrollDict();
        event.put("streamId", streamId);
        event.put("error", error.getMessage());

        fireEvent("error", event);
    }
}