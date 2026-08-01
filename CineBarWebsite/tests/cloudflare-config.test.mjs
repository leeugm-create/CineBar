import test from "node:test";
import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import { readFile } from "node:fs/promises";
import { promisify } from "node:util";

const read = (path) =>
  readFile(new URL(`../${path}`, import.meta.url), "utf8");
const execFileAsync = promisify(execFile);
const websiteRoot = new URL("..", import.meta.url);

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
  assert.equal(config.assets.binding, "ASSETS");
  assert.equal(config.assets.run_worker_first, true);
  assert.equal(config.observability.enabled, true);
  assert.equal(config.route, undefined);
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

test("owns only the CineBar apex custom domain after cutover", async () => {
  const config = parseJsonc(await read("wrangler.public.jsonc"));
  assert.deepEqual(config.routes, [
    { pattern: "cinebar.cc", custom_domain: true },
  ]);
});

test("lint ignores Wrangler's generated dry-run output", async () => {
  await execFileAsync("npm", ["run", "lint"], {
    cwd: websiteRoot,
    env: { ...process.env, NO_COLOR: "1" },
  });
});
