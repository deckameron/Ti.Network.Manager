/**
 * Ti.Network.Manager - Interceptor Manager
 * Manages request and response interceptors
 * Uses OkHttp's Interceptor interface
 */

package ti.network.manager;

import okhttp3.Interceptor;
import okhttp3.Request;
import okhttp3.Response;
import org.appcelerator.kroll.KrollDict;
import org.appcelerator.kroll.KrollFunction;
import java.io.IOException;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

public class TNMInterceptorManager {

    private List<KrollFunction> requestInterceptors = new ArrayList<>();
    private List<KrollFunction> responseInterceptors = new ArrayList<>();

    public TNMInterceptorManager() {
        TNMLogger.info("Interceptor manager initialized", "Interceptor");
    }

    /**
     * Add request interceptor
     */
    public void addRequestInterceptor(KrollFunction callback) {
        requestInterceptors.add(callback);
        TNMLogger.Interceptor.requestInterceptorAdded(requestInterceptors.size());
    }

    /**
     * Add response interceptor
     */
    public void addResponseInterceptor(KrollFunction callback) {
        responseInterceptors.add(callback);
        TNMLogger.Interceptor.responseInterceptorAdded(responseInterceptors.size());
    }

    /**
     * Create OkHttp request interceptor
     */
    public Interceptor createRequestInterceptor() {
        return new Interceptor() {
            @Override
            public Response intercept(Chain chain) throws IOException {
                Request request = chain.request();

                // Call all request interceptors
                for (KrollFunction callback : requestInterceptors) {
                    KrollDict config = new KrollDict();
                    config.put("url", request.url().toString());
                    config.put("method", request.method());

                    // Convert headers
                    Map<String, String> headers = new HashMap<>();
                    for (String name : request.headers().names()) {
                        headers.put(name, request.header(name));
                    }
                    config.put("headers", headers);

                    // Call interceptor
                    Object result = callback.call(null, new Object[] { config });

                    if (result instanceof KrollDict) {
                        KrollDict modifiedConfig = (KrollDict) result;

                        // Rebuild request with modified config
                        Request.Builder builder = request.newBuilder();

                        if (modifiedConfig.containsKey("headers")) {
                            @SuppressWarnings("unchecked")
                            Map<String, String> modifiedHeaders =
                                    (Map<String, String>) modifiedConfig.get("headers");

                            for (Map.Entry<String, String> entry : modifiedHeaders.entrySet()) {
                                builder.header(entry.getKey(), entry.getValue());
                            }
                        }

                        request = builder.build();
                    }
                }

                return chain.proceed(request);
            }
        };
    }

    /**
     * Create OkHttp response interceptor
     */
    public Interceptor createResponseInterceptor() {
        return new Interceptor() {
            @Override
            public Response intercept(Chain chain) throws IOException {
                Response response = chain.proceed(chain.request());

                // Call all response interceptors
                for (KrollFunction callback : responseInterceptors) {
                    KrollDict responseDict = new KrollDict();
                    responseDict.put("statusCode", response.code());

                    // Convert headers
                    Map<String, String> headers = new HashMap<>();
                    for (String name : response.headers().names()) {
                        headers.put(name, response.header(name));
                    }
                    responseDict.put("headers", headers);

                    // Call interceptor
                    callback.call(null, new Object[] { responseDict });
                }

                return response;
            }
        };
    }

    /**
     * Clear all interceptors
     */
    public void clearAllInterceptors() {
        requestInterceptors.clear();
        responseInterceptors.clear();
        TNMLogger.info("All interceptors cleared", "Interceptor");
    }
}