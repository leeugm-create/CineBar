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
  const home = await read("app/home.tsx");
  const zh = await read("app/i18n.ts");
  const support = await read("app/support-view.tsx");
  const site = `${home}\n${zh}\n${support}`;
  assert.match(site, /找到下一部好片/);
  assert.doesNotMatch(site, /今晚看什么？/);
  assert.match(site, /一个找电影、电视剧的 app/);
  assert.match(site, /leeugm@vip\.qq\.com/);
  assert.match(site, /测试版/);
  assert.match(
    site,
    /https:\/\/github\.com\/leeugm-create\/CineBar\/releases/,
  );
  assert.match(site, /免费/);
  assert.match(site, /无广告/);
  assert.match(site, /无订阅/);
  assert.match(site, /https:\/\/www\.paypal\.com\/cgi-bin\/webscr/);
  assert.match(site, /VVVZUSU9QUJBW/);
});

test("keeps the public website anonymous without GPT account sign-in", async () => {
  const page = await read("app/page.tsx");
  const layout = await read("app/layout.tsx");
  assert.doesNotMatch(
    `${page}\n${layout}`,
    /ChatGPT|GPT account|signin-with-chatgpt/i,
  );
  await assert.rejects(
    access(new URL("../app/chatgpt-auth.ts", import.meta.url)),
    /ENOENT/,
  );
});

test("discloses the current release and multilingual coverage", async () => {
  const home = await read("app/home.tsx");
  const i18n = await read("app/i18n.ts");
  const langSelect = await read("app/lang-select.tsx");
  const site = `${home}\n${i18n}\n${langSelect}`;

  const linkedMac = home.match(/downloads\/CineBar-0\.8\.3-test-build-(\d+)-universal\.zip/);
  assert.ok(linkedMac, "home.tsx must link a build-universal.zip download");
  const buildNumber = Number(linkedMac[1]);
  assert.ok(Number.isInteger(buildNumber) && buildNumber >= 1, "download link must carry a numeric build");
  assert.match(site, new RegExp(`Build ${buildNumber}（|Build ${buildNumber}）`));
  assert.match(site, /本地片库/);
  assert.match(site, new RegExp(`CineBar-0\\.8\\.3-test-build-${buildNumber}-universal\\.zip`));
  assert.doesNotMatch(site, /已签名 appcast 发布后才支持应用内更新/);
  assert.match(site, /支持简体中文、繁体中文、英语、日语与韩语/);
  assert.match(site, /测试版/);
  assert.match(site, /一次看全/);
  assert.doesNotMatch(site, /已经.*公证/);
});

test("keeps the telemetry dashboard server-side and protected by a secret", async () => {
  const page = await read("app/admin/analytics/page.tsx");
  assert.match(page, /CINEBAR_TELEMETRY_ADMIN_TOKEN/);
  assert.match(page, /Authorization.*Bearer/);
  assert.match(page, /telemetry\.cinebar\.cc/);
  assert.doesNotMatch(page, /localStorage|install_id|install_hash/);
});

test("protects the analytics route before rendering any aggregate data", async () => {
  const worker = await read("worker/index.ts");
  assert.match(worker, /url\.pathname === ["']\/admin\/analytics["']/);
  assert.match(worker, /CINEBAR_TELEMETRY_ADMIN_TOKEN/);
  assert.match(worker, /startsWith\(["']Basic ["']\)/);
  assert.match(worker, /atob\(/);
  assert.match(worker, /www-authenticate/);
  assert.match(worker, /Administrator authentication required/);
});

test("contains accessible navigation and all required sections", async () => {
  const home = await read("app/home.tsx");
  const i18n = await read("app/i18n.ts");
  const langSelect = await read("app/lang-select.tsx");
  const site = `${home}\n${i18n}\n${langSelect}`;
  for (const id of ["ratings", "features", "install", "support"]) {
    assert.match(site, new RegExp(`id=["']${id}["']`));
  }
  assert.match(site, /aria-label=["']Language["']/);
  assert.match(site, /Apple 芯片与 Intel Mac/);
  assert.match(site, /右键/);
  assert.match(site, /TMDB/);
  assert.match(site, /Metacritic/);
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

test("keeps the lang select from composing broken /en/ja paths", async () => {
  const select = await read("app/lang-select.tsx");
  assert.match(select, /if \(!matched\) suffix = here/);
  assert.doesNotMatch(select, /if \(suffix === "" && here !== "\/"\) suffix = here/);
});

test("exposes an uncached website health response", async () => {
  const route = await read("app/health/route.ts");
  assert.match(route, /service:\s*["']cinebar-website["']/);
  assert.match(route, /0\.8\.3-test\.12-build-28/);
  assert.match(route, /cache-control/);
  assert.match(route, /no-store/);
});

test("keeps the signed appcast in descending immutable build order", async () => {
  const appcast = await read("public/appcast.xml");
  const builds = [...appcast.matchAll(/sparkle:version="(\d+)"/g)].map(
    (match) => Number(match[1]),
  );
  assert.ok(builds.length >= 5, "appcast must carry several prior builds");
  for (let i = 1; i < builds.length; i++) {
    assert.ok(builds[i - 1] > builds[i], `builds must descend at index ${i}: ${builds}`);
  }
  assert.match(appcast, /sparkle:edSignature="[^"]+"/);
  assert.match(appcast, /length="[1-9][0-9]*"/);
  const home = await read("app/home.tsx");
  const linked = home.match(/build-(\d+)-universal\.zip/);
  assert.ok(linked, "home.tsx must link the latest build");
  assert.equal(
    builds[0],
    Number(linked[1]),
    "appcast newest build must match the website download link",
  );
  assert.match(
    appcast,
    new RegExp(`CineBar-0\\.8\\.3-test-build-${builds[0]}-universal\\.zip`),
  );
  assert.ok(
    [...appcast.matchAll(/CineBar-0\.8\.3-test-build-(\d+)-universal\.zip/g)]
      .map((m) => m[1])
      .includes(String(builds[0])),
  );
});
