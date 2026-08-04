# CineBar Local Library Classification and Manual Matching Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将本地片库中的视频分为电影、电视剧和其他视频，提供保守候选与手动 TMDB 匹配，并为片库增加关闭按钮。

**Architecture:** 在现有 `LocalLibraryEntry` 上增加可迁移的内容分类；扫描器只解析文件名和生成分类提示，不发起网络请求；匹配服务提供自动候选与用户输入搜索两条路径，只有用户确认才写入 metadata；SwiftUI 片库视图负责筛选、匹配窗口和关闭面板。

**Tech Stack:** Swift 5、SwiftUI、AppKit、Foundation、现有 TMDB 代理、macOS 13+、现有 Universal 构建脚本。

## Global Constraints

- 支持 macOS 13.0 及 Apple silicon / Intel Universal 构建。
- 仅扫描用户通过 `NSOpenPanel` 授权的目录。
- 保留个人视频，但将其归入 `other`，不参与电影/电视剧候选污染。
- 自动匹配只生成候选，不自动写入 TMDB metadata。
- 手动搜索只查询电影/电视剧元数据，不提供下载链接、磁力链接或第三方片源。
- 确认新匹配时保留已看、片单和最近打开时间。
- 片库左上角关闭按钮只隐藏面板，不退出应用。
- 下一版测试发布目标为 `0.8.3-test.10`（Build 26），`CFBundleShortVersionString` 保持 `0.8.3`，`CFBundleVersion` 升至 `26`。

## 文件结构与职责

- Modify: `CineBar/Sources/CineBar/LocalLibrary.swift` — 分类枚举、文件名分类规则、schema 迁移辅助。
- Modify: `CineBar/Sources/CineBar/LocalLibraryScanner.swift` — 为扫描条目生成分类和候选状态。
- Modify: `CineBar/Sources/CineBar/LocalLibraryStore.swift` — 分类保留、确认匹配和刷新合并。
- Modify: `CineBar/Sources/CineBar/LocalLibraryMatchService.swift` — 手动搜索词/类型接口与候选转换。
- Modify: `CineBar/Sources/CineBar/LocalLibraryView.swift` — 关闭按钮、分类筛选、手动搜索匹配窗口。
- Modify: `CineBar/Tests/RegressionBehaviorTests.swift` — 分类、迁移、匹配确认和关闭行为回归断言。
- Modify: `CineBar/Tools/tests/app-branding.test.mjs` — 新增分类和手动匹配文案检查。
- Modify: `CineBar/Assets/Localization/{zh-Hans,zh-Hant,en,ja,ko}.lproj/Localizable.strings` — 新增分类、搜索和关闭文案。
- Modify: `CineBar/Info.plist` — Build 26。
- Create: `CineBar/ReleaseNotes/0.8.3-test.10-Build-26.txt` — 简短更新说明。
- Modify: `CineBar/README.md`、`CineBar/INSTALL.md`、安装说明 HTML/TXT — 本地片库分类和手动匹配说明。

## Shared Interfaces

```swift
enum LocalLibraryContentCategory: String, Codable, Hashable {
    case movie
    case television
    case other
}

struct LocalLibraryParsedFilename: Hashable {
    let title: String
    let year: String?
    let fileExtension: String
    let category: LocalLibraryContentCategory
    let isTrustedTitle: Bool
}

struct LocalLibraryMatchQuery: Hashable {
    let text: String
    let kind: LocalLibraryMediaKind
}

func search(query: LocalLibraryMatchQuery) async throws -> [LocalLibraryMatchCandidate]
```

### Task 1: 增加内容分类和旧数据迁移

**Files:**
- Modify: `CineBar/Sources/CineBar/LocalLibrary.swift`
- Modify: `CineBar/Tests/RegressionBehaviorTests.swift`

**Interfaces:** `LocalLibraryContentCategory`、`LocalLibraryParsedFilename.category`、`isTrustedTitle`、`LocalLibraryEntry.contentCategory`、`LocalLibrarySnapshot.currentSchemaVersion = 2`。

- [ ] **Step 1: 写失败测试**

```swift
let personal = LocalLibraryFilenameParser.parse("IMG_20260803_142233.mov")
precondition(personal.category == .other)
precondition(!personal.isTrustedTitle)

let movie = LocalLibraryFilenameParser.parse("Interstellar.2014.2160p.mkv")
precondition(movie.category == .movie)
precondition(movie.isTrustedTitle)

let show = LocalLibraryFilenameParser.parse("The Bear S02E03.mkv")
precondition(show.category == .television)
precondition(show.isTrustedTitle)
```

- [ ] **Step 2: 运行失败测试**

```bash
mkdir -p /tmp/cinebar-tests
xcrun swiftc -parse-as-library -D CINEBAR_TEST \
  CineBar/Sources/CineBar/*.swift \
  CineBar/Tests/RegressionBehaviorTests.swift \
  -o /tmp/cinebar-tests/CineBarRegressionTests
```

预期：分类字段和解析属性尚未定义，编译失败。

- [ ] **Step 3: 实现最小分类解析**

保留现有标题清理逻辑；新增相机/录屏前缀、纯时间戳、空标题规则。检测 `SxxExx` 或 `Season N` 为电视剧；其他可信标题默认为电影。任何不可信标题归为 `other`。

- [ ] **Step 4: 实现 schema 迁移**

将 `LocalLibrarySnapshot.currentSchemaVersion` 升为 2。解码旧条目时：已有 metadata 按 `metadata.kind` 分类；无 metadata 的条目通过解析器分类。缺失分类字段默认 `other`，损坏 JSON 仍按现有 `.bak` 恢复规则处理。

- [ ] **Step 5: 运行测试确认通过**

```bash
xcrun swiftc -parse-as-library -D CINEBAR_TEST \
  CineBar/Sources/CineBar/*.swift \
  CineBar/Tests/RegressionBehaviorTests.swift \
  -o /tmp/cinebar-tests/CineBarRegressionTests \
  && /tmp/cinebar-tests/CineBarRegressionTests
```

- [ ] **Step 6: 提交**

```bash
git add CineBar/Sources/CineBar/LocalLibrary.swift CineBar/Tests/RegressionBehaviorTests.swift
git commit -m "feat: classify local library video entries"
```

### Task 2: 让扫描和刷新保留分类及候选状态

**Files:**
- Modify: `CineBar/Sources/CineBar/LocalLibraryScanner.swift`
- Modify: `CineBar/Sources/CineBar/LocalLibraryStore.swift`
- Modify: `CineBar/Tests/RegressionBehaviorTests.swift`

**Interfaces:** `LocalLibraryScanner` 输出分类；`LocalLibraryRefreshMerger.merge` 保留分类、metadata、已看、片单和最近打开时间。

- [ ] **Step 1: 写失败测试**

创建一个 `IMG_...mov` 和一个 `Movie (2020).mkv`，首次扫描断言前者为 `.other`、后者为 `.movie` 且 metadata 为空；再次扫描断言条目 ID 和分类不变，条目数量不增加。

- [ ] **Step 2: 运行测试确认失败**

运行 `/tmp/cinebar-tests/CineBarRegressionTests`，预期扫描条目尚未携带分类。

- [ ] **Step 3: 实现扫描分类**

扫描器使用解析器输出填充 `contentCategory`；可信标题设置 `matchState = .suggested`，不可信标题设置 `matchState = .unmatched`。扫描器不调用 `TMDBClient`。

- [ ] **Step 4: 实现刷新合并规则**

同一 `folderID + normalized relativePath` 只保留一个条目；已有条目保留用户状态和 metadata；新文件使用扫描分类；文件消失只变为 `.missing` 或 `.volumeUnavailable`，不删除。

- [ ] **Step 5: 运行重复刷新和断盘测试**

连续刷新三次、删除文件、恢复文件，分别断言去重、状态变化和分类保持。

- [ ] **Step 6: 提交**

```bash
git add CineBar/Sources/CineBar/LocalLibraryScanner.swift \
  CineBar/Sources/CineBar/LocalLibraryStore.swift \
  CineBar/Tests/RegressionBehaviorTests.swift
git commit -m "feat: preserve local library categories during refresh"
```

### Task 3: 增加手动 TMDB 搜索和确认匹配

**Files:**
- Modify: `CineBar/Sources/CineBar/LocalLibraryMatchService.swift`
- Modify: `CineBar/Sources/CineBar/LocalLibraryStore.swift`
- Modify: `CineBar/Tests/RegressionBehaviorTests.swift`

**Interfaces:** `LocalLibraryMatchService.search(query:)`；`LocalLibraryStore.confirmMatch(entryID:metadata:category:)`。

- [ ] **Step 1: 写失败测试**

使用注入的 movie/TV 搜索闭包，调用 `search(query:)`，断言电影查询只调用 movie 搜索，电视剧查询只调用 TV 搜索；调用 `confirmMatch` 后断言 metadata、category 和 `.confirmed` 写入，同时 `isWatched`、`isInWatchlist`、`lastOpenedAt` 不变。

- [ ] **Step 2: 运行测试确认失败**

运行 Swift 回归测试，预期 `LocalLibraryMatchQuery` 和 `confirmMatch` 尚未定义。

- [ ] **Step 3: 实现查询接口**

保留现有候选排序和置信度；把文件名解析默认查询封装为 `search(query:)`。候选只包含 TMDB ID、标题、年份、海报、类型、评分、简介和类别。

- [ ] **Step 4: 实现确认匹配**

`confirmMatch` 只更新 metadata、contentCategory 和 matchState；不得重置用户状态。手动搜索失败只返回错误，不改变本地条目。

- [ ] **Step 5: 运行测试确认通过**

执行完整 Swift 回归编译和运行命令，确认电影/电视剧路由、确认覆盖和状态保留通过。

- [ ] **Step 6: 提交**

```bash
git add CineBar/Sources/CineBar/LocalLibraryMatchService.swift \
  CineBar/Sources/CineBar/LocalLibraryStore.swift \
  CineBar/Tests/RegressionBehaviorTests.swift
git commit -m "feat: support manual local media matching"
```

### Task 4: 更新片库 UI、关闭按钮和本地化

**Files:**
- Modify: `CineBar/Sources/CineBar/LocalLibraryView.swift`
- Modify: `CineBar/Assets/Localization/zh-Hans.lproj/Localizable.strings`
- Modify: `CineBar/Assets/Localization/zh-Hant.lproj/Localizable.strings`
- Modify: `CineBar/Assets/Localization/en.lproj/Localizable.strings`
- Modify: `CineBar/Assets/Localization/ja.lproj/Localizable.strings`
- Modify: `CineBar/Assets/Localization/ko.lproj/Localizable.strings`
- Modify: `CineBar/Tools/tests/app-branding.test.mjs`
- Modify: `CineBar/Tests/RegressionBehaviorTests.swift`

**Interfaces:** `LocalLibraryFilter` 增加 `.movie`、`.television`、`.other`；匹配 sheet 增加搜索词、类型和候选状态。

- [ ] **Step 1: 写失败文案/行为测试**

在 Node 文案测试中加入“电影”“电视剧”“其他视频”“搜索片名”“关闭片库”“确认匹配”；在 Swift 回归中断言筛选器只返回对应分类，并断言关闭操作发布 `.cineBarPanelWillHide` 而不调用终止应用。

- [ ] **Step 2: 运行测试确认失败**

```bash
node --test CineBar/Tools/tests/app-branding.test.mjs
```

预期新文案和分类筛选尚未实现。

- [ ] **Step 3: 实现片库左上角关闭按钮**

在 `LocalLibraryView.header` 左侧加入 `xmark.circle.fill`，点击发布 `.cineBarPanelWillHide` 并调用 `NSApplication.shared.keyWindow?.orderOut(nil)`；不调用 `terminate`。

- [ ] **Step 4: 实现分类筛选和行文案**

条目行显示“电影 / 电视剧 / 其他视频”；`other` 不显示“待匹配”误导性按钮，仍显示“匹配”入口供用户主动改变分类。

- [ ] **Step 5: 实现手动匹配 sheet**

匹配 sheet 默认填充解析标题，提供 TextField、电影/电视剧 Picker、搜索按钮、ProgressView、候选列表、确认匹配和跳过。确认调用 `store.confirmMatch`；关闭不改变条目。

- [ ] **Step 6: 完成本地化并运行测试**

五种语言必须覆盖新增 UI、错误和筛选文案；运行 Node 文案测试和 Swift 回归测试。

- [ ] **Step 7: 提交**

```bash
git add CineBar/Sources/CineBar/LocalLibraryView.swift \
  CineBar/Assets/Localization \
  CineBar/Tools/tests/app-branding.test.mjs \
  CineBar/Tests/RegressionBehaviorTests.swift
git commit -m "feat: add local library categories and matching UI"
```

### Task 5: 文档、Build 26 和发布验证

**Files:**
- Modify: `CineBar/Info.plist`
- Create: `CineBar/ReleaseNotes/0.8.3-test.10-Build-26.txt`
- Modify: `CineBar/README.md`
- Modify: `CineBar/INSTALL.md`
- Modify: `CineBar/请先阅读-测试版安装说明.html`
- Modify: `CineBar/请先阅读-测试版安装说明.txt`

- [ ] **Step 1: 更新版本和说明**

将 `CFBundleVersion` 改为 `26`，写入“其他视频分类、手动匹配、片库关闭按钮”三条简短更新说明，并说明本地视频不上传。

- [ ] **Step 2: 运行静态检查**

```bash
git diff --check
node --test CineBar/Tools/tests/app-branding.test.mjs
```

- [ ] **Step 3: 编译 Universal 包**

```bash
CineBar/Tools/build_test_package.sh
```

预期生成 `dist/CineBar-0.8.3-test-build-26-universal.zip`，并通过代码签名和构建来源检查。

- [ ] **Step 4: 运行包级验证**

确认 `file` 同时显示 `arm64` 和 `x86_64`，解压后安装说明、ReleaseNotes、BuildManifest 均存在；运行 Sparkle 签名检查。

- [ ] **Step 5: 提交发布资料**

```bash
git add CineBar/Info.plist CineBar/ReleaseNotes CineBar/README.md \
  CineBar/INSTALL.md CineBar/请先阅读-测试版安装说明.html \
  CineBar/请先阅读-测试版安装说明.txt
git commit -m "release: prepare CineBar Build 26 local library update"
```
