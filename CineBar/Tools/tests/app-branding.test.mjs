import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const sourcePath = new URL("../../Sources/CineBar/main.swift", import.meta.url);
const localLibraryModelPath = new URL("../../Sources/CineBar/LocalLibrary.swift", import.meta.url);
const localLibraryViewPath = new URL("../../Sources/CineBar/LocalLibraryView.swift", import.meta.url);
const localizationRoot = new URL("../../Assets/Localization/", import.meta.url);
const installGuidePath = new URL("../../INSTALL.md", import.meta.url);
const htmlInstallGuidePath = new URL(
  "../../请先阅读-测试版安装说明.html",
  import.meta.url,
);
const textInstallGuidePath = new URL(
  "../../请先阅读-测试版安装说明.txt",
  import.meta.url,
);
const releaseNotesPath = new URL(
  "../../ReleaseNotes/0.8.3-test.11-Build-27.txt",
  import.meta.url,
);

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
    "查看详情",
    "文件详情",
    "文件名",
    "路径",
    "文件夹",
    "文件大小",
    "观看状态",
    "片单状态",
    "未知",
    "关闭详情",
    "匹配影片或电视剧",
    "关闭匹配",
    "清除搜索",
    "请输入片名",
    "最佳建议",
    "相似度",
    "最佳建议仅供参考；确认需手动操作，且当前条目的匹配不可撤销。",
    "本地片库的内容分类与状态筛选现在可以组合使用",
    "已确认影片可打开完整资料，未匹配文件显示本地详情",
    "匹配搜索改为明确确认，并避免旧请求覆盖新结果",
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

test("keeps Local Library category tabs separate from combinable status filters", async () => {
  const [modelSource, viewSource] = await Promise.all([
    readFile(localLibraryModelPath, "utf8"),
    readFile(localLibraryViewPath, "utf8"),
  ]);

  assert.match(
    modelSource,
    /enum LocalLibraryCategoryFilter[\s\S]*?case all[\s\S]*?case movie[\s\S]*?case television[\s\S]*?case other[\s\S]*?case \.other: return entry\.contentCategory == \.other/,
  );
  assert.match(
    modelSource,
    /enum LocalLibraryStatusFilter[\s\S]*?case all[\s\S]*?case unwatched[\s\S]*?case unmatched[\s\S]*?case unavailable/,
  );
  assert.match(
    viewSource,
    /Picker\(localized\("内容类型"\), selection: \$categoryFilter\)[\s\S]*?ForEach\(LocalLibraryCategoryFilter\.allCases\)[\s\S]*?\.pickerStyle\(\.segmented\)/,
  );
  assert.match(
    viewSource,
    /Picker\(localized\("筛选"\), selection: \$statusFilter\)[\s\S]*?ForEach\(LocalLibraryStatusFilter\.allCases\)[\s\S]*?\.pickerStyle\(\.menu\)/,
  );
  assert.match(
    viewSource,
    /guard categoryFilter\.includes\(entry\) else \{ return false \}[\s\S]*?guard statusFilter\.includes\(entry\) else \{ return false \}/,
  );
});

test("routes confirmed Local Library media to existing details and keeps file-only details local", async () => {
  const [source, viewSource] = await Promise.all([
    readFile(sourcePath, "utf8"),
    readFile(localLibraryViewPath, "utf8"),
  ]);

  assert.match(viewSource, /struct LocalLibraryFileDetailView: View/);
  assert.match(viewSource, /Button\(localized\("查看详情"\), action: onDetail\)/);
  assert.match(viewSource, /\.sheet\(item: \$fileDetailEntry/);
  assert.match(
    viewSource,
    /\.sheet\(item: \$fileDetailEntry, onDismiss: presentPendingMatch\)/,
  );
  assert.match(
    viewSource,
    /LocalLibraryDetailBridge\.movie\(from: metadata\)[\s\S]*?movieStore\.select\(movie\)/,
  );
  assert.match(
    viewSource,
    /LocalLibraryDetailBridge\.television\(from: metadata\)[\s\S]*?movieStore\.selectTV\(show\)/,
  );
  assert.match(
    viewSource,
    /store\.confirmMatch\([\s\S]*?store\.entries\.contains[\s\S]*?openExternalDetail\(for: candidate\.metadata\)/,
  );

  const fileDetailStart = viewSource.indexOf("struct LocalLibraryFileDetailView: View");
  const fileDetailEnd = viewSource.indexOf("enum LocalLibraryPosterURL", fileDetailStart);
  const fileDetailSource = viewSource.slice(fileDetailStart, fileDetailEnd);
  for (const key of [
    "文件名",
    "路径",
    "文件夹",
    "文件大小",
    "观看状态",
    "片单状态",
    "匹配影片或电视剧",
  ]) {
    assert.match(fileDetailSource, new RegExp(key), `file detail is missing ${key}`);
  }
  assert.doesNotMatch(fileDetailSource, /voteAverage|cast|评分|演员|剧照|预告/);

  const contentViewSource = source.slice(source.indexOf("struct ContentView: View"));
  const movieRoute = contentViewSource.indexOf("else if let movie = store.selectedMovie");
  const televisionRoute = contentViewSource.indexOf("else if let show = store.selectedTVShow");
  const localLibraryRoute = contentViewSource.indexOf("else if store.isShowingLocalLibrary");
  assert.ok(movieRoute >= 0, "missing selected movie route");
  assert.ok(televisionRoute >= 0, "missing selected television route");
  assert.ok(localLibraryRoute >= 0, "missing Local Library route");
  assert.ok(movieRoute < localLibraryRoute, "movie details must precede the Local Library list");
  assert.ok(
    televisionRoute < localLibraryRoute,
    "television details must precede the Local Library list",
  );
  assert.match(source, /@State private var localLibraryCategoryFilter/);
  assert.match(source, /categoryFilter: \$localLibraryCategoryFilter/);
});

test("keeps Local Library matching explicit, dismissible, and resilient", async () => {
  const viewSource = await readFile(localLibraryViewPath, "utf8");
  const matchSheetStart = viewSource.indexOf("private struct LocalLibraryMatchSheet: View");
  assert.ok(matchSheetStart >= 0, "missing LocalLibraryMatchSheet");
  const matchSheetSource = viewSource.slice(matchSheetStart);

  assert.match(
    viewSource,
    /candidates: entry\.contentCategory == \.other\s*\? \[\][\s\S]*?initialQuery: entry\.contentCategory == \.other\s*\? ""/,
  );
  assert.match(
    matchSheetSource,
    /Button\(action: dismiss\)[\s\S]*?Image\(systemName: "xmark\.circle\.fill"\)[\s\S]*?\.help\(localized\("关闭匹配"\)\)/,
  );
  assert.match(matchSheetSource, /Button\(localized\("跳过"\), action: dismiss\)/);
  assert.match(
    matchSheetSource,
    /private func dismiss\(\)[\s\S]*?searchTask\?\.cancel\(\)[\s\S]*?onDismiss\(\)/,
  );
  assert.match(matchSheetSource, /TextField\(localized\("搜索片名"\), text: \$queryText\)/);
  assert.match(
    matchSheetSource,
    /Picker\(localized\("内容类型"\), selection: \$kind\)[\s\S]*?LocalLibraryMediaKind\.movie[\s\S]*?LocalLibraryMediaKind\.television/,
  );
  assert.match(
    matchSheetSource,
    /Button[\s\S]*?clearSearch\(\)[\s\S]*?\.help\(localized\("清除搜索"\)\)/,
  );
  assert.match(
    matchSheetSource,
    /private func clearSearch\(\)[\s\S]*?queryText = ""[\s\S]*?candidates = \[\]/,
  );
  assert.match(
    matchSheetSource,
    /ForEach\(Array\(candidates\.enumerated\(\)\), id: \\.element\.id\)[\s\S]*?offset == 0[\s\S]*?localized\("最佳建议"\)[\s\S]*?localized\("相似度"\)[\s\S]*?candidate\.confidence/,
  );
  assert.match(
    matchSheetSource,
    /localized\("最佳建议仅供参考；确认需手动操作，且当前条目的匹配不可撤销。"\)/,
  );
  const searchSource = matchSheetSource.slice(matchSheetSource.indexOf("private func search()"));
  assert.match(
    searchSource,
    /let generation = searchState\.begin\(\)[\s\S]*?let results = try await session\.search\(query\)[\s\S]*?guard searchState\.isCurrent\(generation\),\s*!Task\.isCancelled\s*else \{ return \}[\s\S]*?candidates = results[\s\S]*?searchError = nil/,
  );
  assert.match(
    searchSource,
    /catch[\s\S]*?guard searchState\.isCurrent\(generation\) else \{ return \}[\s\S]*?Task\.isCancelled \|\|[\s\S]*?LocalLibraryMatchSearchState\.isCancellation\(error\)/,
  );
  assert.match(
    searchSource,
    /searchState\.finish\([\s\S]*?generation: generation[\s\S]*?receivedResults:/,
  );
  const failedSearchCatch = searchSource.slice(
    searchSource.indexOf("} catch {"),
    searchSource.indexOf("private func clearSearch()"),
  );
  assert.doesNotMatch(failedSearchCatch, /candidates = \[\]/);
  assert.doesNotMatch(searchSource, /\n\s*isSearching = false/);
  assert.match(
    matchSheetSource,
    /@State private var searchState: LocalLibraryMatchSearchState/,
  );
  assert.match(
    matchSheetSource,
    /initialHasSearched: session\.entry\.contentCategory != \.other/,
  );
  assert.match(
    matchSheetSource,
    /state: searchState\.hasSearched[\s\S]*?LocalLibraryEmptyState\.match\(language: language\)[\s\S]*?localized\("请输入片名"\)/,
  );
  assert.match(
    matchSheetSource,
    /private func clearSearch\(\)[\s\S]*?searchState\.reset\(\)/,
  );
  assert.doesNotMatch(matchSheetSource, /onConfirm\(candidates\.first/);
});

test("keeps in-app release metadata on Build 27", async () => {
  const source = await readFile(sourcePath, "utf8");
  assert.match(source, /CineBar 0\.8\.3-test\.11/);
  assert.match(source, /Build 27 · 2026 年 8 月 4 日/);
  assert.doesNotMatch(source, /CineBar 0\.8\.3-test\.10/);
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
    "0.8.3-test.11",
    "Build 27",
    "Add Folder",
    "Refresh",
    "View Details",
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

test("discloses ad-hoc app signing separately from Sparkle update signing", async () => {
  const [english, html, text, releaseNotes] = await Promise.all([
    readFile(installGuidePath, "utf8"),
    readFile(htmlInstallGuidePath, "utf8"),
    readFile(textInstallGuidePath, "utf8"),
    readFile(releaseNotesPath, "utf8"),
  ]);

  for (const document of [english, html, text, releaseNotes]) {
    assert.match(document, /ad-hoc/i);
    assert.match(document, /Apple Developer ID/);
  }
  assert.match(english, /not notarized/i);
  for (const document of [html, text, releaseNotes]) {
    assert.match(document, /未经 Apple 公证/);
    assert.match(document, /Sparkle EdDSA/);
  }
});
