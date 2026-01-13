/**
 * Ti.Network.Manager - Background Transfer Proxy
 * JavaScript proxy for background transfers
 * Mirrors iOS TNMBackgroundTransferProxy
 */

package ti.network.manager;

import org.appcelerator.kroll.KrollDict;
import org.appcelerator.kroll.KrollProxy;
import org.appcelerator.kroll.annotations.Kroll;
import org.appcelerator.titanium.TiApplication;
import java.util.HashMap;
import java.util.Map;
import java.util.UUID;

@Kroll.proxy(creatableInModule = TiNetworkManagerModule.class)
public class TNMBackgroundTransferProxy extends KrollProxy {

    private final TNMBackgroundTransferManager transferManager;
    private final String transferId;
    private final String type; // "download" or "upload"
    private final String url;
    private final String destination; // for download
    private final String filePath; // for upload
    private final Map<String, String> headers;
    private boolean isActive = false;

    public TNMBackgroundTransferProxy(KrollDict params, TNMBackgroundTransferManager transferManager) {
        super();

        this.transferManager = transferManager;
        this.transferId = UUID.randomUUID().toString();
        this.type = params.optString("type", "download");
        this.url = params.optString("url", "");
        this.destination = params.optString("destination", null);
        this.filePath = params.optString("file", null);

        // Headers
        if (params.containsKey("headers")) {
            @SuppressWarnings("unchecked")
            Map<String, String> headersMap = (Map<String, String>) params.get("headers");
            this.headers = headersMap;
        } else {
            this.headers = new HashMap<>();
        }

        Map<String, Object> details = new HashMap<>();
        details.put("transferId", transferId);
        details.put("type", type);
        details.put("url", url);
        TNMLogger.debug("Background transfer proxy created", "BackgroundTransfer", details);
    }

    @Kroll.method
    public void start() {
        if (isActive) {
            TNMLogger.warning("Transfer already active", "BackgroundTransfer",
                    Map.of("transferId", transferId));
            return;
        }

        isActive = true;

        if ("download".equals(type)) {
            startDownload();
        } else if ("upload".equals(type)) {
            startUpload();
        }
    }

    private void startDownload() {
        transferManager.startDownload(
                transferId,
                url,
                destination,
                headers,
                new TNMBackgroundTransferManager.TransferCallback() {
                    @Override
                    public void onProgress(long sent, long total) {
                        handleProgress(sent, total);
                    }

                    @Override
                    public void onComplete(String response) {
                        handleComplete(response);
                    }

                    @Override
                    public void onError(Exception error) {
                        handleError(error);
                    }
                }
        );
    }

    private void startUpload() {
        transferManager.startUpload(
                transferId,
                url,
                filePath,
                headers,
                new TNMBackgroundTransferManager.TransferCallback() {
                    @Override
                    public void onProgress(long sent, long total) {
                        handleProgress(sent, total);
                    }

                    @Override
                    public void onComplete(String response) {
                        handleComplete(response);
                    }

                    @Override
                    public void onError(Exception error) {
                        handleError(error);
                    }
                }
        );
    }

    @Kroll.method
    public void pause() {
        if (!isActive) return;

        transferManager.pause(transferId);

        KrollDict event = new KrollDict();
        event.put("transferId", transferId);
        fireEvent("paused", event);
    }

    @Kroll.method
    public void resume() {
        if (!isActive) return;

        transferManager.resume(transferId);

        KrollDict event = new KrollDict();
        event.put("transferId", transferId);
        fireEvent("resumed", event);
    }

    @Kroll.method
    public void cancel() {
        if (!isActive) return;

        transferManager.cancel(transferId);
        isActive = false;

        KrollDict event = new KrollDict();
        event.put("transferId", transferId);
        fireEvent("cancelled", event);
    }

    private void handleProgress(long sent, long total) {
        if (!isActive) return;

        KrollDict event = new KrollDict();
        event.put("transferId", transferId);
        event.put("sent", sent);
        event.put("total", total);
        event.put("progress", total > 0 ? (double) sent / total : 0.0);

        fireEvent("progress", event);
    }

    private void handleComplete(String response) {
        if (!isActive) return;

        isActive = false;

        KrollDict event = new KrollDict();
        event.put("transferId", transferId);

        if ("download".equals(type)) {
            event.put("path", destination);
        } else {
            event.put("response", response != null ? response : "");
        }

        fireEvent("complete", event);
    }

    private void handleError(Exception error) {
        if (!isActive) return;

        isActive = false;

        KrollDict event = new KrollDict();
        event.put("transferId", transferId);
        event.put("error", error.getMessage());

        fireEvent("error", event);
    }
}