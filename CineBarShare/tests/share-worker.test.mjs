import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

import worker, { mediaPath } from "../worker.js";

const config = JSON.parse(
  readFileSync(new URL("../wrangler.jsonc", import.meta.url), "utf8"),
);

const movieMetadata = {
  id: 603,
  title: "The Matrix",
  overview: "A computer hacker discovers the truth.",
  poster_path: "/matrix.jpg",
  release_date: "1999-03-30",
  vote_average: 8.2,
};

const tvMetadata = {
  id: 1399,
  name: "Game of Thrones",
  overview: "Nine noble families fight for control.",
  poster_path: "/game-of-thrones.jpg",
  first_air_date: "2011-04-17",
  vote_average: 8.5,
};

const movieCast = [
  { name: "Keanu Reeves", character: "Neo" },
  { name: "Carrie-Anne Moss", character: "Trinity" },
  { name: "Laurence Fishburne", character: "Morpheus" },
  { name: "Hugo Weaving", character: "Agent Smith" },
  { name: "Gloria Foster", character: "Oracle" },
  { name: "Joe Pantoliano", character: "Cypher" },
  { name: "Should Not Render", character: "Seventh" },
];

const tvCast = [
  { name: "Emilia Clarke", character: "Daenerys Targaryen" },
  { name: "Kit Harington", character: "Jon Snow" },
];

const maliciousMovieCast = [
  { name: "<script>alert(1)</script>", character: "<script>role</script>" },
];

const metadataFetcher = async (requestURL) => {
  const url = String(requestURL);
  if (url.includes("/credits")) {
    return new Response(JSON.stringify({
      cast: url.includes("/movie/") ? movieCast : tvCast,
    }), {
      status: 200,
      headers: { "content-type": "application/json" },
    });
  }
  const payload = url.includes("/movie/") ? movieMetadata : tvMetadata;
  return new Response(JSON.stringify(payload), {
    status: 200,
    headers: { "content-type": "application/json" },
  });
};

const fetchPage = (path, overrides = {}) =>
  worker.fetch(
    new Request(`https://share.example${path}`),
    {
      TMDB_BEARER_TOKEN: "test-token",
      MEDIA_FETCHER: metadataFetcher,
      ...overrides,
    },
  );

test("recognizes only permanent movie and television short routes", () => {
  assert.deepEqual(mediaPath("/m/603"), {
    mediaType: "movie",
    mediaID: 603,
  });
  assert.deepEqual(mediaPath("/t/1399"), {
    mediaType: "tv",
    mediaID: 1399,
  });
  assert.equal(mediaPath("/m/not-a-number"), null);
  assert.equal(mediaPath("/share/movies/603"), null);
});

test("renders movie metadata at a canonical short URL", async () => {
  const response = await fetchPage(
    "/m/603?title=Injected&summary=Wrong",
  );
  const html = await response.text();

  assert.equal(response.status, 200);
  assert.match(html, /The Matrix/);
  assert.match(html, /主要演员/);
  assert.match(html, /Keanu Reeves/);
  assert.match(html, /饰 Neo/);
  assert.doesNotMatch(html, /Should Not Render/);
  assert.match(
    html,
    /<meta name="description" content="主演：Keanu Reeves、Carrie-Anne Moss、Laurence Fishburne、Hugo Weaving、Gloria Foster、Joe Pantoliano。A computer hacker discovers the truth\.">/,
  );
  assert.match(
    html,
    /property="og:description" content="主演：Keanu Reeves、Carrie-Anne Moss、Laurence Fishburne、Hugo Weaving、Gloria Foster、Joe Pantoliano。A computer hacker discovers the truth\."/,
  );
  assert.match(
    html,
    /name="twitter:description" content="主演：Keanu Reeves、Carrie-Anne Moss、Laurence Fishburne、Hugo Weaving、Gloria Foster、Joe Pantoliano。A computer hacker discovers the truth\."/,
  );
  assert.match(html, /<title>《The Matrix》— CineBar<\/title>/);
  assert.match(
    html,
    /property="og:url" content="https:\/\/share\.example\/m\/603"/,
  );
  assert.doesNotMatch(html, /Injected|Wrong/);
});

test("escapes malicious cast member markup", async () => {
  const response = await fetchPage("/m/603", {
    MEDIA_FETCHER: async (requestURL) => {
      if (String(requestURL).includes("/credits")) {
        return new Response(JSON.stringify({ cast: maliciousMovieCast }), {
          status: 200,
          headers: { "content-type": "application/json" },
        });
      }
      return metadataFetcher(requestURL);
    },
  });
  const html = await response.text();

  assert.equal(response.status, 200);
  assert.match(html, /&lt;script&gt;/);
  assert.doesNotMatch(html, /<script>/);
});

test("keeps the share page when credits fail", async () => {
  const response = await fetchPage("/m/603", {
    MEDIA_FETCHER: async (requestURL) => {
      if (String(requestURL).includes("/credits")) {
        return new Response("upstream error", { status: 503 });
      }
      return metadataFetcher(requestURL);
    },
  });
  const html = await response.text();

  assert.equal(response.status, 200);
  assert.match(html, /The Matrix/);
  assert.doesNotMatch(html, /主要演员/);
});

test("renders television metadata at a canonical short URL", async () => {
  const response = await fetchPage("/t/1399");
  const html = await response.text();

  assert.equal(response.status, 200);
  assert.match(html, /Game of Thrones/);
  assert.match(
    html,
    /property="og:url" content="https:\/\/share\.example\/t\/1399"/,
  );
});

test("hides download control until a valid HTTPS URL is configured", async () => {
  const withoutDownload = await fetchPage("/m/603");
  const htmlWithoutDownload = await withoutDownload.text();
  assert.doesNotMatch(htmlWithoutDownload, /查看 CineBar 版本与下载/);

  const withDownload = await fetchPage("/m/603", {
    CINEBAR_DOWNLOAD_URL:
      "https://github.com/leeugm-create/CineBar/releases",
  });
  const htmlWithDownload = await withDownload.text();
  assert.match(htmlWithDownload, /查看 CineBar 版本与下载/);
  assert.match(
    htmlWithDownload,
    /https:\/\/github\.com\/leeugm-create\/CineBar\/releases/,
  );

  const invalidDownload = await fetchPage("/m/603", {
    CINEBAR_DOWNLOAD_URL: "javascript:alert(1)",
  });
  assert.doesNotMatch(
    await invalidDownload.text(),
    /查看 CineBar 版本与下载/,
  );
});

test("returns a branded fallback page when metadata is unavailable", async () => {
  const response = await fetchPage("/m/603", {
    MEDIA_FETCHER: async () => {
      throw new Error("upstream unavailable");
    },
  });
  const html = await response.text();

  assert.equal(response.status, 200);
  assert.match(html, /CineBar/);
  assert.match(html, /电影 #603/);
  assert.match(html, /影片资料暂时无法加载/);
});

test("reports share service health", async () => {
  const response = await fetchPage("/health");
  const body = await response.json();

  assert.equal(response.status, 200);
  assert.equal(body.ok, true);
  assert.equal(body.service, "cinebar-share");
  assert.equal(body.version, "0.8.2-test.2");
  assert.match(body.utc, /^\d{4}-\d{2}-\d{2}T/);
  assert.equal(response.headers.get("cache-control"), "no-store");
});

test("redirects plain HTTP requests to the same HTTPS URL", async () => {
  const response = await worker.fetch(
    new Request("http://cinebar.cc/m/603?source=test"),
    {
      TMDB_BEARER_TOKEN: "test-token",
      MEDIA_FETCHER: metadataFetcher,
    },
  );

  assert.equal(response.status, 308);
  assert.equal(
    response.headers.get("location"),
    "https://cinebar.cc/m/603?source=test",
  );
});

test("publishes the Build 17 GitHub Releases migration manifest", async () => {
  const response = await fetchPage("/updates/latest.json");
  const body = await response.json();

  assert.equal(response.status, 200);
  assert.equal(body.version, "0.8.3");
  assert.equal(body.build, 17);
  assert.equal(
    body.download_url,
    "https://github.com/leeugm-create/CineBar/releases",
  );
});

test("renders a lightweight CineBar root page", async () => {
  const response = await fetchPage("/");
  const html = await response.text();

  assert.equal(response.status, 200);
  assert.match(html, /CineBar/);
  assert.match(html, /今晚看什么/);
  assert.match(html, /电影与电视剧发现工具/);
  assert.doesNotMatch(html, /workers\.dev/);
});

test("keeps only the public share hostname", () => {
  const patterns = config.routes.map((route) => route.pattern);
  assert.deepEqual(patterns, ["share.cinebar.cc"]);
  assert.equal(config.routes[0].custom_domain, true);
});
