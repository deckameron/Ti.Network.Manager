/**
 * Ti.Network.Manager - Background Transfer Manager
 * Manages background downloads and uploads that survive app termination
 * Uses Android WorkManager for true background persistence
 */

package ti.network.manager;

import android.content.Context;
import android.os.Handler;
import android.os.Looper;

import androidx.annotation.NonNull;
import androidx.work.*;
import okhttp3.*;
import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.TimeUnit;

public class TNMBackgroundTransferManager {

    private final Context context;
    private final ConcurrentHashMap<String, UUID> workRequests = new ConcurrentHashMap<>();
    private final ConcurrentHashMap<String, TransferCallback> callbacks = new ConcurrentHashMap<>();
    private final Handler mainHandler = new Handler(Looper.getMainLooper());

    public TNMBackgroundTransferManager(Context context, OkHttpClient.Builder clientBuilder) {
        this.context = context;
        TNMLogger.info("Background transfer manager initialized", "BackgroundTransfer");
    }

    /**
     * Start background download using WorkManager
     */
    public void startDownload(
            String transferId,
            String url,
            String destination,
            Map<String, String> headers,
            TransferCallback callback
    ) {
        TNMLogger.info("Starting background download", "BackgroundTransfer", Map.of(
                "transferId", transferId,
                "url", url,
                "destination", destination
        ));

        // Store callback
        callbacks.put(transferId, callback);

        // Build input data
        Data.Builder dataBuilder = new Data.Builder()
                .putString("transferId", transferId)
                .putString("url", url)
                .putString("destination", destination)
                .putString("type", "download");

        // Add headers
        if (headers != null) {
            int index = 0;
            for (Map.Entry<String, String> entry : headers.entrySet()) {
                dataBuilder.putString("header_key_" + index, entry.getKey());
                dataBuilder.putString("header_value_" + index, entry.getValue());
                index++;
            }
            dataBuilder.putInt("header_count", index);
        }

        // Build constraints (WiFi not required, but can be added)
        Constraints constraints = new Constraints.Builder()
                .setRequiredNetworkType(NetworkType.CONNECTED)
                .build();

        // Build work request
        OneTimeWorkRequest workRequest = new OneTimeWorkRequest.Builder(DownloadWorker.class)
                .setInputData(dataBuilder.build())
                .setConstraints(constraints)
                .addTag(transferId)
                .build();

        // Enqueue work
        WorkManager.getInstance(context).enqueue(workRequest);
        workRequests.put(transferId, workRequest.getId());

        // Observe work status
        observeWork(workRequest.getId(), transferId);
    }

    /**
     * Start background upload using WorkManager
     */
    public void startUpload(
            String transferId,
            String url,
            String filePath,
            Map<String, String> headers,
            TransferCallback callback
    ) {
        TNMLogger.info("Starting background upload", "BackgroundTransfer", Map.of(
                "transferId", transferId,
                "url", url,
                "file", filePath
        ));

        // Verify file exists
        File file = new File(filePath);
        if (!file.exists()) {
            callback.onError(new Exception("File not found: " + filePath));
            return;
        }

        // Store callback
        callbacks.put(transferId, callback);

        // Build input data
        Data.Builder dataBuilder = new Data.Builder()
                .putString("transferId", transferId)
                .putString("url", url)
                .putString("filePath", filePath)
                .putString("type", "upload");

        // Add headers
        if (headers != null) {
            int index = 0;
            for (Map.Entry<String, String> entry : headers.entrySet()) {
                dataBuilder.putString("header_key_" + index, entry.getKey());
                dataBuilder.putString("header_value_" + index, entry.getValue());
                index++;
            }
            dataBuilder.putInt("header_count", index);
        }

        // Build constraints
        Constraints constraints = new Constraints.Builder()
                .setRequiredNetworkType(NetworkType.CONNECTED)
                .build();

        // Build work request
        OneTimeWorkRequest workRequest = new OneTimeWorkRequest.Builder(UploadWorker.class)
                .setInputData(dataBuilder.build())
                .setConstraints(constraints)
                .addTag(transferId)
                .build();

        // Enqueue work
        WorkManager.getInstance(context).enqueue(workRequest);
        workRequests.put(transferId, workRequest.getId());

        // Observe work status
        observeWork(workRequest.getId(), transferId);
    }

    /**
     * Pause transfer (not truly supported by WorkManager, but we can cancel and store state)
     */
    public void pause(String transferId) {
        UUID workId = workRequests.get(transferId);
        if (workId != null) {
            WorkManager.getInstance(context).cancelWorkById(workId);

            TNMLogger.info("Transfer paused (cancelled)", "BackgroundTransfer", Map.of(
                    "transferId", transferId
            ));
        }
    }

    /**
     * Resume transfer (restart the work)
     */
    public void resume(String transferId) {
        // Note: True resume with partial download would require more complex implementation
        // For now, this restarts the transfer from beginning
        TNMLogger.info("Transfer resume not fully implemented", "BackgroundTransfer", Map.of(
                "transferId", transferId
        ));
    }

    /**
     * Cancel transfer
     */
    public void cancel(String transferId) {
        UUID workId = workRequests.get(transferId);
        if (workId != null) {
            WorkManager.getInstance(context).cancelWorkById(workId);
            workRequests.remove(transferId);
            callbacks.remove(transferId);

            TNMLogger.info("Transfer cancelled", "BackgroundTransfer", Map.of(
                    "transferId", transferId
            ));
        }
    }

    /**
     * Observe work progress and status
     */
    private void observeWork(UUID workId, String transferId) {
        WorkManager.getInstance(context)
                .getWorkInfoByIdLiveData(workId)
                .observeForever(workInfo -> {
                    if (workInfo == null) return;

                    TransferCallback callback = callbacks.get(transferId);
                    if (callback == null) return;

                    // Get progress
                    Data progress = workInfo.getProgress();
                    long sent = progress.getLong("sent", 0);
                    long total = progress.getLong("total", 0);

                    if (sent > 0 && total > 0) {
                        mainHandler.post(() -> callback.onProgress(sent, total));
                    }

                    // Check final state
                    if (workInfo.getState() == WorkInfo.State.SUCCEEDED) {
                        Data output = workInfo.getOutputData();
                        String result = output.getString("result");

                        callbacks.remove(transferId);
                        workRequests.remove(transferId);

                        mainHandler.post(() -> callback.onComplete(result));

                    } else if (workInfo.getState() == WorkInfo.State.FAILED) {
                        Data output = workInfo.getOutputData();
                        String error = output.getString("error");

                        callbacks.remove(transferId);
                        workRequests.remove(transferId);

                        mainHandler.post(() -> callback.onError(new Exception(error)));
                    }
                });
    }

    /**
     * Download Worker - Runs in background
     */
    public static class DownloadWorker extends Worker {

        public DownloadWorker(Context context, WorkerParameters params) {
            super(context, params);
        }

        @NonNull
        @Override
        public Result doWork() {
            String transferId = getInputData().getString("transferId");
            String url = getInputData().getString("url");
            String destination = getInputData().getString("destination");

            assert transferId != null;
            assert url != null;
            TNMLogger.info("Download worker started", "BackgroundTransfer", Map.of(
                    "transferId", transferId,
                    "url", url
            ));

            try {
                // Build OkHttp client
                OkHttpClient client = new OkHttpClient.Builder()
                        .readTimeout(0, TimeUnit.SECONDS)
                        .build();

                // Build request with headers
                Request.Builder requestBuilder = new Request.Builder().url(url);

                int headerCount = getInputData().getInt("header_count", 0);
                for (int i = 0; i < headerCount; i++) {
                    String key = getInputData().getString("header_key_" + i);
                    String value = getInputData().getString("header_value_" + i);
                    if (key != null && value != null) {
                        requestBuilder.header(key, value);
                    }
                }

                Request request = requestBuilder.build();

                // Execute request
                Response response = client.newCall(request).execute();

                if (!response.isSuccessful()) {
                    return Result.failure(
                            new Data.Builder()
                                    .putString("error", "HTTP " + response.code())
                                    .build()
                    );
                }

                ResponseBody body = response.body();
                if (body == null) {
                    return Result.failure(
                            new Data.Builder()
                                    .putString("error", "Empty response body")
                                    .build()
                    );
                }

                // Download with progress
                long totalBytes = body.contentLength();
                InputStream inputStream = body.byteStream();

                File destinationFile = new File(destination);
                destinationFile.getParentFile().mkdirs();

                FileOutputStream outputStream = new FileOutputStream(destinationFile);

                byte[] buffer = new byte[8192];
                long downloadedBytes = 0;
                int bytesRead;

                while ((bytesRead = inputStream.read(buffer)) != -1) {
                    outputStream.write(buffer, 0, bytesRead);
                    downloadedBytes += bytesRead;

                    // Update progress
                    setProgressAsync(
                            new Data.Builder()
                                    .putLong("sent", downloadedBytes)
                                    .putLong("total", totalBytes)
                                    .build()
                    );
                }

                outputStream.close();
                inputStream.close();

                TNMLogger.success("Download worker completed", "BackgroundTransfer", Map.of(
                        "transferId", transferId,
                        "bytes", downloadedBytes
                ));

                return Result.success(
                        new Data.Builder()
                                .putString("result", destination)
                                .build()
                );

            } catch (Exception e) {
                TNMLogger.error("Download worker failed", "BackgroundTransfer", e);

                return Result.failure(
                        new Data.Builder()
                                .putString("error", e.getMessage())
                                .build()
                );
            }
        }
    }

    /**
     * Upload Worker - Runs in background
     */
    public static class UploadWorker extends Worker {

        public UploadWorker(Context context, WorkerParameters params) {
            super(context, params);
        }

        @NonNull
        @Override
        public Result doWork() {
            String transferId = getInputData().getString("transferId");
            String url = getInputData().getString("url");
            String filePath = getInputData().getString("filePath");

            assert transferId != null;
            assert url != null;
            TNMLogger.info("Upload worker started", "BackgroundTransfer", Map.of(
                    "transferId", transferId,
                    "url", url
            ));

            try {
                assert filePath != null;
                File file = new File(filePath);
                if (!file.exists()) {
                    return Result.failure(
                            new Data.Builder()
                                    .putString("error", "File not found: " + filePath)
                                    .build()
                    );
                }

                final long fileSize = file.length();

                // Build OkHttp client
                OkHttpClient client = new OkHttpClient.Builder()
                        .writeTimeout(0, TimeUnit.SECONDS)
                        .build();

                // Create request body with progress tracking
                RequestBody fileBody = RequestBody.create(file, MediaType.parse("application/octet-stream"));
                RequestBody progressBody = new RequestBody() {
                    @Override
                    public MediaType contentType() {
                        return fileBody.contentType();
                    }

                    @Override
                    public long contentLength() {
                        return fileSize;
                    }

                    @Override
                    public void writeTo(@NonNull okio.BufferedSink sink) throws java.io.IOException {
                        okio.BufferedSink progressSink = okio.Okio.buffer(new okio.ForwardingSink(sink) {
                            private long bytesWritten = 0;

                            @Override
                            public void write(@NonNull okio.Buffer source, long byteCount) throws java.io.IOException {
                                super.write(source, byteCount);
                                bytesWritten += byteCount;

                                // Update progress
                                setProgressAsync(
                                        new Data.Builder()
                                                .putLong("sent", bytesWritten)
                                                .putLong("total", fileSize)
                                                .build()
                                );
                            }
                        });

                        fileBody.writeTo(progressSink);
                        progressSink.flush();
                    }
                };

                // Build request with headers
                Request.Builder requestBuilder = new Request.Builder()
                        .url(url)
                        .post(progressBody);

                int headerCount = getInputData().getInt("header_count", 0);
                for (int i = 0; i < headerCount; i++) {
                    String key = getInputData().getString("header_key_" + i);
                    String value = getInputData().getString("header_value_" + i);
                    if (key != null && value != null) {
                        requestBuilder.header(key, value);
                    }
                }

                Request request = requestBuilder.build();

                // Execute request
                Response response = client.newCall(request).execute();

                String responseBody = null;
                if (response.body() != null) {
                    responseBody = response.body().string();
                }

                if (!response.isSuccessful()) {
                    return Result.failure(
                            new Data.Builder()
                                    .putString("error", "HTTP " + response.code())
                                    .build()
                    );
                }

                TNMLogger.success("Upload worker completed", "BackgroundTransfer", Map.of(
                        "transferId", transferId
                ));

                return Result.success(
                        new Data.Builder()
                                .putString("result", responseBody != null ? responseBody : "")
                                .build()
                );

            } catch (Exception e) {
                TNMLogger.error("Upload worker failed", "BackgroundTransfer", e);

                return Result.failure(
                        new Data.Builder()
                                .putString("error", e.getMessage())
                                .build()
                );
            }
        }
    }

    /**
     * Transfer callback interface
     */
    public interface TransferCallback {
        void onProgress(long sent, long total);
        void onComplete(String response);
        void onError(Exception error);
    }
}