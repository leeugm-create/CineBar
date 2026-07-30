import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const read = (path) => readFile(new URL(`../${path}`, import.meta.url), "utf8");

test("publishes the approved CineBar identity and download entry", async () => {
  const page = await read("app/page.tsx");
  assert.match(page, /今晚看什么？/);
  assert.match(page, /macOS 菜单栏/);
  assert.match(page, /测试版/);
  assert.match(
    page,
    /https:\/\/github\.com\/leeugm-create\/CineBar\/releases/,
  );
  assert.match(page, /免费/);
  assert.match(page, /无广告/);
  assert.match(page, /无订阅/);
  assert.match(page, /https:\/\/www\.paypal\.com\/cgi-bin\/webscr/);
  assert.match(page, /VVVZUSU9QUJBW/);
});

test("contains accessible navigation and all required sections", async () => {
  const page = await read("app/page.tsx");
  for (const id of ["features", "install", "privacy", "support"]) {
    assert.match(page, new RegExp(`id=["']${id}["']`));
  }
  assert.match(page, /aria-label=["']主导航["']/);
  assert.match(page, /Apple 芯片与 Intel Mac/);
  assert.match(page, /右键/);
  assert.match(page, /TMDB/);
  assert.match(page, /OMDb/);
});

test("follows system appearance and reduced-motion preferences", async () => {
  const css = await read("app/globals.css");
  assert.match(css, /prefers-color-scheme:\s*dark/);
  assert.match(css, /prefers-reduced-motion:\s*reduce/);
  assert.match(css, /--background:/);
  assert.match(css, /--foreground:/);
});
