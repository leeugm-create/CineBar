import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const read = (path) => readFile(new URL(`../${path}`, import.meta.url), "utf8");

test("search supports mobile inline playback without URL navigation", async () => {
  const search = await read("app/site-search.tsx");
  const player = await read("app/inline-player.tsx");

  assert.match(search, /matchMedia\(["']\(max-width: 560px\)/);
  assert.match(search, /InlinePlayer/);
  assert.match(player, /preload=["']none["']/);
  assert.match(player, /https:/);
  assert.match(player, /暂无可在线播放源|playerNoSource/);
  assert.doesNotMatch(search, /window\.location/);
});

test("mobile homepage has a scoped search-first layout", async () => {
  const home = await read("app/home.tsx");
  const css = await read("app/globals.css");

  assert.match(home, /className=["']site-home["']/);
  assert.match(css, /\.site-home[^{]*\.site-header/);
  assert.match(css, /\.site-home[^{]*\.search-panel/);
  assert.match(css, /\.inline-player-card/);
  assert.match(css, /aspect-ratio:\s*16\s*\/\s*9/);
});

test("targets legacy mobile WebViews for media-query compatibility", async () => {
  const vite = await read("vite.config.ts");

  assert.match(vite, /target:\s*\[/);
  assert.match(vite, /["']safari13["']/);
  assert.match(vite, /["']ios13["']/);
  assert.match(vite, /["']chrome80["']/);
});

test("mobile homepage keeps only the brand and search surface", async () => {
  const home = await read("app/home.tsx");
  const i18n = await read("app/i18n.ts");
  const css = await read("app/globals.css");

  assert.match(home, /className=["']mobile-search-stack["']/);
  assert.match(home, /className=["']mobile-search-lede["']/);
  assert.match(i18n, /mobileSearchLede:/);
  assert.match(
    css,
    /\.site-home \.hero,\s*\.site-home \.section,\s*\.site-home footer\s*\{\s*display:\s*none/,
  );
  assert.match(css, /\.site-home \.site-header[\s\S]*\.site-home \.site-search/);
  assert.match(css, /\.site-home \.mobile-search-stack\s*\{[\s\S]*justify-content:\s*center/);
  assert.match(css, /\.site-home \.search-toggle\s*\{[\s\S]*width:\s*64px[\s\S]*height:\s*64px/);
});
