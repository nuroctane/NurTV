import tv.webwrap.NavigationPolicy;

public final class NavigationPolicyTest {
    public static void main(String[] args) {
        for (String url : new String[]{"https://site.example/watch?id=1", "https://SITE.example:443/"}) {
            if (!NavigationPolicy.allows(url, "https://site.example/", "player.example")) throw new AssertionError(url);
        }
        if (!NavigationPolicy.allows("https://player.example/", "https://site.example/", "player.example")) throw new AssertionError();
        for (String url : new String[]{"https://site.example.attacker.test/", "https://site.example@attacker.test/",
                "https://attacker.test@site.example/", "https://site.example:444/", "http://site.example/",
                "javascript:alert(1)", "intent://site.example/", "file:///sdcard/test", "content://test/",
                "https://site.example\\@attacker.test/", "https://sub.site.example/", "//site.example/"}) {
            if (NavigationPolicy.allows(url, "https://site.example/", "player.example")) throw new AssertionError(url);
        }
        System.out.println("navigation ok: exact hosts, schemes, ports and authority confusion");
    }
}
