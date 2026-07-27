import test from "node:test";
import assert from "node:assert/strict";

import worker, { mediaPath } from "../worker.js";

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

const metadataFetcher = async (requestURL) => {
  const url = String(requestURL);
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
  assert.match(
    html,
    /property="og:url" content="https:\/\/share\.example\/m\/603"/,
  );
  assert.doesNotMatch(html, /Injected|Wrong/);
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
  assert.doesNotMatch(htmlWithoutDownload, /下载 CineBar for macOS/);

  const withDownload = await fetchPage("/m/603", {
    CINEBAR_DOWNLOAD_URL: "https://download.example/CineBar.zip",
  });
  const htmlWithDownload = await withDownload.text();
  assert.match(htmlWithDownload, /下载 CineBar for macOS/);
  assert.match(
    htmlWithDownload,
    /https:\/\/download\.example\/CineBar\.zip/,
  );

  const invalidDownload = await fetchPage("/m/603", {
    CINEBAR_DOWNLOAD_URL: "javascript:alert(1)",
  });
  assert.doesNotMatch(
    await invalidDownload.text(),
    /下载 CineBar for macOS/,
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
