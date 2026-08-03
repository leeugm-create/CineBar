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

test("uses localized keys for Local Library runtime labels", async () => {
  const source = await readFile(localLibraryViewPath, "utf8");
  for (const key of [
    "全部",
    "搜索本地视频",
    "文件可用",
    "已匹配",
    "未知年份",
    "电影",
    "电视剧",
  ]) {
    assert.match(
      source,
      new RegExp(`String\\(localized: "${key}"\\)`),
      `LocalLibraryView must localize ${key}`,
    );
  }
});

test("documents Local Library setup and local-only playback in English", async () => {
  const guide = await readFile(installGuidePath, "utf8");
  for (const phrase of [
    "0.8.3-test.7",
    "Build 23",
    "Add Folder",
    "Refresh",
    "Confirm Match",
    "IINA",
    "VLC",
    "does not upload",
    "does not provide downloads",
    "not notarized",
  ]) {
    assert.match(guide, new RegExp(phrase));
  }
});
