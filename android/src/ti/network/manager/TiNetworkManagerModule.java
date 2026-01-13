/**
 * Ti.Network.Manager Module
 * Advanced HTTP networking for Titanium
 * Android version - mirrors iOS functionality
 */

package ti.network.manager;

import org.appcelerator.kroll.KrollDict;
import org.appcelerator.kroll.KrollFunction;
import org.appcelerator.kroll.KrollModule;
import org.appcelerator.kroll.annotations.Kroll;
import org.appcelerator.titanium.TiApplication;
import okhttp3.OkHttpClient;
import java.util.List;
import java.util.Map;

@Kroll.module(name = "TiNetworkManager", id = "ti.network.manager")
public class TiNetworkManagerModule extends KrollModule {

	// Managers
	private TNMRequestManager requestManager;
	private final TNMStreamManager streamManager;
	private final TNMBackgroundTransferManager backgroundTransferManager;
	private final TNMInterceptorManager interceptorManager;
	private final TNMCacheManager cacheManager;
	private final TNMCertificatePinningManager certificatePinningManager;
	private TNMWebSocketManager webSocketManager;
	private TNMMultipartUploadManager multipartUploadManager;

	// Constants - Priority
	@Kroll.constant
	public static final float PRIORITY_HIGH = 0.75f;
	@Kroll.constant
	public static final float PRIORITY_NORMAL = 0.5f;
	@Kroll.constant
	public static final float PRIORITY_LOW = 0.25f;

	// Constants - Cache Policy
	@Kroll.constant
	public static final String CACHE_POLICY_NETWORK_ONLY = "network-only";
	@Kroll.constant
	public static final String CACHE_POLICY_CACHE_FIRST = "cache-first";
	@Kroll.constant
	public static final String CACHE_POLICY_NETWORK_FIRST = "network-first";

	// Constants - Retry Backoff
	@Kroll.constant
	public static final String RETRY_BACKOFF_LINEAR = "linear";
	@Kroll.constant
	public static final String RETRY_BACKOFF_EXPONENTIAL = "exponential";

	public TiNetworkManagerModule() {
		super();

		// Initialize managers
		certificatePinningManager = new TNMCertificatePinningManager();
		interceptorManager = new TNMInterceptorManager();
		cacheManager = new TNMCacheManager(TiApplication.getInstance().getApplicationContext());

		// Build OkHttp client with interceptors and certificate pinning
		OkHttpClient.Builder clientBuilder = new OkHttpClient.Builder()
				.addInterceptor(interceptorManager.createRequestInterceptor())
				.addInterceptor(interceptorManager.createResponseInterceptor())
				.cache(cacheManager.getDiskCache());

		// Add certificate pinner if configured
		if (certificatePinningManager.getCertificatePinner() != null) {
			clientBuilder.certificatePinner(certificatePinningManager.getCertificatePinner());
		}

		requestManager = new TNMRequestManager(clientBuilder);
		webSocketManager = new TNMWebSocketManager(clientBuilder);
		multipartUploadManager = new TNMMultipartUploadManager(clientBuilder);

		TNMLogger.info("Ti.Network.Manager initialized", null, Map.of(
				"version", "1.0.0",
				"platform", "Android"
		));

		streamManager = new TNMStreamManager(clientBuilder);
		backgroundTransferManager = new TNMBackgroundTransferManager(
				TiApplication.getInstance().getApplicationContext(),
				clientBuilder
		);
	}

	// MARK: - Request Methods

	@Kroll.method
	public TNMRequestProxy createRequest(KrollDict params) {
		TNMLogger.debug("Creating request", "Module", Map.of(
				"url", params.optString("url", "unknown")
		));

		return new TNMRequestProxy(params, requestManager, cacheManager);
	}

	// MARK: - WebSocket Methods

	@Kroll.method
	public TNMWebSocketProxy createWebSocket(KrollDict params) {
		TNMLogger.debug("Creating WebSocket", "Module", Map.of(
				"url", params.optString("url", "unknown")
		));

		return new TNMWebSocketProxy(params, webSocketManager);
	}

	// MARK: - Multipart Upload Methods

	@Kroll.method
	public TNMMultipartUploadProxy createMultipartUpload(KrollDict params) {
		TNMLogger.debug("Creating multipart upload", "Module", Map.of(
				"url", params.optString("url", "unknown")
		));

		return new TNMMultipartUploadProxy(params, multipartUploadManager);
	}

	// MARK: - Certificate Pinning

	@Kroll.method
	public void setCertificatePinning(String domain, Object[] hashes) {
		List<String> hashList = new java.util.ArrayList<>();
		for (Object hash : hashes) {
			hashList.add((String) hash);
		}

		certificatePinningManager.setCertificatePins(domain, hashList);

		// Rebuild OkHttp client with new pinning
		OkHttpClient.Builder clientBuilder = new OkHttpClient.Builder()
				.addInterceptor(interceptorManager.createRequestInterceptor())
				.addInterceptor(interceptorManager.createResponseInterceptor())
				.certificatePinner(certificatePinningManager.getCertificatePinner())
				.cache(cacheManager.getDiskCache());

		requestManager = new TNMRequestManager(clientBuilder);
		webSocketManager = new TNMWebSocketManager(clientBuilder);
		multipartUploadManager = new TNMMultipartUploadManager(clientBuilder);
	}

	// MARK: - Interceptors

	@Kroll.method
	public void addRequestInterceptor(KrollFunction callback) {
		interceptorManager.addRequestInterceptor(callback);
	}

	@Kroll.method
	public void addResponseInterceptor(KrollFunction callback) {
		interceptorManager.addResponseInterceptor(callback);
	}

	@Kroll.method
	public TiHTTPStreamProxy createStreamRequest(KrollDict params) {
		TNMLogger.debug("Creating stream request", "Module", Map.of(
				"url", params.optString("url", "unknown")
		));

		return new TiHTTPStreamProxy(params, streamManager);
	}

	@Kroll.method
	public TNMBackgroundTransferProxy createBackgroundTransfer(KrollDict params) {
		TNMLogger.debug("Creating background transfer", "Module", Map.of(
				"url", params.optString("url", "unknown"),
				"type", params.optString("type", "download")
		));

		return new TNMBackgroundTransferProxy(params, backgroundTransferManager);
	}

	// MARK: - Cache

	@Kroll.method
	public void clearCache(Object domain) {
		if (domain instanceof String) {
			cacheManager.clearCache((String) domain);
		} else {
			cacheManager.clearAllCache();
		}
	}

	@Kroll.method
	public String getName() {
		return "TiNetworkManager";
	}
}