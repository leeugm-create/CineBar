const allowedPrefixes = [
  "/trending/",
  "/search/",
  "/discover/",
  "/movie/",
  "/tv/",
  "/person/",
];

export const tmdbPathAllowed = (pathname) =>
  !pathname.includes("..") &&
  (pathname === "/configuration/countries" ||
    allowedPrefixes.some((prefix) => pathname.startsWith(prefix)));

export const omdbIMDbID = (url) => {
  if (url.pathname !== "/omdb") return null;
  if ([...url.searchParams.keys()].some((key) => key !== "i")) return null;
  const imdbID = url.searchParams.get("i") ?? "";
  return /^tt\d{7,10}$/.test(imdbID) ? imdbID : null;
};

function proxiedResponse(upstream, maxAge) {
  const response = new Response(upstream.body, upstream);
  response.headers.set(
    "cache-control",
    upstream.ok ? `public, max-age=${maxAge}` : "no-store",
  );
  response.headers.set("x-content-type-options", "nosniff");
  return response;
}

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    if (url.pathname === "/") {
      return new Response("CineBar Data Proxy is running.");
    }
    if (request.method !== "GET") {
      return new Response("Not found", { status: 404 });
    }

    const fetcher = env.UPSTREAM_FETCHER ?? fetch;
    const cache = env.CACHE ?? caches.default;
    const imdbID = omdbIMDbID(url);

    if (url.pathname === "/omdb") {
      if (!imdbID) {
        return new Response("Invalid IMDb ID", { status: 400 });
      }
      if (!env.OMDB_API_KEY) {
        return new Response("Server is not configured", { status: 503 });
      }

      const cacheURL = new URL("/omdb", url.origin);
      cacheURL.searchParams.set("i", imdbID);
      const cacheKey = new Request(cacheURL, { method: "GET" });
      const cached = await cache.match(cacheKey);
      if (cached) return cached;

      const upstreamURL = new URL("https://www.omdbapi.com/");
      upstreamURL.searchParams.set("i", imdbID);
      upstreamURL.searchParams.set("apikey", env.OMDB_API_KEY);
      const upstream = await fetcher(upstreamURL.toString(), {
        headers: { Accept: "application/json" },
      });
      const response = proxiedResponse(upstream, 21600);
      if (upstream.ok) {
        ctx.waitUntil(cache.put(cacheKey, response.clone()));
      }
      return response;
    }

    if (!tmdbPathAllowed(url.pathname)) {
      return new Response("Not found", { status: 404 });
    }
    if (!env.TMDB_TOKEN) {
      return new Response("Server is not configured", { status: 503 });
    }

    const upstreamURL = new URL(
      `https://api.themoviedb.org/3${url.pathname}${url.search}`,
    );
    const cacheKey = new Request(url, { method: "GET" });
    const cached = await cache.match(cacheKey);
    if (cached) return cached;

    const upstream = await fetcher(upstreamURL.toString(), {
      headers: {
        Authorization: `Bearer ${env.TMDB_TOKEN}`,
        Accept: "application/json",
      },
    });
    const response = proxiedResponse(upstream, 900);
    if (upstream.ok) {
      ctx.waitUntil(cache.put(cacheKey, response.clone()));
    }
    return response;
  },
};
