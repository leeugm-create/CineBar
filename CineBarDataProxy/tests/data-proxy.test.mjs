import assert from "node:assert/strict";
import test from "node:test";

import worker, {
  omdbIMDbID,
  tmdbPathAllowed,
} from "../worker.js";

class MemoryCache {
  constructor() {
    this.entries = new Map();
    this.keys = [];
  }

  async match(request) {
    const key = request.url;
    this.keys.push(key);
    const response = this.entries.get(key);
    return response?.clone();
  }

  async put(request, response) {
    const key = request.url;
    this.keys.push(key);
    this.entries.set(key, response.clone());
  }
}

function context() {
  const promises = [];
  return {
    promises,
    waitUntil(promise) {
      promises.push(promise);
    },
  };
}

function environment(overrides = {}) {
  const requests = [];
  const cache = new MemoryCache();
  return {
    env: {
      TMDB_TOKEN: "test-tmdb-secret",
      OMDB_API_KEY: "test-omdb-secret",
      CACHE: cache,
      UPSTREAM_FETCHER: async (request, init = {}) => {
        const url = typeof request === "string" ? request : request.url;
        requests.push({ url, init });
        return new Response(JSON.stringify({ ok: true }), {
          status: 200,
          headers: { "content-type": "application/json" },
        });
      },
      ...overrides,
    },
    cache,
    requests,
  };
}

test("accepts only the intended TMDB paths", () => {
  assert.equal(tmdbPathAllowed("/movie/603"), true);
  assert.equal(tmdbPathAllowed("/tv/1399/credits"), true);
  assert.equal(tmdbPathAllowed("/configuration/countries"), true);
  assert.equal(tmdbPathAllowed("/configuration/jobs"), false);
  assert.equal(tmdbPathAllowed("/movie/../admin"), false);
});

test("accepts only one valid IMDb ID on the OMDb route", () => {
  assert.equal(
    omdbIMDbID(new URL("https://data.example/omdb?i=tt0133093")),
    "tt0133093",
  );
  assert.equal(
    omdbIMDbID(new URL("https://data.example/omdb?i=603")),
    null,
  );
  assert.equal(
    omdbIMDbID(
      new URL("https://data.example/omdb?i=tt0133093&apikey=stolen"),
    ),
    null,
  );
});

test("proxies TMDB with server authorization and caches the response", async () => {
  const { env, requests } = environment();
  const ctx = context();
  const request = new Request(
    "https://data.example/movie/603?language=zh-CN",
  );

  const first = await worker.fetch(request, env, ctx);
  await Promise.all(ctx.promises);
  const second = await worker.fetch(request, env, context());

  assert.equal(first.status, 200);
  assert.equal(first.headers.get("cache-control"), "public, max-age=900");
  assert.equal(second.status, 200);
  assert.equal(requests.length, 1);
  assert.equal(
    requests[0].url,
    "https://api.themoviedb.org/3/movie/603?language=zh-CN",
  );
  assert.equal(
    new Headers(requests[0].init.headers).get("authorization"),
    "Bearer test-tmdb-secret",
  );
});

test("proxies OMDb with a server-side key and credential-free cache key", async () => {
  const { env, requests, cache } = environment();
  const ctx = context();
  const incoming = "https://data.example/omdb?i=tt0133093";

  const first = await worker.fetch(new Request(incoming), env, ctx);
  await Promise.all(ctx.promises);
  const second = await worker.fetch(new Request(incoming), env, context());

  assert.equal(first.status, 200);
  assert.equal(first.headers.get("cache-control"), "public, max-age=21600");
  assert.equal(second.status, 200);
  assert.equal(requests.length, 1);
  assert.equal(
    requests[0].url,
    "https://www.omdbapi.com/?i=tt0133093&apikey=test-omdb-secret",
  );
  assert.equal(incoming.includes("test-omdb-secret"), false);
  assert.equal(
    cache.keys.some((key) => key.includes("test-omdb-secret")),
    false,
  );
});

test("rejects unsupported methods, paths, and OMDb queries", async () => {
  const { env } = environment();
  const cases = [
    new Request("https://data.example/movie/603", { method: "POST" }),
    new Request("https://data.example/configuration/jobs"),
    new Request("https://data.example/omdb?i=603"),
    new Request("https://data.example/omdb?i=tt0133093&apikey=client-key"),
  ];

  for (const request of cases) {
    const response = await worker.fetch(request, env, context());
    assert.ok(response.status === 400 || response.status === 404);
  }
});

test("reports missing secrets without calling upstream", async () => {
  const tmdb = environment({ TMDB_TOKEN: "" });
  const omdb = environment({ OMDB_API_KEY: "" });

  assert.equal(
    (await worker.fetch(
      new Request("https://data.example/movie/603"),
      tmdb.env,
      context(),
    )).status,
    503,
  );
  assert.equal(
    (await worker.fetch(
      new Request("https://data.example/omdb?i=tt0133093"),
      omdb.env,
      context(),
    )).status,
    503,
  );
  assert.equal(tmdb.requests.length, 0);
  assert.equal(omdb.requests.length, 0);
});

test("does not cache upstream failures", async () => {
  const cache = new MemoryCache();
  const env = {
    TMDB_TOKEN: "test-tmdb-secret",
    OMDB_API_KEY: "test-omdb-secret",
    CACHE: cache,
    UPSTREAM_FETCHER: async () => new Response("failure", { status: 502 }),
  };
  const ctx = context();

  const response = await worker.fetch(
    new Request("https://data.example/movie/603"),
    env,
    ctx,
  );

  assert.equal(response.status, 502);
  assert.equal(response.headers.get("cache-control"), "no-store");
  assert.equal(ctx.promises.length, 0);
  assert.equal(cache.entries.size, 0);
});

test("reports data service health without calling an upstream", async () => {
  let upstreamCalls = 0;
  const response = await worker.fetch(
    new Request("https://api.cinebar.cc/health"),
    {
      UPSTREAM_FETCHER: async () => {
        upstreamCalls += 1;
        throw new Error("must not be called");
      },
    },
    context(),
  );
  const body = await response.json();

  assert.equal(response.status, 200);
  assert.equal(body.ok, true);
  assert.equal(body.service, "cinebar-data");
  assert.equal(body.version, "0.8.2-test.2");
  assert.match(body.utc, /^\d{4}-\d{2}-\d{2}T/);
  assert.equal(upstreamCalls, 0);
  assert.equal(JSON.stringify(body).includes("TOKEN"), false);
  assert.equal(response.headers.get("cache-control"), "no-store");
});
