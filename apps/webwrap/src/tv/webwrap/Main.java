package tv.webwrap;

import android.annotation.SuppressLint;
import android.app.Activity;
import android.app.AlertDialog;
import android.app.ActivityManager;
import android.net.Uri;
import android.content.pm.ActivityInfo;
import android.content.pm.PackageManager;
import android.graphics.Color;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.os.Message;
import android.os.SystemClock;
import android.util.Log;
import android.view.InputDevice;
import android.view.KeyEvent;
import android.view.MotionEvent;
import android.view.View;
import android.view.ViewGroup;
import android.view.WindowManager;
import android.webkit.ConsoleMessage;
import android.webkit.CookieManager;
import android.webkit.WebChromeClient;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.webkit.WebResourceRequest;
import android.webkit.WebResourceError;
import android.webkit.WebResourceResponse;
import android.widget.FrameLayout;
import android.widget.TextView;

import java.util.Locale;

/**
 * A website as a Fire TV app: a fullscreen WebView, a D-pad pointer, and the
 * media plumbing a TV browser needs.
 *
 * INPUT IS NATIVE, NOT SYNTHETIC. A <video> is very often inside an iframe, and
 * JavaScript events dispatched in the top document never cross a frame boundary
 * — the click lands on the <iframe> element and the player never sees it. Real
 * MotionEvents are routed by the browser itself, so they reach the player, they
 * fire hover (which is how a web player reveals its control bar), and they count
 * as genuine user activation, which is what requestFullscreen() insists on.
 * This is the approach TV Bro takes.
 *
 * The JS side is only what a native event cannot do: draw the cursor, scroll an
 * overflow container, and pin a <video> to the viewport for the fake-fullscreen
 * fallback.
 */
public final class Main extends Activity {

    private static final String TAG = "webwrap";

    private static final String DEFAULT_HOME = "https://example.com/";

    private static final int STEP = 44;
    private static final long DOUBLE_TAP_MS = 420;

    private FrameLayout root;
    private WebView web;
    private TextView loadNotice;
    private View customView;
    private WebChromeClient.CustomViewCallback customCallback;

    /** Pointer position in CSS pixels; multiplied by scale for native events. */
    private float px = 0f;
    private float py = 0f;
    /**
     * View pixels per CSS pixel, derived from innerWidth. NOT devicePixelRatio:
     * on this TCL (4K panel, 1080p Fire OS UI) it reports 4 while the view is
     * 1920 px wide and the page lays out at 960 CSS px — trusting it put every
     * native tap at twice the intended coordinate.
     */
    private float scale = 2f;
    private float vw = 960f;
    private float vh = 540f;

    private long lastOkAt = 0;
    private boolean fakeFull = false;
    /** Some players refuse to run inside a sandboxed iframe and say so on screen. */
    private boolean stripSandbox = false;
    /** Sites that stack a chat panel over the player (StreamEast does). */
    private boolean hideChat = false;
    private boolean diagnostics = false;
    private boolean resumed = false;
    private final Runnable statePoll = this::pollState;
    private final Handler handler = new Handler(Looper.getMainLooper());

    @SuppressLint("SetJavaScriptEnabled")
    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);
        diagnostics = "1".equals(metaData("tv.webwrap.diagnostics"));

        root = new FrameLayout(this);
        root.setBackgroundColor(Color.BLACK);
        loadNotice = new TextView(this);
        loadNotice.setTextColor(Color.WHITE);
        loadNotice.setBackgroundColor(0xee202020);
        loadNotice.setPadding(24, 18, 24, 18);
        loadNotice.setVisibility(View.GONE);

        web = new WebView(this);
        web.setBackgroundColor(Color.BLACK);
        web.setFocusable(true);
        web.setFocusableInTouchMode(true);

        WebSettings s = web.getSettings();
        s.setJavaScriptEnabled(true);
        s.setDomStorageEnabled(true);
        s.setDatabaseEnabled(true);
        s.setMediaPlaybackRequiresUserGesture(false);
        // Keep the actual engine identity; a spoofed Chrome version is not an update.
        s.setAllowFileAccess(false);
        s.setAllowContentAccess(false);
        s.setAllowFileAccessFromFileURLs(false);
        s.setAllowUniversalAccessFromFileURLs(false);
        s.setLoadWithOverviewMode(true);
        s.setUseWideViewPort(true);
        s.setSupportZoom(false);
        s.setBuiltInZoomControls(false);
        s.setCacheMode(WebSettings.LOAD_DEFAULT);
        s.setJavaScriptCanOpenWindowsAutomatically(false);
        s.setSupportMultipleWindows(true);
        s.setMixedContentMode("1".equals(metaData("tv.webwrap.legacyHttp"))
                ? WebSettings.MIXED_CONTENT_COMPATIBILITY_MODE
                : WebSettings.MIXED_CONTENT_NEVER_ALLOW);
        if (android.os.Build.VERSION.SDK_INT >= 26) s.setSafeBrowsingEnabled(true);

        CookieManager cm = CookieManager.getInstance();
        cm.setAcceptCookie(true);
        cm.setAcceptThirdPartyCookies(web,
                "1".equals(metaData("tv.webwrap.thirdPartyCookies")));

        web.setWebViewClient(new WebViewClient() {
            @Override
            public boolean shouldOverrideUrlLoading(WebView v, WebResourceRequest request) {
                Uri uri = request.getUrl();
                if (request.isForMainFrame() && !allowedNavigation(uri)) {
                    loadProblem("Link blocked: " + String.valueOf(uri.getHost())
                            + ". This app stays on its configured site.");
                    return true;
                }
                return request.isForMainFrame() ? false
                        : !("https".equalsIgnoreCase(uri.getScheme())
                        || ("http".equalsIgnoreCase(uri.getScheme())
                        && "1".equals(metaData("tv.webwrap.legacyHttp"))));
            }

            @Override
            public boolean shouldOverrideUrlLoading(WebView v, String url) {
                boolean blocked = !allowedNavigation(Uri.parse(url));
                if (blocked) loadProblem("This link opens another site and was blocked.");
                return blocked;
            }

            @Override
            public void onPageStarted(WebView v, String url, android.graphics.Bitmap icon) {
                loadNotice.setVisibility(View.GONE);
                Log.i(TAG, "PAGE_START " + (allowedNavigation(Uri.parse(url)) ? "approved" : "other"));
            }

            @Override
            public void onReceivedError(WebView v, WebResourceRequest request, WebResourceError error) {
                if (request.isForMainFrame()) {
                    Log.w(TAG, "PAGE_ERROR " + error.getErrorCode());
                    loadProblem("This page could not load. Hold MENU to reload.");
                }
            }

            @Override
            public void onReceivedHttpError(WebView v, WebResourceRequest request, WebResourceResponse response) {
                if (request.isForMainFrame()) {
                    Log.w(TAG, "PAGE_HTTP " + response.getStatusCode());
                    loadProblem("The website did not accept this request. Hold MENU to retry.");
                }
            }

            @Override
            public void onPageFinished(WebView v, String url) {
                Log.i(TAG, "PAGE_FINISHED " + (allowedNavigation(Uri.parse(url)) ? "approved" : "other"));
                if (!allowedNavigation(Uri.parse(url))) return;
                v.evaluateJavascript(POINTER, null);
                v.evaluateJavascript("window.__wwStrip=" + stripSandbox
                        + ";window.__wwChat=" + hideChat + ";", null);
                v.evaluateJavascript(EXTRAS, null);
                if (stripSandbox) {
                    js("window.__wwSandbox&&window.__wwSandbox()");
                }
                if (hideChat) {
                    js("window.__wwHideChat&&window.__wwHideChat()");
                }
                v.evaluateJavascript(
                        "(function(){return String(window.innerWidth)+','+String(window.innerHeight)})()",
                        value -> {
                            String raw = value == null ? "" : value.replace("\"", "");
                            try {
                                String[] wh = raw.split(",");
                                vw = Float.parseFloat(wh[0].trim());
                                vh = Float.parseFloat(wh[1].trim());
                                float s = web.getWidth() / vw;
                                if (s > 0.1f) {
                                    scale = s;
                                }
                            } catch (Exception ignored) {
                                // keep the previous scale
                            }
                            if (px <= 0 || py <= 0) {
                                centerPointer();
                            } else {
                                px = Math.min(px, vw - 2f);
                                py = Math.min(py, vh - 2f);
                                paintPointer();
                            }
                            trace( "VIEW " + vw + "x" + vh + " scale " + scale);
                        });
            }
        });

        web.setWebChromeClient(new WebChromeClient() {
            @Override
            public boolean onConsoleMessage(ConsoleMessage m) {
                String msg = m.message();
                // These sites dump megabytes of console output, which rotates the
                // logcat ring buffer and destroys the evidence. Log our own markers
                // and real errors only.
                if (msg != null && (msg.startsWith("PTR") || msg.startsWith("SCROLL")
                        || msg.startsWith("FULL") || msg.startsWith("MEDIA")
                        || msg.startsWith("CLICK") || msg.startsWith("HOVER")
                        || msg.startsWith("FRAMES") || msg.startsWith("SANDBOX") || msg.startsWith("CHAT")
                        || m.messageLevel() == ConsoleMessage.MessageLevel.ERROR)) {
                    // Never copy arbitrary page errors, URLs or tokens to logcat.
                    if (msg.matches("FULL frame-pin [0-9]+x[0-9]+ -> [0-9]+x[0-9]+|FULL off|FULL no-video and no frame|CHAT hidden [0-9]+|SANDBOX stripped [0-9]+ of [0-9]+")) {
                        trace(msg);
                    } else if (m.messageLevel() == ConsoleMessage.MessageLevel.ERROR) {
                        trace("page ERROR");
                    }
                }
                return true;
            }

            /**
             * The page asked for fullscreen. Prefer OUR container pin whenever a
             * <video> is reachable in this document.
             *
             * Why not the native view: onShowCustomView gets a bare media surface.
             * The site's control bar is DOM and is left behind (the "bottom cut
             * off" report), and that surface cannot be captured by screencap at
             * all, so any fix there is unverifiable. The pin keeps the player's own
             * DOM, uses object-fit:contain so nothing can clip, and is visible to
             * screencap. Only if no video is reachable (cross-origin iframe) do we
             * fall back to the native view.
             */
            @Override
            public void onShowCustomView(View view, final CustomViewCallback callback) {
                if (customView != null) {
                    callback.onCustomViewHidden();
                    return;
                }
                final View pending = view;
                web.evaluateJavascript(
                        "(function(){var v=window.__wwVideo?window.__wwVideo():null;"
                        + "if(v){if(!window.__wwFake){window.__wwToggleFull()}"
                        + "return window.__wwFake?'pinned':'none'}"
                        + "if(window.__wwFrameFull&&window.__wwFrameFull()){return 'framepin'}"
                        + "return 'none'})()",
                        value -> {
                            String r = value == null ? "" : value.replace("\"", "");
                            if (r.contains("pinned") || r.contains("framepin")) {
                                trace( "FULLSCREEN declined -> container pin (controls kept)");
                                try {
                                    callback.onCustomViewHidden();
                                } catch (Exception ignored) {
                                    // a build may reject the second hide
                                }
                                return;
                            }
                            trace( "FULLSCREEN accepted (native: no reachable video)");
                            customView = pending;
                            customCallback = callback;
                            root.addView(pending, new FrameLayout.LayoutParams(
                                    ViewGroup.LayoutParams.MATCH_PARENT,
                                    ViewGroup.LayoutParams.MATCH_PARENT));
                            web.setVisibility(View.GONE);
                            getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
                            immersive();
                            root.post(() -> trace( "FULLSCREEN native on view "
                                    + (customView == null ? 0 : customView.getWidth()) + "x"
                                    + (customView == null ? 0 : customView.getHeight())));
                        });
            }

            @Override
            public void onHideCustomView() {
                if (customView == null) {
                    return;
                }
                root.removeView(customView);
                customView = null;
                web.setVisibility(View.VISIBLE);
                if (customCallback != null) {
                    try {
                        customCallback.onCustomViewHidden();
                    } catch (Exception ignored) {
                        // callback can already be detached after a navigation
                    }
                    customCallback = null;
                }
                web.requestFocus();
                immersive();
                trace( "FULLSCREEN native off");
            }

            /** window.open / target=_blank: load it here instead of doing nothing. */
            @Override
            public boolean onCreateWindow(WebView view, boolean isDialog,
                                          boolean isUserGesture, Message resultMsg) {
                if (!isUserGesture) return false;
                WebView temp = new WebView(Main.this);
                temp.setWebViewClient(new WebViewClient() {
                    @Override
                    public boolean shouldOverrideUrlLoading(WebView v, String url) {
                        if (allowedNavigation(Uri.parse(url))) web.loadUrl(url);
                        temp.destroy();
                        return true;
                    }
                });
                WebView.WebViewTransport transport =
                        (WebView.WebViewTransport) resultMsg.obj;
                transport.setWebView(temp);
                resultMsg.sendToTarget();
                handler.postDelayed(() -> temp.destroy(), 10000);
                return true;
            }
        });

        root.addView(web, new FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT));
        root.addView(loadNotice, new FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));
        setContentView(root);

        web.requestFocus();
        immersive();
        stripSandbox = "1".equals(metaData("tv.webwrap.stripSandbox"));
        hideChat = "1".equals(metaData("tv.webwrap.hideChat"));
        trace( "HIDECHAT " + hideChat);
        trace( "STRIPSANDBOX " + stripSandbox);
        Log.i(TAG, "BUILD " + metaData("tv.webwrap.build"));
        web.loadUrl(home());
    }

    private void trace(String message) {
        if (diagnostics) Log.i(TAG, message);
    }

    private void loadProblem(String message) {
        loadNotice.setText(message);
        loadNotice.setVisibility(View.VISIBLE);
    }

    private String metaData(String key) {
        try {
            ActivityInfo ai = getPackageManager().getActivityInfo(
                    getComponentName(), PackageManager.GET_META_DATA);
            if (ai != null && ai.metaData != null) {
                Object v = ai.metaData.get(key);
                return v == null ? null : String.valueOf(v);
            }
        } catch (Exception ignored) {
            // no metadata
        }
        return null;
    }

    private boolean allowedNavigation(Uri uri) {
        return NavigationPolicy.allows(uri.toString(), home(), metaData("tv.webwrap.navigationHosts"));
    }

    private void siteMenu() {
        new AlertDialog.Builder(this).setTitle("Site settings")
                .setItems(new String[]{"Reload", "Clear site data"}, (dialog, which) -> {
                    if (which == 0) { web.reload(); return; }
                    new AlertDialog.Builder(this).setTitle("Clear site data?")
                            .setMessage("This signs you out, removes all local data in this app, and closes it. Reopen its tile afterward.")
                            .setNegativeButton("Cancel", null)
                            .setPositiveButton("Clear", (d, w) -> {
                                // OS clears cookies, IndexedDB, service workers and
                                // caches together, then terminates this app only.
                                ((ActivityManager) getSystemService(ACTIVITY_SERVICE))
                                        .clearApplicationUserData();
                            }).show();
                }).show();
    }

    private String home() {
        try {
            ActivityInfo ai = getPackageManager().getActivityInfo(
                    getComponentName(), PackageManager.GET_META_DATA);
            if (ai != null && ai.metaData != null) {
                String url = ai.metaData.getString("tv.webwrap.url");
                if (url != null && url.trim().length() > 0) {
                    return url.trim();
                }
            }
        } catch (Exception ignored) {
            // a manifest without the meta-data still launches, just at the default
        }
        return DEFAULT_HOME;
    }

    // ---------------------------------------------------------------- input

    /** Real tap. Routed by the browser, so it reaches inside iframes. */
    private void tap(float x, float y) {
        trace( "TAP " + Math.round(x) + "," + Math.round(y));
        if (stripSandbox) {
            // temporary: show what frames exist right after a click on an SPA page
            handler.postDelayed(() -> js("window.__wwFrames&&window.__wwFrames()"), 2500);
        }
        hover(x, y);                       // reveal whatever the tap is aimed at
        long now = SystemClock.uptimeMillis();
        MotionEvent down = MotionEvent.obtain(now, now, MotionEvent.ACTION_DOWN, x, y, 0);
        down.setSource(InputDevice.SOURCE_TOUCHSCREEN);
        web.dispatchTouchEvent(down);
        down.recycle();
        MotionEvent up = MotionEvent.obtain(now, now + 50, MotionEvent.ACTION_UP, x, y, 0);
        up.setSource(InputDevice.SOURCE_TOUCHSCREEN);
        web.dispatchTouchEvent(up);
        up.recycle();
    }

    /**
     * Real mouse hover at a point. This is what makes a web player show its
     * control bar — a synthetic JS mousemove does it in the top document only,
     * and the controls of an iframe player are in a different document.
     */
    private void hover(float x, float y) {
        long now = SystemClock.uptimeMillis();
        MotionEvent e = MotionEvent.obtain(now, now, MotionEvent.ACTION_HOVER_MOVE, x, y, 0);
        e.setSource(InputDevice.SOURCE_MOUSE);
        web.dispatchGenericMotionEvent(e);
        e.recycle();
    }

    private float cssWidth() {
        return vw > 0 ? vw : 960f;
    }

    private float cssHeight() {
        return vh > 0 ? vh : 540f;
    }

    private void centerPointer() {
        px = cssWidth() / 2f;
        py = cssHeight() / 2f;
        paintPointer();
        hover(px * scale, py * scale);
        trace( "PTR " + Math.round(px) + "," + Math.round(py));
    }

    private void paintPointer() {
        js(String.format(Locale.US, "window.__wwSet&&window.__wwSet(%f,%f)", px, py));
    }

    private void moveBy(int dx, int dy) {
        float maxX = cssWidth() - 2f;
        float maxY = cssHeight() - 2f;
        float nx = Math.max(2f, Math.min(maxX, px + dx));
        float ny = Math.max(2f, Math.min(maxY, py + dy));
        boolean stuckX = nx == px && (px <= 2f || px >= maxX);
        boolean stuckY = ny == py && (py <= 2f || py >= maxY);
        px = nx;
        py = ny;
        paintPointer();
        hover(px * scale, py * scale);
        if (stuckY) {
            js("window.__wwScroll(" + (dy > 0 ? 140 : -140) + ")");
        } else if (stuckX) {
            js("window.__wwScrollX(" + (dx > 0 ? 160 : -160) + ")");
        }
    }

    private void js(String code) {
        if (web != null) {
            web.evaluateJavascript(code, null);
        }
    }

    @Override
    public boolean dispatchKeyEvent(KeyEvent e) {
        if (e.getAction() != KeyEvent.ACTION_DOWN) {
            return handledKey(e.getKeyCode()) || super.dispatchKeyEvent(e);
        }
        int step = e.getRepeatCount() > 0 ? STEP + STEP / 2 : STEP;
        switch (e.getKeyCode()) {
            case KeyEvent.KEYCODE_DPAD_LEFT:
                moveBy(-step, 0); return true;
            case KeyEvent.KEYCODE_DPAD_RIGHT:
                moveBy(step, 0); return true;
            case KeyEvent.KEYCODE_DPAD_UP:
                moveBy(0, -step); return true;
            case KeyEvent.KEYCODE_DPAD_DOWN:
                moveBy(0, step); return true;
            case KeyEvent.KEYCODE_DPAD_CENTER:
            case KeyEvent.KEYCODE_ENTER:
            case KeyEvent.KEYCODE_NUMPAD_ENTER: {
                long now = SystemClock.uptimeMillis();
                tap(px * scale, py * scale);
                if (now - lastOkAt < DOUBLE_TAP_MS) {
                    js("window.__wwToggleFull()");
                    lastOkAt = 0;
                } else {
                    lastOkAt = now;
                }
                return true;
            }
            case KeyEvent.KEYCODE_MENU:
                if (e.getRepeatCount() == 1) siteMenu();
                else if (e.getRepeatCount() == 0) js("window.__wwToggleFull()");
                return true;
            case KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE:
                js("window.__wwPlayPause()");
                return true;
            case KeyEvent.KEYCODE_PAGE_DOWN:
            case KeyEvent.KEYCODE_MEDIA_NEXT:
            case KeyEvent.KEYCODE_CHANNEL_DOWN:
                js("window.__wwScroll(600)"); return true;
            case KeyEvent.KEYCODE_PAGE_UP:
            case KeyEvent.KEYCODE_MEDIA_PREVIOUS:
            case KeyEvent.KEYCODE_CHANNEL_UP:
                js("window.__wwScroll(-600)"); return true;
            case KeyEvent.KEYCODE_BACK:
                if (fakeFull) {
                    js("window.__wwToggleFull()");
                    fakeFull = false;
                    return true;
                }
                if (customView != null) {
                    js("if(document.exitFullscreen)document.exitFullscreen()");
                    return true;
                }
                if (web != null && web.canGoBack()) {
                    web.goBack();
                    return true;
                }
                return super.dispatchKeyEvent(e);
            default:
                return super.dispatchKeyEvent(e);
        }
    }

    private boolean handledKey(int code) {
        switch (code) {
            case KeyEvent.KEYCODE_DPAD_LEFT:
            case KeyEvent.KEYCODE_DPAD_RIGHT:
            case KeyEvent.KEYCODE_DPAD_UP:
            case KeyEvent.KEYCODE_DPAD_DOWN:
            case KeyEvent.KEYCODE_DPAD_CENTER:
            case KeyEvent.KEYCODE_ENTER:
            case KeyEvent.KEYCODE_NUMPAD_ENTER:
            case KeyEvent.KEYCODE_MENU:
            case KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE:
            case KeyEvent.KEYCODE_PAGE_DOWN:
            case KeyEvent.KEYCODE_PAGE_UP:
            case KeyEvent.KEYCODE_CHANNEL_DOWN:
            case KeyEvent.KEYCODE_CHANNEL_UP:
            case KeyEvent.KEYCODE_MEDIA_NEXT:
            case KeyEvent.KEYCODE_MEDIA_PREVIOUS:
                return true;
            default:
                return false;
        }
    }

    /**
     * Keeps the TV awake only while something is playing, and learns whether the
     * fake fullscreen pin is currently on so BACK can undo it.
     */
    private void pollState() {
        if (web == null || !resumed) {
            return;
        }
        web.evaluateJavascript(
                "(function(){var v=window.__wwVideo?window.__wwVideo():null;"
                + "var playing=!!(v&&!v.paused&&!v.ended&&v.readyState>2);"
                + "return (window.__wwFake?'F':'-')+(playing?'P':'p')})()",
                value -> {
                    String st = value == null ? "" : value.replace("\"", "");
                    fakeFull = st.indexOf('F') >= 0;
                    if (!resumed) return;
                    // Cross-origin playback cannot be inspected. Keep awake during
                    // explicit fullscreen, rather than mistaking it for paused video.
                    if (st.indexOf('P') >= 0 || fakeFull || customView != null) {
                        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
                    } else {
                        getWindow().clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
                    }
                });
        handler.postDelayed(statePoll, 2000);
    }

    @Override
    protected void onResume() {
        super.onResume();
        resumed = true;
        web.onResume();
        web.resumeTimers();
        handler.removeCallbacks(statePoll);
        pollState();
        if (web != null) {
            web.requestFocus();
        }
        immersive();
    }

    @Override
    protected void onPause() {
        resumed = false;
        handler.removeCallbacks(statePoll);
        getWindow().clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        web.pauseTimers();
        web.onPause();
        super.onPause();
    }

    @Override
    protected void onDestroy() {
        handler.removeCallbacksAndMessages(null);
        if (web != null) {
            web.destroy();
            web = null;
        }
        super.onDestroy();
    }

    private void immersive() {
        getWindow().getDecorView().setSystemUiVisibility(
                View.SYSTEM_UI_FLAG_LAYOUT_STABLE
                | View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
                | View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
                | View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                | View.SYSTEM_UI_FLAG_FULLSCREEN
                | View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY);
    }

    private static final String EXTRAS =
            "(function(){"
            // NTV injects its player iframe after a click (SPA route change, no page
            // load), so a one-shot strip on onPageFinished is too early. Watch instead.
            + "window.__wwSandbox=function(){"
            + "var n=0,seen=0;"
            // querySelectorAll does NOT pierce shadow roots, and these players commonly
            // build their iframe inside one — which is why the earlier strip found 0.
            + "function walk(root){"
            + "if(!root){return}"
            + "try{var fs=root.querySelectorAll('iframe,frame');"
            + "for(var i=0;i<fs.length;i++){var f=fs[i];seen++;"
            + "if(window.__wwStrip&&window.__wwSandboxHosts.indexOf(new URL(f.src,document.baseURI).hostname)>=0&&f.hasAttribute('sandbox')){f.removeAttribute('sandbox');n++}"
            + "try{if(f.contentDocument){walk(f.contentDocument)}}catch(e){}}}catch(e){}"
            + "try{var all=root.querySelectorAll('*');"
            + "for(var i=0;i<all.length;i++){if(all[i].shadowRoot){walk(all[i].shadowRoot)}}}catch(e){}}"
            + "walk(document);"
            + "if(n){console.log('SANDBOX stripped '+n+' of '+seen)}"
            + "return n};"
            // sweep on a timer too: frames and shadow roots appear long after load
            + "window.__wwSandboxHosts=[];" // No current wrapper requires a sandbox exception.
            + "try{if(window.__wwStrip&&!window.__wwSbT){window.__wwSbT=setInterval(function(){"
            + "window.__wwSandbox&&window.__wwSandbox()},1200)}}catch(e){};"
            // A cross-origin player frame cannot be inspected at all (contentDocument
            // throws), and native fullscreen hides the WebView that was drawing it —
            // which is the black spinner. So fullscreen the FRAME ELEMENT instead: the
            // WebView stays visible, the player keeps decoding, nothing is handed over.
            + "window.__wwBestFrame=function(){"
            + "var fs=[],best=null,bestA=0;"
            + "try{fs=[].slice.call(document.querySelectorAll('iframe,frame'))}catch(e){return null}"
            + "for(var i=0;i<fs.length;i++){var r=null;"
            + "try{r=fs[i].getBoundingClientRect()}catch(e){continue}"
            + "var a=r.width*r.height;"
            // never pick a chat frame as the player: the stacked twitch chat embed
            // can be BIGGER than the video frame (StreamEast: ~960x600 chat under
            // a ~960x335 player), and pinning it would fullscreen the chat instead
            + "var src=String(fs[i].src||fs[i].getAttribute('data-src')||'');"
            + "if(src.indexOf('twitch.tv/embed')>=0||src.indexOf('/chat')>=0||src.indexOf('chat.')>=0){continue}"
            + "if(r.width>200&&r.height>120&&a>bestA){bestA=a;best=fs[i]}}"
            + "return best};"
            + "window.__wwFrameFull=function(){"
            + "if(window.__wwFake){return true}"
            + "var f=window.__wwBestFrame();if(!f){return false}"
            + "var r=f.getBoundingClientRect();"
            + "if(!(r.width>0&&r.height>0)){return false}"
            // Pin the frame ELEMENT, not the page scale. Contain-zoom was a measured
            // no-op when the frame already spans the viewport width (it logged
            // 'FULL zoom x1.00 frame 960x335' on StreamEast and changed nothing).
            // The <iframe> lives in THIS document even when its contents are
            // cross-origin, so it can be fixed to the viewport directly: the inner
            // player relayouts into the full screen and keeps its own controls.
            + "var de=document.documentElement,b=document.body;"
            + "var saved=[{el:de,css:de.style.cssText}];"
            + "de.style.overflow='hidden';"
            + "if(b){saved.push({el:b,css:b.style.cssText});b.style.overflow='hidden'}"
            // hide every sibling up the ancestor chain so no header, premium banner
            // or chat frame stays visible behind or above the pinned player
            + "var n=f,depth=0;"
            + "while(n&&n!==de&&depth<14){"
            + "var p=null;try{p=n.parentElement}catch(e){}"
            + "if(!p||p===de){break}"
            + "try{var kids=p.children;"
            + "for(var i=0;i<kids.length;i++){var k=kids[i];"
            + "if(k===n||k.id==='__wwp'){continue}"
            + "if(!k.style||k.style.display==='none'){continue}"
            + "saved.push({el:k,css:k.style.cssText});"
            + "k.style.display='none'}}catch(e){}"
            + "n=p;depth++}"
            + "saved.push({el:f,css:f.style.cssText});"
            + "f.style.cssText='position:fixed!important;inset:0!important;margin:0!important;"
            + "width:100vw!important;height:100vh!important;max-width:100vw!important;"
            + "max-height:100vh!important;z-index:2147483646!important;background:#000!important;"
            + "border:0!important;transform:none!important';"
            // let the inner player's own fullscreen button reach onShowCustomView,
            // which declines the native surface and keeps this pin instead
            + "try{f.setAttribute('allowfullscreen','');"
            + "f.setAttribute('webkitallowfullscreen','')}catch(e){}"
            + "window.__wwFake={saved:saved};"
            + "if(window.__wwBlockFull){window.__wwBlockFull(true)}"
            + "var pw=document.getElementById('__wwp');if(pw){pw.style.display='none'}"
            + "var br=f.getBoundingClientRect();"
            + "console.log('FULL frame-pin '+Math.round(r.width)+'x'+Math.round(r.height)"
            + "+' -> '+Math.round(br.width)+'x'+Math.round(br.height));"
            + "return true};"
                        // StreamEast stacks its embedded Twitch chat under the player, taking the
            // vertical space the video needs. Remove the embed and its heading.
            + "window.__wwHideChat=function(){"
            + "var n=0;"
            + "function kill(el){try{if(el&&el.style&&!el.__wwHC){el.style.display='none';el.__wwHC=1;n++}}catch(e){}}"
            + "function tlen(el){try{var s=(el.innerText||el.textContent||'');return s.trim().length}catch(e){return 9999}}"
            + "function hasPlayer(el){try{if(el.querySelector&&el.querySelector('video')){return true}}catch(e){}return false}"
            + "function killUp(el){kill(el);var base=tlen(el);var p=null;try{p=el.parentElement}catch(e){}var i=0;"
            + "while(p&&i<2){var tx='';try{tx=((p.innerText||p.textContent)||'').toLowerCase()}catch(e){break}"
            + "var h=0;try{h=p.getBoundingClientRect().height||0}catch(e){}"
            + "var L=tlen(p);"
            + "if(hasPlayer(p)){break}"
            + "if(L>base+200){break}"
            + "if((tx.indexOf('live chat')>=0||tx.indexOf('join the conversation')>=0)&&h>0&&h<340&&L>0&&L<260){kill(p);try{p=p.parentElement}catch(e){break}i++}else{break}}}"
            + "try{var fs=document.querySelectorAll('iframe,frame');"
            + "for(var i=0;i<fs.length;i++){var s=String(fs[i].src||fs[i].getAttribute('data-src')||'');"
            + "if(s.indexOf('twitch.tv/embed')>=0||s.indexOf('/chat')>=0||s.indexOf('chat.')>=0){kill(fs[i])}}}catch(e){}"
            + "try{var all=document.querySelectorAll('div,section,aside,a,button');"
            + "for(var j=0;j<all.length;j++){var el=all[j];"
            + "var tx=String(el.textContent||'').trim().toLowerCase();"
            + "if(tx==='live chat'){killUp(el)}}}catch(e){}"
            + "if(n){console.log('CHAT hidden '+n)}"
            + "return n};"
            + "try{if(window.__wwChat&&!window.__wwChT){window.__wwChT=setInterval(function(){"
            + "window.__wwHideChat&&window.__wwHideChat()},1500)}}catch(e){};"
+ "})()";

    /**
     * JS side: cursor drawing (native events cannot draw), container scrolling,
     * and the fake-fullscreen / play-pause helpers. No click synthesis — that is
     * native now, so it reaches iframe players and counts as a user gesture.
     */
    private static final String POINTER =
            "(function(){"
            + "if(window.__wwp){return}window.__wwp=1;"
            + "var d=document.createElement('div');"
            + "d.id='__wwp';"
            + "d.style.cssText='position:fixed;left:0;top:0;width:20px;height:20px;"
            + "margin:-10px 0 0 -10px;border-radius:50%;border:2px solid #fff;"
            + "box-shadow:0 0 0 2px #000,0 0 12px rgba(0,0,0,.85);z-index:2147483647;"
            + "pointer-events:none;transition:transform .05s linear';"
            + "(document.documentElement||document.body).appendChild(d);"
            + "var x=Math.round((window.innerWidth||1280)/2),"
            + "y=Math.round((window.innerHeight||720)/2);"
            + "function paint(){d.style.transform='translate('+x+'px,'+y+'px)'}"
            + "window.__wwSet=function(nx,ny){x=nx;y=ny;paint()};"
            + "function root(){return document.scrollingElement||document.documentElement}"
            + "function finder(axis){"
            + "var n=document.elementFromPoint(x,y);"
            + "while(n&&n!==document.documentElement){"
            + "var st;try{st=window.getComputedStyle(n)}catch(e){st=null}"
            + "if(st){"
            + "if(axis==='y'&&(st.overflowY==='auto'||st.overflowY==='scroll')&&"
            + "n.scrollHeight>n.clientHeight+4){return n}"
            + "if(axis==='x'&&(st.overflowX==='auto'||st.overflowX==='scroll')&&"
            + "n.scrollWidth>n.clientWidth+4){return n}}"
            + "n=n.parentElement}"
            + "return root()}"
            + "window.__wwScroll=function(dy){"
            + "var s=finder('y'),before=s.scrollTop;s.scrollTop=before+dy;"
            + "if(Math.abs(s.scrollTop-before)<1&&s!==root()){"
            + "var r=root();before=r.scrollTop;r.scrollTop=before+dy}"
            + "console.log('SCROLL '+Math.round(before)+'->'+Math.round(s.scrollTop)+"
            + "' <'+(s.tagName||'?')+'>')};"
            + "window.__wwScrollX=function(dx){"
            + "var s=finder('x'),before=s.scrollLeft;s.scrollLeft=before+dx;"
            + "console.log('SCROLLX '+Math.round(before)+'->'+Math.round(s.scrollLeft)+"
            + "' <'+(s.tagName||'?')+'>')};"
            + "window.__wwAllDocs=function(){"
            + "var out=[document];"
            + "var fs=[];try{fs=[].slice.call(document.querySelectorAll('iframe,frame'))}catch(e){}"
            + "for(var i=0;i<fs.length;i++){try{var d=fs[i].contentDocument;if(d){out.push(d)}}catch(e){}}"
            + "return out};"
            + "window.__wwFrameEl=function(d){"
            + "if(!d||d===document){return null}"
            + "var fs=[];try{fs=[].slice.call(document.querySelectorAll('iframe,frame'))}catch(e){}"
            + "for(var i=0;i<fs.length;i++){try{if(fs[i].contentDocument===d){return fs[i]}}catch(e){}}"
            + "return null};"
            // frameXTV puts the player in a same-origin /embed/<id> iframe, so a
            // top-document querySelector('video') finds nothing. Search every
            // reachable document and prefer the one that is playing and largest.
            + "window.__wwVideo=function(){"
            + "var docs=window.__wwAllDocs();"
            + "var best=null,bestScore=-1;"
            + "for(var i=0;i<docs.length;i++){"
            + "var vs=[];try{vs=[].slice.call(docs[i].querySelectorAll('video'))}catch(e){}"
            + "for(var j=0;j<vs.length;j++){"
            + "var v=vs[j],r=null;try{r=v.getBoundingClientRect()}catch(e){continue}"
            + "var playing=(!v.paused&&!v.ended&&v.readyState>2);"
            + "var score=r.width*r.height*(playing?4:1);"
            + "if(score>bestScore){bestScore=score;best=v}}}"
            + "return best};"
            + "function playerBox(v){"
            + "var best=v,n=v.parentElement,i=0,vr=v.getBoundingClientRect();"
            + "while(n&&i<5){"
            + "var r=n.getBoundingClientRect();"
            + "if(r.width>0&&r.height>0&&r.width<=vr.width*1.4&&r.height<=vr.height*1.8){"
            + "var c=null;"
            + "try{c=n.querySelector('button,[role=button],input,[class*=control],[class*=Control]')}catch(e){}"
            + "if(c){best=n}}"
            + "n=n.parentElement;i++}"
            + "return best}"
            + "window.__wwBlockFull=function(on){"
            + "try{"
            + "if(on){"
            + "if(!window.__wwRF){window.__wwRF=Element.prototype.requestFullscreen||null;"
            + "window.__wwWRF=Element.prototype.webkitRequestFullscreen||null}"
            + "if(window.__wwRF){Element.prototype.requestFullscreen=function(){"
            + "console.log('FULL request blocked (pin active)');"
            + "return Promise.reject(new Error('pinned'))}}"
            + "if(window.__wwWRF){Element.prototype.webkitRequestFullscreen=function(){"
            + "console.log('FULL request blocked (pin active)')}}"
            // HTMLVideoElement.webkitEnterFullscreen bypasses requestFullscreen and
            // goes straight to the native custom view (bare video, no DOM controls).
            + "if(!window.__wwVE){window.__wwVE=(window.HTMLVideoElement&&"
            + "HTMLVideoElement.prototype.webkitEnterFullscreen)||null;"
            + "window.__wwVX=(window.HTMLVideoElement&&"
            + "HTMLVideoElement.prototype.webkitExitFullscreen)||null}"
            + "try{if(window.__wwVE){HTMLVideoElement.prototype.webkitEnterFullscreen=function(){"
            + "console.log('FULL video-fullscreen blocked (pin active)')}}"
            + "if(window.__wwVX){HTMLVideoElement.prototype.webkitExitFullscreen=function(){}}}catch(e){}"
            + "}else{"
            + "if(window.__wwRF){Element.prototype.requestFullscreen=window.__wwRF}"
            + "if(window.__wwWRF){Element.prototype.webkitRequestFullscreen=window.__wwWRF}"
            + "try{if(window.__wwVE){HTMLVideoElement.prototype.webkitEnterFullscreen=window.__wwVE}"
            + "if(window.__wwVX){HTMLVideoElement.prototype.webkitExitFullscreen=window.__wwVX}}catch(e){}"
            + "}"
            + "}catch(e){}};"
            + "window.__wwFrames=function(){"
            + "var fs=[],all=[];"
            + "try{fs=[].slice.call(document.querySelectorAll('iframe,frame'))}catch(e){}"
            + "for(var i=0;i<fs.length;i++){"
            + "var f=fs[i],same=false,nv=-1,loc='';"
            + "try{var d=f.contentDocument;"
            + "if(d){same=true;nv=d.querySelectorAll('video').length;"
            + "loc=(d.location&&d.location.href)||''}}catch(e){}"
            + "all.push('#'+i+' same='+same+' videos='+nv"
            + ") }"
            + "console.log('FRAMES '+fs.length+(all.length?' | '+all.join(' | '):''));"
            + "return fs.length};"
            + "window.__wwFake=null;"
            + "window.__wwToggleFull=function(){"
            + "if(window.__wwFake){"
            + "var f=window.__wwFake;window.__wwFake=null;"
            + "window.__wwBlockFull(false);"
            + "if(f.saved){for(var i=f.saved.length-1;i>=0;i--){"
            + "try{f.saved[i].el.style.cssText=f.saved[i].css}catch(e){}}}"
            + "d.style.display='block';"
            + "console.log('FULL off');return}"
            + "var v=window.__wwVideo();"
            + "if(!v){"
            + "if(window.__wwFrameFull&&window.__wwFrameFull()){return}"
            + "console.log('FULL no-video and no frame');"
            + "if(window.__wwFrames){window.__wwFrames()}return}"
            // Pin the player CONTAINER, not the bare <video>: a site with a custom
            // control bar keeps that bar in the DOM next to the video, and native
            // requestFullscreen() would hand only the raw <video> its own surface,
            // leaving the seek bar and buttons behind — which looks like the bottom
            // of the player being cut off.
            + "var box=playerBox(v);"
            + "var d2=(v.ownerDocument||document);"
            + "var de=d2.documentElement;"
            + "var saved=[{el:box,css:box.style.cssText},{el:v,css:v.style.cssText},"
            + "{el:de,css:de.style.cssText}];"
            + "de.style.overflow='hidden';"
            + "box.style.cssText='position:fixed!important;inset:0!important;margin:0!important;"
            + "width:100vw!important;height:100vh!important;max-width:100vw!important;"
            + "max-height:100vh!important;z-index:2147483646!important;background:#000!important;"
            + "overflow:hidden!important;transform:none!important';"
            + "v.style.cssText='width:100%!important;height:100%!important;max-width:100%!important;"
            + "max-height:100%!important;object-fit:contain!important;"
            + "object-position:center center!important;transform:none!important';"
            // if the video lives in a frame, the FRAME itself must fill the screen,
            // otherwise only the small embed box grows and the rest stays letterboxed
            + "var fe=window.__wwFrameEl(d2);"
            + "if(fe){saved.push({el:fe,css:fe.style.cssText});"
            + "fe.style.cssText='position:fixed!important;inset:0!important;margin:0!important;"
            + "width:100vw!important;height:100vh!important;max-width:100vw!important;"
            + "max-height:100vh!important;z-index:2147483646!important;border:0!important;"
            + "transform:none!important'}"
            + "d.style.display='none';"
            + "window.__wwBlockFull(true);"
            + "try{if(v.play){v.play()}}catch(e){}"
            + "var br=box.getBoundingClientRect(),vr=v.getBoundingClientRect();"
            + "console.log('FULL on <'+box.tagName+'>'+(fe?' in-frame':' top')"
            + "+' box '+Math.round(br.left)+','+Math.round(br.top)"
            + "+' '+Math.round(br.width)+'x'+Math.round(br.height)"
            + "+' vid '+Math.round(vr.width)+'x'+Math.round(vr.height));"
            + "window.__wwFake={saved:saved,v:v,vbox:box};};"
            + "window.__wwPlayPause=function(){"
            + "var v=window.__wwVideo();"
            + "if(!v){console.log('MEDIA no-video');return}"
            + "if(v.paused){v.play();console.log('MEDIA play')}"
            + "else{v.pause();console.log('MEDIA pause')}};"
            + "paint();console.log('PTR-READY '+Math.round(x)+','+Math.round(y));"
            + "})()";
}
