import test from "node:test";
import assert from "node:assert/strict";
import { access, readFile } from "node:fs/promises";
import { execFile } from "node:child_process";
import { fileURLToPath } from "node:url";
import { promisify } from "node:util";

const read = (path) => readFile(new URL(`../${path}`, import.meta.url), "utf8");
const execFileAsync = promisify(execFile);

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

test("keeps the Sites Vite plugin in a tracked source path", async () => {
  const viteConfig = await read("vite.config.ts");
  const pluginImport = viteConfig.match(
    /from ["'](?<path>\.\/(?:[^"']*\/)?sites-vite-plugin)["']/,
  )?.groups?.path;

  assert.ok(pluginImport, "vite.config.ts must import the Sites Vite plugin");
  assert.doesNotMatch(pluginImport, /(^|\/)build\//);

  const pluginPath = `${pluginImport.replace(/^\.\//, "")}.ts`;
  await access(new URL(`../${pluginPath}`, import.meta.url));
  await execFileAsync(
    "git",
    ["ls-files", "--error-unmatch", `CineBarWebsite/${pluginPath}`],
    { cwd: fileURLToPath(new URL("../../", import.meta.url)) },
  );
});
