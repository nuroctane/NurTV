package tv.webwrap;

import java.net.URI;
import java.net.URISyntaxException;

/** Exact HTTPS origins only. Embedded media hosts are independent of top-level navigation. */
public final class NavigationPolicy {
    private NavigationPolicy() {}

    public static boolean allows(String url, String home, String extraHosts) {
        try {
            URI uri = new URI(url);
            String host = uri.getHost();
            if (!"https".equalsIgnoreCase(uri.getScheme()) || host == null
                    || uri.getRawUserInfo() != null || (uri.getPort() != -1 && uri.getPort() != 443)) return false;
            if (host.equalsIgnoreCase(new URI(home).getHost())) return true;
            if (extraHosts != null) for (String candidate : extraHosts.split(",")) {
                if (host.equalsIgnoreCase(candidate.trim())) return true;
            }
        } catch (URISyntaxException | NullPointerException ignored) {
            // Malformed and non-network destinations stay outside the wrapper.
        }
        return false;
    }
}
