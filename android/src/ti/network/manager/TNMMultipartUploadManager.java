/**
 * Ti.Network.Manager - Multipart Upload Manager
 * Manages multipart/form-data uploads with progress tracking
 * Uses OkHttp's MultipartBody
 */

package ti.network.manager;

import android.os.Handler;
import android.os.Looper;
import android.util.Base64;

import androidx.annotation.NonNull;

import okhttp3.*;
import java.io.IOException;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

public class TNMMultipartUploadManager {

    private final OkHttpClient client;
    private final ConcurrentHashMap<String, Call> activeUploads = new ConcurrentHashMap<>();
    private final Handler mainHandler = new Handler(Looper.getMainLooper());

    public TNMMultipartUploadManager(OkHttpClient.Builder clientBuilder) {
        this.client = clientBuilder.build();
        TNMLogger.info("Multipart upload manager initialized", "MultipartUpload");
    }

    /**
     * Execute multipart upload
     */
    public void upload(
            String uploadId,
            String url,
            Map<String, String> headers,
            List<MultipartField> fields,
            float priority,
            UploadCallback callback
    ) {
        TNMLogger.info("Starting multipart upload", "MultipartUpload", Map.of(
                "uploadId", uploadId,
                "url", url,
                "fieldCount", fields.size()
        ));

        // Build multipart body
        MultipartBody.Builder bodyBuilder = new MultipartBody.Builder()
                .setType(MultipartBody.FORM);

        long totalSize = 0;
        List<FileFieldInfo> fileFields = new ArrayList<>();

        for (MultipartField field : fields) {
            if (field.isFile) {
                // File field
                byte[] data = Base64.decode(field.data, Base64.DEFAULT);
                totalSize += data.length;

                fileFields.add(new FileFieldInfo(
                        field.filename,
                        totalSize - data.length,
                        data.length
                ));

                RequestBody fileBody = RequestBody.create(
                        data,
                        MediaType.parse(field.mimeType)
                );

                bodyBuilder.addFormDataPart(field.name, field.filename, fileBody);

                TNMLogger.debug("Added file field", "MultipartUpload", Map.of(
                        "name", field.name,
                        "filename", field.filename,
                        "size", data.length
                ));
            } else {
                // Text field
                bodyBuilder.addFormDataPart(field.name, field.value);

                TNMLogger.debug("Added text field", "MultipartUpload", Map.of(
                        "name", field.name
                ));
            }
        }

        // Create progress tracking body
        final long finalTotalSize = totalSize;
        final List<FileFieldInfo> finalFileFields = fileFields;

        RequestBody multipartBody = bodyBuilder.build();
        RequestBody progressBody = new RequestBody() {
            @Override
            public MediaType contentType() {
                return multipartBody.contentType();
            }

            @Override
            public long contentLength() throws IOException {
                return multipartBody.contentLength();
            }

            @Override
            public void writeTo(@NonNull okio.BufferedSink sink) throws IOException {
                okio.BufferedSink progressSink = okio.Okio.buffer(new okio.ForwardingSink(sink) {
                    private long bytesWritten = 0;

                    @Override
                    public void write(@NonNull okio.Buffer source, long byteCount) throws IOException {
                        super.write(source, byteCount);
                        bytesWritten += byteCount;

                        // Calculate overall progress
                        final double overallProgress = (double) bytesWritten / finalTotalSize;

                        // Calculate which file is being uploaded
                        String currentFile = null;
                        double fileProgress = 0.0;

                        for (FileFieldInfo fileField : finalFileFields) {
                            if (bytesWritten >= fileField.offset &&
                                    bytesWritten < (fileField.offset + fileField.size)) {
                                currentFile = fileField.filename;
                                long fileBytesSent = bytesWritten - fileField.offset;
                                fileProgress = (double) fileBytesSent / fileField.size;

                                // Fire per-file progress
                                final String finalCurrentFile = currentFile;
                                final double finalFileProgress = fileProgress;

                                mainHandler.post(() -> {
                                    callback.onFileProgress(finalCurrentFile, finalFileProgress);
                                });

                                break;
                            }
                        }

                        // Fire overall progress
                        final String finalCurrentFileForOverall = currentFile;
                        mainHandler.post(() -> {
                            callback.onProgress(bytesWritten, finalTotalSize,
                                    overallProgress, finalCurrentFileForOverall);
                        });
                    }
                });

                multipartBody.writeTo(progressSink);
                progressSink.flush();
            }
        };

        // Build request
        Request.Builder requestBuilder = new Request.Builder()
                .url(url)
                .post(progressBody);

        if (headers != null) {
            for (Map.Entry<String, String> entry : headers.entrySet()) {
                requestBuilder.header(entry.getKey(), entry.getValue());
            }
        }

        Request request = requestBuilder.build();

        // Execute request
        Call call = client.newCall(request);
        activeUploads.put(uploadId, call);

        call.enqueue(new Callback() {
            @Override
            public void onResponse(@NonNull Call call, @NonNull Response response) throws IOException {
                activeUploads.remove(uploadId);

                String body = null;
                body = response.body().string();

                Map<String, String> responseHeaders = new HashMap<>();
                for (String name : response.headers().names()) {
                    responseHeaders.put(name, response.header(name));
                }

                final int statusCode = response.code();
                final String finalBody = body;
                final Map<String, String> finalHeaders = responseHeaders;

                TNMLogger.success("Multipart upload completed", "MultipartUpload", Map.of(
                        "uploadId", uploadId,
                        "statusCode", statusCode
                ));

                mainHandler.post(() -> {
                    callback.onComplete(statusCode, finalHeaders, finalBody);
                });
            }

            @Override
            public void onFailure(@NonNull Call call, @NonNull IOException e) {
                activeUploads.remove(uploadId);

                TNMLogger.error("Multipart upload failed", "MultipartUpload", e);

                mainHandler.post(() -> {
                    callback.onError(e);
                });
            }
        });
    }

    /**
     * Cancel upload
     */
    public void cancel(String uploadId) {
        Call call = activeUploads.get(uploadId);
        if (call != null) {
            call.cancel();
            activeUploads.remove(uploadId);

            TNMLogger.info("Multipart upload cancelled", "MultipartUpload", Map.of(
                    "uploadId", uploadId
            ));
        }
    }

    /**
     * Multipart field
     */
    public static class MultipartField {
        public String name;
        public String value;
        public String filename;
        public String mimeType;
        public String data; // base64
        public boolean isFile;

        public MultipartField(String name, String value) {
            this.name = name;
            this.value = value;
            this.isFile = false;
        }

        public MultipartField(String name, String filename, String mimeType, String data) {
            this.name = name;
            this.filename = filename;
            this.mimeType = mimeType;
            this.data = data;
            this.isFile = true;
        }
    }

    /**
     * File field info for progress tracking
     */
    private static class FileFieldInfo {
        String filename;
        long offset;
        long size;

        FileFieldInfo(String filename, long offset, long size) {
            this.filename = filename;
            this.offset = offset;
            this.size = size;
        }
    }

    /**
     * Upload callback interface
     */
    public interface UploadCallback {
        void onProgress(long sent, long total, double progress, String currentFile);
        void onFileProgress(String filename, double progress);
        void onComplete(int statusCode, Map<String, String> headers, String body);
        void onError(Exception error);
    }
}