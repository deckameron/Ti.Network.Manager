/**
 * Ti.Network.Manager - Multipart Upload Proxy
 * JavaScript proxy for multipart uploads
 * Mirrors iOS TNMMultipartUploadProxy
 */

package ti.network.manager;

import org.appcelerator.kroll.KrollDict;
import org.appcelerator.kroll.KrollProxy;
import org.appcelerator.kroll.annotations.Kroll;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

@Kroll.proxy(creatableInModule = TiNetworkManagerModule.class)
public class TNMMultipartUploadProxy extends KrollProxy {

    private final TNMMultipartUploadManager uploadManager;
    private final String uploadId;
    private final String url;
    private final Map<String, String> headers;
    private final List<TNMMultipartUploadManager.MultipartField> fields;
    private final String priority;
    private boolean isActive = false;

    public TNMMultipartUploadProxy(KrollDict params, TNMMultipartUploadManager uploadManager) {
        super();

        this.uploadManager = uploadManager;
        this.uploadId = UUID.randomUUID().toString();
        this.url = params.optString("url", "");
        this.priority = params.optString("priority", "normal");

        // Headers
        if (params.containsKey("headers")) {
            @SuppressWarnings("unchecked")
            Map<String, String> headersMap = (Map<String, String>) params.get("headers");
            this.headers = headersMap;
        } else {
            this.headers = new HashMap<>();
        }

        // Parse fields
        this.fields = new ArrayList<>();
        if (params.containsKey("fields")) {
            Object[] fieldsArray = (Object[]) params.get("fields");

            assert fieldsArray != null;
            for (Object fieldObj : fieldsArray) {
                @SuppressWarnings("unchecked")
                Map<String, Object> field = (Map<String, Object>) fieldObj;

                String type = (String) field.get("type");
                String name = (String) field.get("name");

                if ("text".equals(type)) {
                    // Text field
                    String value = (String) field.get("value");
                    fields.add(new TNMMultipartUploadManager.MultipartField(name, value));

                } else if ("file".equals(type)) {
                    // File field
                    String filename = (String) field.get("filename");
                    String mimeType = (String) field.get("mimeType");
                    String data = (String) field.get("data");

                    fields.add(new TNMMultipartUploadManager.MultipartField(
                            name, filename, mimeType, data
                    ));
                }
            }
        }

        Map<String, Object> details = new HashMap<>();
        details.put("uploadId", uploadId);
        details.put("url", url);
        details.put("fieldCount", fields.size());
        TNMLogger.debug("Multipart upload proxy created", "MultipartUpload", details);
    }

    @Kroll.method
    public void upload() {
        if (isActive) {
            TNMLogger.warning("Upload already active", "MultipartUpload",
                    Map.of("uploadId", uploadId));
            return;
        }

        isActive = true;

        // Convert priority
        float urlPriority = 0.5f; // Normal
        if ("high".equals(priority)) {
            urlPriority = 0.75f;
        } else if ("low".equals(priority)) {
            urlPriority = 0.25f;
        }

        uploadManager.upload(
                uploadId,
                url,
                headers,
                fields,
                urlPriority,
                new TNMMultipartUploadManager.UploadCallback() {
                    @Override
                    public void onProgress(long sent, long total, double progress, String currentFile) {
                        handleProgress(sent, total, progress, currentFile);
                    }

                    @Override
                    public void onFileProgress(String filename, double progress) {
                        handleFileProgress(filename, progress);
                    }

                    @Override
                    public void onComplete(int statusCode, Map<String, String> headers, String body) {
                        handleComplete(statusCode, headers, body);
                    }

                    @Override
                    public void onError(Exception error) {
                        handleError(error);
                    }
                }
        );
    }

    @Kroll.method
    public void cancel() {
        if (!isActive) return;

        uploadManager.cancel(uploadId);
        isActive = false;

        KrollDict event = new KrollDict();
        fireEvent("cancelled", event);
    }

    private void handleProgress(long sent, long total, double progress, String currentFile) {
        if (!isActive) return;

        KrollDict event = new KrollDict();
        event.put("uploadId", uploadId);
        event.put("totalBytesSent", sent);
        event.put("totalBytesExpected", total);
        event.put("progress", progress);
        if (currentFile != null) {
            event.put("currentFile", currentFile);
        }

        fireEvent("progress", event);
    }

    private void handleFileProgress(String filename, double progress) {
        if (!isActive) return;

        KrollDict event = new KrollDict();
        event.put("uploadId", uploadId);
        event.put("filename", filename);
        event.put("progress", progress);

        fireEvent("fileprogress", event);
    }

    private void handleComplete(int statusCode, Map<String, String> headers, String body) {
        if (!isActive) return;

        isActive = false;

        KrollDict event = new KrollDict();
        event.put("uploadId", uploadId);
        event.put("statusCode", statusCode);
        event.put("headers", headers);
        event.put("body", body != null ? body : "");
        event.put("success", statusCode >= 200 && statusCode < 300);

        fireEvent("complete", event);
    }

    private void handleError(Exception error) {
        if (!isActive) return;

        isActive = false;

        KrollDict event = new KrollDict();
        event.put("uploadId", uploadId);
        event.put("error", error.getMessage());

        fireEvent("error", event);
    }
}