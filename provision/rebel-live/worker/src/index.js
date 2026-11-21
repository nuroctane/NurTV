// Rebel Live stable front door: https://iptv.nuroctane.xyz
//
// The VM can only publish Rebel Live through a localhost.run tunnel whose hostname changes on
// every restart. The VM watchdog writes the live tunnel origin into KV (key "origin"); this
// Worker makes that churn invisible to the TV:
//   /playlist, /epg  -> fetched from the tunnel (small text), tunnel origin rewritten to this
//                       host, so every stream link in it points here
//   anything else    -> 302 to the same path on the current tunnel (video never flows
//                       through the Worker)
// No key is stored here: the TV's request carries ?key=, which is passed through untouched.

const TEXT_PATHS = new Set(["/playlist", "/playlist.m3u", "/epg", "/epg.xml"]);

export default {
  async fetch(request, env) {
    const origin = (await env.REBEL.get("origin"))?.replace(/\/+$/, "");
    if (!origin) return new Response("Rebel Live origin not published yet", { status: 503 });

    const url = new URL(request.url);
    const target = origin + url.pathname + url.search;

    if (!TEXT_PATHS.has(url.pathname)) {
      return Response.redirect(target, 302);
    }

    const upstream = await fetch(target, { headers: { "User-Agent": request.headers.get("User-Agent") || "VLC/3.0.18" } });
    if (!upstream.ok) return new Response(`upstream ${upstream.status}`, { status: 502 });
    const tunnelHost = new URL(origin).host;
    const body = (await upstream.text()).replace(
      new RegExp(`https?://${tunnelHost.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}`, "g"),
      `${url.protocol}//${url.host}`,
    );
    return new Response(body, {
      headers: {
        "Content-Type": upstream.headers.get("Content-Type") || "application/x-mpegURL",
        "Cache-Control": "no-store",
      },
    });
  },
};
