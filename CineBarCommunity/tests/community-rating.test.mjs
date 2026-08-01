import test from "node:test";
import assert from "node:assert/strict";

import {
  default as worker,
  normalizeMediaType,
  normalizeScore,
  ratingPath,
} from "../worker.js";

class MemoryD1 {
  constructor() {
    this.rows = new Map();
  }

  prepare(sql) {
    return new MemoryStatement(this, sql.replace(/\s+/g, " ").trim());
  }
}

class MemoryStatement {
  constructor(database, sql) {
    this.database = database;
    this.sql = sql;
    this.values = [];
  }

  bind(...values) {
    this.values = values;
    return this;
  }

  async first() {
    if (this.sql.startsWith("SELECT ROUND(AVG(score)")) {
      const [mediaType, mediaID] = this.values;
      const scores = [...this.database.rows.values()]
        .filter((row) =>
          row.mediaType === mediaType && row.mediaID === mediaID)
        .map((row) => row.score);
      return {
        average_score: scores.length === 0
          ? null
          : Math.round(
              scores.reduce((total, score) => total + score, 0) /
                scores.length *
                10,
            ) / 10,
        total: scores.length,
      };
    }
    if (this.sql.startsWith("SELECT score FROM ratings")) {
      const [mediaType, mediaID, deviceHash] = this.values;
      const row = this.database.rows.get(
        `${mediaType}:${mediaID}:${deviceHash}`,
      );
      return row ? { score: row.score } : null;
    }
    throw new Error(`Unsupported first query: ${this.sql}`);
  }

  async run() {
    if (this.sql.startsWith("INSERT INTO ratings")) {
      const [
        mediaType,
        mediaID,
        deviceHash,
        score,
        createdAt,
        updatedAt,
      ] = this.values;
      const key = `${mediaType}:${mediaID}:${deviceHash}`;
      const existing = this.database.rows.get(key);
      if (existing && !this.sql.includes("ON CONFLICT")) {
        throw new Error("UNIQUE constraint failed: ratings");
      }
      this.database.rows.set(key, {
        mediaType,
        mediaID,
        deviceHash,
        score,
        createdAt: existing?.createdAt ?? createdAt,
        updatedAt,
      });
      return { success: true };
    }
    if (this.sql.startsWith("DELETE FROM ratings")) {
      const [mediaType, mediaID, deviceHash] = this.values;
      this.database.rows.delete(`${mediaType}:${mediaID}:${deviceHash}`);
      return { success: true };
    }
    throw new Error(`Unsupported run query: ${this.sql}`);
  }
}

const ratingRequest = (method, mediaType, mediaID, score) =>
  new Request(
    `https://cinebar.test/v1/${mediaType}/${mediaID}/rating`,
    {
      method,
      headers: {
        "content-type": "application/json",
        "x-cinebar-device": "test-installation",
      },
      body: score == null ? undefined : JSON.stringify({ score }),
    },
  );

const testEnvironment = () => ({
  DB: new MemoryD1(),
  DEVICE_SALT: "test-salt",
});

test("accepts movie and tv media types", () => {
  assert.equal(normalizeMediaType("movie"), "movie");
  assert.equal(normalizeMediaType("tv"), "tv");
  assert.equal(normalizeMediaType("person"), null);
});

test("accepts zero through ten in half-point increments", () => {
  for (const score of [0, 0.5, 4, 8.5, 10]) {
    assert.equal(normalizeScore(score), score);
  }
  for (const score of [-0.5, 0.1, 10.5, "8.5", null]) {
    assert.equal(normalizeScore(score), null);
  }
});

test("uses one stable endpoint shape for movies and television", () => {
  assert.deepEqual(
    ratingPath("/v1/movie/603/rating"),
    { mediaType: "movie", mediaID: 603 },
  );
  assert.deepEqual(
    ratingPath("/v1/tv/1399/rating"),
    { mediaType: "tv", mediaID: 1399 },
  );
  assert.equal(ratingPath("/v1/person/1/rating"), null);
});

test("accepts the first anonymous score for movies and television", async (t) => {
  for (const mediaType of ["movie", "tv"]) {
    await t.test(mediaType, async () => {
      const env = testEnvironment();
      const response = await worker.fetch(
        ratingRequest("POST", mediaType, 603, 8),
        env,
      );
      const payload = await response.json();

      assert.equal(response.status, 200);
      assert.equal(payload.my_score, 8);
      assert.equal(payload.average_score, 8);
      assert.equal(payload.total, 1);
    });
  }
});

test("rejects a repeated score and preserves the original value", async () => {
  const env = testEnvironment();
  const first = await worker.fetch(
    ratingRequest("POST", "movie", 603, 8),
    env,
  );
  assert.equal(first.status, 200);

  const repeated = await worker.fetch(
    ratingRequest("POST", "movie", 603, 3),
    env,
  );
  const repeatedPayload = await repeated.json();
  assert.equal(repeated.status, 409);
  assert.equal(repeatedPayload.code, "already_rated");

  const summary = await worker.fetch(
    ratingRequest("GET", "movie", 603),
    env,
  );
  const summaryPayload = await summary.json();
  assert.equal(summaryPayload.my_score, 8);
  assert.equal(summaryPayload.average_score, 8);
  assert.equal(summaryPayload.total, 1);
});

test("does not expose a rating deletion route", async () => {
  const env = testEnvironment();
  await worker.fetch(
    ratingRequest("POST", "tv", 1399, 9),
    env,
  );

  const response = await worker.fetch(
    ratingRequest("DELETE", "tv", 1399),
    env,
  );
  assert.equal(response.status, 405);

  const summary = await worker.fetch(
    ratingRequest("GET", "tv", 1399),
    env,
  );
  const payload = await summary.json();
  assert.equal(payload.my_score, 9);
});

test("reports community service health without querying D1", async () => {
  const response = await worker.fetch(
    new Request("https://community.cinebar.cc/health"),
    {},
  );
  const body = await response.json();

  assert.equal(response.status, 200);
  assert.equal(body.ok, true);
  assert.equal(body.service, "cinebar-community");
  assert.equal(body.version, "0.8.2-test.2");
  assert.match(body.utc, /^\d{4}-\d{2}-\d{2}T/);
  assert.equal(response.headers.get("cache-control"), "no-store");
});
