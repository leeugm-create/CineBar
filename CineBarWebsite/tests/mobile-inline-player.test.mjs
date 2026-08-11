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
