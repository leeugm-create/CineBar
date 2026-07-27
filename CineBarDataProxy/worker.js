const allowedPrefixes = [
  "/trending/",
  "/search/",
  "/discover/",
  "/movie/",
  "/tv/",
  "/person/",
];

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    if (url.pathname === "/") {
      return new Response("CineBar Data Proxy is running.");
    }
    if (request.method !== "GET" ||
        !allowedPrefixes.some((prefix) => url.pathname.startsWith(prefix)) ||
        url.pathname.includes("..")) {
      return new Response("Not found", { status: 404 });
    }
    if (!env.TMDB_TOKEN) {
      return new Response("Server is not configured", { status: 503 });
    }

    const upstreamURL = new URL(
      `https://api.themoviedb.org/3${url.pathname}${url.search}`,
    );
    const cache = caches.default;
    const cacheKey = new Request(upstreamURL, { method: "GET" });
    const cached = await cache.match(cacheKey);
    if (cached) return cached;

    const upstream = await fetch(upstreamURL, {
      headers: {
        Authorization: `Bearer ${env.TMDB_TOKEN}`,
        Accept: "application/json",
      },
    });
    const response = new Response(upstream.body, upstream);
    response.headers.set("cache-control", upstream.ok
      ? "public, max-age=900"
      : "no-store");
    response.headers.set("x-content-type-options", "nosniff");
    if (upstream.ok) ctx.waitUntil(cache.put(cacheKey, response.clone()));
    return response;
  },
};
