import test from "node:test";
import assert from "node:assert/strict";
import { access, readFile } from "node:fs/promises";
import { execFile } from "node:child_process";
import { fileURLToPath } from "node:url";
import { promisify } from "node:util";

const read = (path) => readFile(new URL(`../${path}`, import.meta.url), "utf8");
const execFileAsync = promisify(execFile);
const repositoryRoot = fileURLToPath(new URL("../../", import.meta.url));

async function hasGitWorktree() {
  try {
    const { stdout } = await execFileAsync(
      "git",
      ["rev-parse", "--is-inside-work-tree"],
      { cwd: repositoryRoot },
    );
    return stdout.trim() === "true";
  } catch (error) {
    if (error.code === 128 || error.code === "ENOENT") {
      return false;
    }
    throw error;
  }
}

function contrastRatio(foreground, background) {
  const luminance = (hex) =>
    hex
      .slice(1)
      .match(/../g)
      .map((part) => parseInt(part, 16) / 255)
      .map((value) =>
        value <= 0.04045
          ? value / 12.92
          : ((value + 0.055) / 1.055) ** 2.4,
      )
      .reduce(
        (sum, value, index) => sum + value * [0.2126, 0.7152, 0.0722][index],
        0,
      );

  return (
    (Math.max(luminance(foreground), luminance(background)) + 0.05) /
    (Math.min(luminance(foreground), luminance(background)) + 0.05)
  );
}

test("publishes the approved CineBar identity and download entry", async () => {
  const page = await read("app/page.tsx");
  assert.match(page, /找到下一部好片/);
  assert.doesNotMatch(page, /今晚看什么？/);
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

test("discloses the current Build 23 test update, Local Library, and anonymous community-rating limit", async () => {
  const page = await read("app/page.tsx");

  assert.match(page, /0\.8\.3-test\.7（Build 23）/);
  assert.match(page, /本地片库/);
  assert.match(page, /GitHub Releases 手动安装/);
  assert.match(page, /已签名 appcast 发布后才支持应用内更新/);
  assert.match(page, /匿名设备标识/);
  assert.match(page, /每个作品仅可评分一次/);
  assert.match(page, /不是正式稳定版/);
  assert.doesNotMatch(page, /已经.*公证/);
  assert.match(page, /安装前请验证 CineBar 独立签名/);
  assert.match(page, /不等于 Apple 公证/);
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

test("uses a contrast-safe token pair for the light primary button", async () => {
  const css = await read("app/globals.css");
  const primaryBackground = css.match(
    /--primary-background:\s*(#[0-9a-f]{6})/i,
  )?.[1];
  const primaryForeground = css.match(
    /--primary-foreground:\s*(#[0-9a-f]{6})/i,
  )?.[1];

  assert.ok(primaryBackground, "primary buttons need a dedicated background token");
  assert.ok(primaryForeground, "primary buttons need a dedicated foreground token");
  assert.ok(
    contrastRatio(primaryForeground, primaryBackground) >= 4.5,
    "light primary-button text must meet 4.5:1 contrast",
  );
  assert.match(
    css,
    /\.primary\s*\{\s*background:\s*var\(--primary-background\);[^}]*color:\s*var\(--primary-foreground\);/,
  );
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
  if (await hasGitWorktree()) {
    await execFileAsync(
      "git",
      ["ls-files", "--error-unmatch", `CineBarWebsite/${pluginPath}`],
      { cwd: repositoryRoot },
    );
  }
});

test("exposes an uncached website health response", async () => {
  const route = await read("app/health/route.ts");
  assert.match(route, /service:\s*["']cinebar-website["']/);
  assert.match(route, /cache-control/);
  assert.match(route, /no-store/);
});
