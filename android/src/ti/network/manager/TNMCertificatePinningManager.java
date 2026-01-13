/**
 * Ti.Network.Manager - Certificate Pinning Manager
 * Manages SSL certificate pinning for secure connections
 * Uses OkHttp's CertificatePinner
 */

package ti.network.manager;

import okhttp3.CertificatePinner;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

public class TNMCertificatePinningManager {

    private Map<String, List<String>> pinnedDomains = new HashMap<>();
    private CertificatePinner certificatePinner;

    public TNMCertificatePinningManager() {
        TNMLogger.info("Certificate pinning manager initialized", "CertificatePinning");
    }

    /**
     * Set certificate pins for a domain
     */
    public void setCertificatePins(String domain, List<String> hashes) {
        pinnedDomains.put(domain, hashes);
        rebuildPinner();

        TNMLogger.CertificatePinning.configured(domain, hashes.size());
    }

    /**
     * Get the certificate pinner for OkHttp
     */
    public CertificatePinner getCertificatePinner() {
        return certificatePinner;
    }

    /**
     * Check if a domain has pinning configured
     */
    public boolean hasPinning(String domain) {
        return pinnedDomains.containsKey(domain);
    }

    /**
     * Rebuild the certificate pinner with all configured domains
     */
    private void rebuildPinner() {
        CertificatePinner.Builder builder = new CertificatePinner.Builder();

        for (Map.Entry<String, List<String>> entry : pinnedDomains.entrySet()) {
            String domain = entry.getKey();
            List<String> hashes = entry.getValue();

            for (String hash : hashes) {
                builder.add(domain, hash);
            }
        }

        certificatePinner = builder.build();

        TNMLogger.debug("Certificate pinner rebuilt", "CertificatePinning",
                Map.of("totalDomains", pinnedDomains.size()));
    }

    /**
     * Clear all certificate pins
     */
    public void clearAllPins() {
        pinnedDomains.clear();
        certificatePinner = new CertificatePinner.Builder().build();

        TNMLogger.info("All certificate pins cleared", "CertificatePinning");
    }

    /**
     * Clear pins for specific domain
     */
    public void clearPins(String domain) {
        pinnedDomains.remove(domain);
        rebuildPinner();

        TNMLogger.info("Certificate pins cleared for domain", "CertificatePinning",
                Map.of("domain", domain));
    }
}