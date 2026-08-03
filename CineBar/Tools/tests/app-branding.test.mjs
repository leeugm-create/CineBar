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
