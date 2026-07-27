import test from "node:test";
import assert from "node:assert/strict";

import {
  normalizeMediaType,
  normalizeScore,
  ratingPath,
} from "../worker.js";

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
