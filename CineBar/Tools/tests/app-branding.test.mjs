import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const sourcePath = new URL("../../Sources/CineBar/main.swift", import.meta.url);
const localLibraryViewPath = new URL("../../Sources/CineBar/LocalLibraryView.swift", import.meta.url);
const localizationRoot = new URL("../../Assets/Localization/", import.meta.url);
const installGuidePath = new URL("../../INSTALL.md", import.meta.url);

test("uses the new CineBar Chinese tagline in the app shell", async () => {
  const source = await readFile(sourcePath, "utf8");
  assert.match(source, /找到下一部好片/);
  assert.doesNotMatch(source, /今晚看什么？/);
});

test("keeps the tagline localization key aligned across supported locales", async () => {
  const locales = ["en.lproj", "ja.lproj", "ko.lproj", "zh-Hant.lproj"];
  for (const locale of locales) {
    const strings = await readFile(
      new URL(`${locale}/Localizable.strings`, localizationRoot),
      "utf8",
    );
    assert.match(strings, /"找到下一部好片"/);
    assert.doesNotMatch(strings, /"今晚看什么？"/);
  }
});

test("localizes every Local Library label and error across supported locales", async () => {
  const keys = [
    "本地片库",
    "添加文件夹",
    "刷新",
    "正在扫描…",
    "待匹配",
    "确认匹配",
    "重新定位文件",
    "文件不可用",
    "存储卷未连接",
    "已看",
    "未看",
    "播放",
    "匹配影片",
    "本地片库为空",
    "添加包含视频文件的文件夹后，使用刷新扫描目录。",
    "已添加 %lld 个目录 · %lld 个视频",
    "正在扫描 %@ · %lld 个视频",
    "添加",
    "筛选",
    "重新定位",
    "片单",
    "移除片单",
    "加入片单",
    "匹配",
    "有建议",
    "确认影片匹配",
    "选择后将覆盖当前匹配信息；跳过不会影响本地文件或播放。",
    "没有找到候选项",
    "跳过",
    "文件当前不可用。请重新定位文件后再播放。",
    "找不到文件。请重新定位文件。",
    "无法启动播放器打开 %@。",
    "匹配失败：%@",
    "所选文件夹已不在片库中。",
    "片库刷新已取消。",
    "无法保存本地片库。",
    "所选片库项目已不存在。",
    "片库项目已不存在。",
    "所选文件与片库项目不匹配。",
    "所选文件不在已授权的文件夹中。",
    "所选项目不是文件。",
    "无法添加文件夹。",
    "无法播放本地文件。",
    "匹配影片失败。",
    "无法重新定位文件。",
    "文件夹权限需要更新。请重新添加同一文件夹。",
    "复制路径",
    "系统播放器",
    "未安装",
    "启动失败",
    "启动超时",
    "系统拒绝打开",
    "无法启动播放器。文件路径：%@",
    "无法启动播放器。%@。文件路径：%@",
    "关闭片库",
    "其他视频",
    "搜索片名",
    "搜索",
  ];
  const locales = [
    "en.lproj",
    "ja.lproj",
    "ko.lproj",
    "zh-Hans.lproj",
    "zh-Hant.lproj",
  ];

  for (const locale of locales) {
    const strings = await readFile(
      new URL(`${locale}/Localizable.strings`, localizationRoot),
      "utf8",
    );
    for (const key of keys) {
      assert.match(strings, new RegExp(`"${key}"\\s*=`), `${locale} is missing ${key}`);
    }
  }
});

test("keeps the Local Library navigation title available for each app language", async () => {
  const source = await readFile(sourcePath, "utf8");
  for (const title of ["本地片库", "本機片庫", "Local Library", "ローカルライブラリ", "로컬 라이브러리"]) {
    assert.match(source, new RegExp(title));
  }
});

test("routes Local Library runtime labels through the selected app language", async () => {
  const source = await readFile(localLibraryViewPath, "utf8");
  assert.match(source, /LocalLibraryLocalization\.string\(key, language:/);
  assert.doesNotMatch(source, /String\(localized:/);
});

test("keeps in-app release metadata on Build 26", async () => {
  const source = await readFile(sourcePath, "utf8");
  assert.match(source, /CineBar 0\.8\.3-test\.10/);
  assert.match(source, /Build 26 · 2026 年 8 月 3 日/);
  assert.doesNotMatch(source, /CineBar 0\.8\.3-test\.9/);
  assert.doesNotMatch(source, /CineBar 0\.8\.0（Build 12）/);
});

test("documents the always-on anonymous installation telemetry contract", async () => {
  const source = await readFile(sourcePath, "utf8");
  const info = await readFile(new URL("../../Info.plist", import.meta.url), "utf8");
  assert.match(source, /每天最多上报一次/);
  assert.match(source, /CineBarTelemetryClient\(\)\.reportIfNeeded/);
  assert.match(info, /<key>CineBarTelemetryURL<\/key>/);
  assert.match(info, /https:\/\/telemetry\.cinebar\.cc\/v1\/telemetry\/install/);
});

test("documents Local Library setup and local-only playback in English", async () => {
  const guide = await readFile(installGuidePath, "utf8");
  for (const phrase of [
    "0.8.3-test.10",
    "Build 26",
    "Add Folder",
    "Refresh",
    "Confirm Match",
    "IINA",
    "VLC",
    "does not upload",
    "does not provide downloads",
    "not notarized",
    "in-app update",
  ]) {
    assert.match(guide, new RegExp(phrase));
  }
});
