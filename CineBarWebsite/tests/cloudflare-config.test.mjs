import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const read = (path) =>
  readFile(new URL(`../${path}`, import.meta.url), "utf8");

const parseJsonc = (source) => JSON.parse(source);

test("deploys the reviewed vinext outputs as an isolated Worker", async () => {
  const config = parseJsonc(await read("wrangler.public.jsonc"));
  assert.equal(config.name, "cinebar-website");
  assert.equal(config.main, "dist/server/index.js");
  assert.equal(config.compatibility_date, "2026-05-15");
  assert.deepEqual(config.compatibility_flags, ["nodejs_compat"]);
  assert.equal(config.no_bundle, true);
  assert.equal(config.workers_dev, true);
  assert.equal(config.preview_urls, true);
  assert.deepEqual(config.rules, [
    {
      type: "ESModule",
      globs: ["**/*.js", "**/*.mjs"],
    },
  ]);
  assert.equal(config.assets.directory, "dist/client");
  assert.equal(config.observability.enabled, true);
  assert.equal(config.route, undefined);
  assert.equal(config.routes, undefined);
});

test("package scripts build before dry-run or deployment", async () => {
  const packageJson = JSON.parse(await read("package.json"));
  assert.equal(
    packageJson.scripts["deploy:dry-run"],
    "npm run build && wrangler deploy --config wrangler.public.jsonc --dry-run --outdir .wrangler/public-dry-run",
  );
  assert.equal(
    packageJson.scripts["deploy:public"],
    "npm run build && wrangler deploy --config wrangler.public.jsonc",
  );
});
