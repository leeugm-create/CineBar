# CineBar 本地片库 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为 CineBar 增加一个独立的本地片库分页，扫描用户授权目录中的影片，提供 TMDB 匹配确认、刷新、状态管理和 IINA/VLC/系统播放器回退。

**Architecture:** 使用目录索引而不是复制文件或内嵌解码器。`LocalLibraryStore` 管理本地 JSON 和状态，`LocalLibraryScanner` 在后台递归扫描授权目录，`LocalLibraryMatchService` 复用现有 TMDB 代理生成候选，`ExternalPlayerLauncher` 负责播放器回退，`LocalLibraryView` 负责交互界面。

**Tech Stack:** Swift 5、SwiftUI、AppKit、Foundation、macOS security-scoped bookmarks、现有 TMDB 代理、现有直接 `swiftc` Universal 构建流程、Sparkle 2.9.2。

## Global Constraints

- 支持 macOS 13.0 及 Apple silicon / Intel Universal 构建。
- 只扫描用户通过 `NSOpenPanel` 授权的目录；支持本机目录、外置硬盘和已挂载 NAS。
- 不上传本地路径、文件内容或影片文件；不抓取磁力、迅雷或第三方下载链接。
- 初始视频扩展名为 `.mp4`、`.m4v`、`.mov`、`.mkv`、`.avi`、`.webm`、`.ts`、`.m2ts`。
- 播放顺序固定为 IINA → VLC → macOS 系统默认播放器。
- 网络只用于 TMDB 元数据匹配；断网时已索引文件仍可播放。
- 新增字段必须有默认值，旧版本用户首次打开本地片库时显示空状态。
- 刷新必须发现新增文件、更新失效状态、保留已有状态，并且不得产生重复条目。
- 新功能发布为 `0.8.3-test.7（Build 23）`；`CFBundleShortVersionString` 保持 `0.8.3`，`CFBundleVersion` 升至 `23`，以保持 Sparkle 可更新链路。

---

## 文件结构与职责

- Create: `CineBar/Sources/CineBar/LocalLibrary.swift` — 纯数据模型、文件名解析、持久化和可测试的状态合并辅助函数。
- Create: `CineBar/Sources/CineBar/LocalLibraryScanner.swift` — security-scoped 目录解析、递归扫描和刷新结果。
- Create: `CineBar/Sources/CineBar/LocalLibraryPlayback.swift` — IINA/VLC/系统播放器解析与启动。
- Create: `CineBar/Sources/CineBar/LocalLibraryMatchService.swift` — TMDB 候选匹配适配层。
- Create: `CineBar/Sources/CineBar/LocalLibraryView.swift` — 本地片库列表、目录操作、筛选和匹配确认界面。
- Modify: `CineBar/Sources/CineBar/main.swift` — 主分页导航、`MovieStore` 导航状态、`ContentView` 和 `AppDelegate` 注入本地片库。
- Modify: `CineBar/Tests/RegressionBehaviorTests.swift` — 纯函数、扫描合并、播放器回退和持久化回归测试。
- Modify: `CineBar/Assets/Localization/*/Localizable.strings` — 简体、繁体、英语、日语、韩语文案。
- Create: `CineBar/ReleaseNotes/0.8.3-test.7-Build-23.txt` — 简短更新说明。
- Modify: `CineBar/Info.plist` — Build 23。
- Modify: `CineBar/README.md`、`CineBar/请先阅读-测试版安装说明.html`、`CineBar/请先阅读-测试版安装说明.txt` — 本地片库使用说明和版本说明。
- Modify: `CineBarWebsite/app/page.tsx`、`CineBarWebsite/tests/content.test.mjs` — 官网版本号与功能说明。
- Modify: `CineBarShare/worker.js`、`CineBarShare/tests/share-worker.test.mjs` — 健康状态和更新清单版本同步。
- Create/overwrite by tool: `CineBarWebsite/public/downloads/CineBar-0.8.3-test-build-23-universal.zip`、`CineBarWebsite/public/appcast.xml` — Universal 包和 Sparkle appcast。

## Interfaces shared between tasks

```swift
enum LocalLibraryFileState: String, Codable, Hashable {
    case available, missing, volumeUnavailable
}

enum LocalLibraryMatchState: String, Codable, Hashable {
    case unmatched, suggested, confirmed
}

enum LocalLibraryMediaKind: String, Codable, Hashable {
    case movie, television
}

struct LocalLibraryFileSignature: Codable, Hashable {
    let fileName: String
    let fileExtension: String
    let byteCount: Int64
    let modificationDate: Date?
    let resourceIdentifier: String?
}

struct LocalLibraryMetadata: Codable, Hashable {
    let id: Int
    let kind: LocalLibraryMediaKind
    let title: String
    let year: String
    let posterPath: String?
    let overview: String
    let voteAverage: Double
}

struct LocalLibraryEntry: Codable, Identifiable, Hashable {
    let id: UUID
    var folderID: UUID
    var relativePath: String
    var signature: LocalLibraryFileSignature
    var state: LocalLibraryFileState
    var matchState: LocalLibraryMatchState
    var metadata: LocalLibraryMetadata?
    var isWatched: Bool
    var isInWatchlist: Bool
    var lastOpenedAt: Date?
}

struct LocalLibraryFolder: Codable, Identifiable, Hashable {
    let id: UUID
    var displayName: String
    var pathHint: String
    var bookmarkData: Data
}
```

### Task 1: 建立本地片库数据模型、解析和持久化

**Files:**
- Create: `CineBar/Sources/CineBar/LocalLibrary.swift`
- Modify: `CineBar/Tests/RegressionBehaviorTests.swift`

**Interfaces:**
- Produces `LocalLibraryFileState`、`LocalLibraryMatchState`、`LocalLibraryMediaKind`、`LocalLibraryFileSignature`、`LocalLibraryMetadata`、`LocalLibraryEntry`、`LocalLibraryFolder`。
- Produces `LocalLibraryParsedFilename` 和 `LocalLibraryFilenameParser.parse(_:)`。
- Produces `LocalLibrarySnapshot`、`LocalLibraryPersistence.init(fileURL:)`、`load()` 和 `save(_:)`。
- Produces `LocalLibraryEntryMerge.key`，供扫描器去重和刷新合并使用。

- [ ] **Step 1: 写失败的纯函数测试**

在 `RegressionBehaviorTests.swift` 的 `main()` 中加入断言：

```swift
let parsed = LocalLibraryFilenameParser.parse("Interstellar (2014) 2160p.mkv")
precondition(parsed.title == "Interstellar")
precondition(parsed.year == "2014")
precondition(parsed.fileExtension == "mkv")

let duplicateKeyA = LocalLibraryEntryMerge.key(
    folderID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
    relativePath: "Movies/A.mkv"
)
let duplicateKeyB = LocalLibraryEntryMerge.key(
    folderID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
    relativePath: "Movies/A.mkv"
)
precondition(duplicateKeyA == duplicateKeyB)
```

同时测试空文件名、大小写扩展名、多余分辨率标记、无年份文件名和中英文片名。

- [ ] **Step 2: 运行回归测试确认失败**

运行：

```bash
mkdir -p /tmp/cinebar-tests
xcrun swiftc -parse-as-library -D CINEBAR_TEST \
  CineBar/Sources/CineBar/*.swift \
  CineBar/Tests/RegressionBehaviorTests.swift \
  -o /tmp/cinebar-tests/CineBarRegressionTests
```

预期：由于 `LocalLibraryFilenameParser` 尚未定义而失败。

- [ ] **Step 3: 实现数据模型和解析器**

`LocalLibraryFilenameParser.parse(_:)` 去除扩展名、常见分辨率/编码/语言标记和括号年份；只在年份为 4 位且在 1888…2100 范围内时提取年份。标题为空时使用原始文件名。

`LocalLibraryEntryMerge.key` 使用 `folderID + normalized relativePath`；同一文件的大小或修改日期变化只更新条目，不创建新条目。

- [ ] **Step 4: 实现 JSON 持久化和损坏文件恢复**

`LocalLibraryPersistence` 写入 `~/Library/Application Support/CineBar/LocalLibrary.json`，保存前将旧文件移动为 `.bak`，读取失败时优先尝试 `.bak`，两者都失败才返回空快照。快照包含 `schemaVersion = 1`、目录和条目数组。

- [ ] **Step 5: 运行测试确认通过**

运行：

```bash
xcrun swiftc -parse-as-library -D CINEBAR_TEST \
  CineBar/Sources/CineBar/*.swift \
  CineBar/Tests/RegressionBehaviorTests.swift \
  -o /tmp/cinebar-tests/CineBarRegressionTests
/tmp/cinebar-tests/CineBarRegressionTests
```

预期：PASS。

- [ ] **Step 6: 提交**

```bash
git add CineBar/Sources/CineBar/LocalLibrary.swift CineBar/Tests/RegressionBehaviorTests.swift
git commit -m "feat: add local library data model"
```

### Task 2: 实现目录授权、递归扫描和刷新合并

**Files:**
- Create: `CineBar/Sources/CineBar/LocalLibraryScanner.swift`
- Modify: `CineBar/Sources/CineBar/LocalLibrary.swift`
- Modify: `CineBar/Tests/RegressionBehaviorTests.swift`

**Interfaces:**
- Produces `LocalLibraryScanRoot`、`LocalLibraryScanProgress`、`LocalLibraryScanResult`。
- Produces `LocalLibraryFolderBookmark.make(from:)` 和 `resolve(_:)`。
- Produces `LocalLibraryScanner.scan(roots:existing:progress:) async`。
- Produces `LocalLibraryRefreshMerger.merge(existing:scanned:roots:)`。

- [ ] **Step 1: 写扫描和刷新失败测试**

使用 `FileManager.temporaryDirectory` 创建 `Movies/A.mkv` 和 `Shows/B.mp4`，先扫描一次，再加入 `Movies/C.mov` 后扫描第二次；断言第二次有 3 条记录且 A/B 只有一条。删除 B 后断言 B 为 `.missing`；用未挂载根目录测试 `.volumeUnavailable`：

```swift
let rootURL = FileManager.default.temporaryDirectory
    .appendingPathComponent("CineBarLocalLibrary-\(UUID().uuidString)")
let moviesURL = rootURL.appendingPathComponent("Movies")
let showsURL = rootURL.appendingPathComponent("Shows")
try FileManager.default.createDirectory(
    at: moviesURL, withIntermediateDirectories: true
)
try FileManager.default.createDirectory(
    at: showsURL, withIntermediateDirectories: true
)
FileManager.default.createFile(
    atPath: moviesURL.appendingPathComponent("A.mkv").path,
    contents: Data()
)
FileManager.default.createFile(
    atPath: showsURL.appendingPathComponent("B.mp4").path,
    contents: Data()
)
let testRoot = LocalLibraryScanRoot(
    folderID: UUID(), url: rootURL, displayName: "测试片库"
)
let first = await LocalLibraryScanner().scan(
    roots: [testRoot], existing: [], progress: { _ in }
)
FileManager.default.createFile(
    atPath: moviesURL.appendingPathComponent("C.mov").path,
    contents: Data()
)
let second = await LocalLibraryScanner().scan(
    roots: [testRoot], existing: first.entries, progress: { _ in }
)
precondition(second.entries.count == 3)
precondition(Set(second.entries.map(\.relativePath)).count == 3)
```

- [ ] **Step 2: 运行测试确认失败**

运行同一回归编译命令和 `/tmp/cinebar-tests/CineBarRegressionTests`，预期因扫描器类型尚未定义而失败。

- [ ] **Step 3: 实现安全书签和目录解析**

`LocalLibraryFolderBookmark.make(from:)` 使用 `.withSecurityScope` 创建 bookmark；解析时调用 `startAccessingSecurityScopedResource()`，扫描结束后调用 `stopAccessingSecurityScopedResource()`。只保存 bookmarkData 和显示用 `pathHint`，不在界面输出完整敏感路径。

- [ ] **Step 4: 实现后台递归扫描**

使用 `FileManager.enumerator(at:includingPropertiesForKeys:options: [.skipsHiddenFiles])`，读取文件类型、大小、修改时间和资源标识。只接受 Global Constraints 中的扩展名；通过 `Task.detached` 或独立 actor 执行，不触碰 SwiftUI 状态。

- [ ] **Step 5: 实现刷新合并**

扫描结果按 `folderID + relativePath` 去重；新文件创建 `.unmatched` 条目；已有条目只更新签名和状态；本轮未发现的已有条目标记为 `.missing` 或 `.volumeUnavailable`。保留 metadata、isWatched、isInWatchlist 和 lastOpenedAt。

- [ ] **Step 6: 运行测试确认新增文件和重复刷新通过**

运行 Swift 回归测试，预期 PASS；确认连续点击刷新三次条目数量不变。

- [ ] **Step 7: 提交**

```bash
git add CineBar/Sources/CineBar/LocalLibrary.swift \
  CineBar/Sources/CineBar/LocalLibraryScanner.swift \
  CineBar/Tests/RegressionBehaviorTests.swift
git commit -m "feat: scan and refresh local library files"
```

### Task 3: 实现本地片库状态商店

**Files:**
- Create: `CineBar/Sources/CineBar/LocalLibraryStore.swift`
- Modify: `CineBar/Tests/RegressionBehaviorTests.swift`

**Interfaces:**
- Produces `@MainActor final class LocalLibraryStore: ObservableObject`。
- Public methods：`addFolder(url:) throws`、`refresh() async`、`refresh(folderID:) async`、`reattach(entryID:url:) throws`、`setWatched(entryID:value:)`、`toggleWatchlist(entryID:)`、`markOpened(entryID:)`、`updateMetadata(entryID:metadata:)`。
- Published state：`folders`、`entries`、`isScanning`、`scanProgress`、`message`。

- [ ] **Step 1: 写持久化状态测试**

先在临时目录创建一个视频文件并保存为 `rootURL`，再使用临时 JSON URL 初始化 `LocalLibraryStore`，设置已看、片单和最近打开时间，重新初始化后断言状态一致；测试添加新目录后 `refresh()` 发现新文件：

```swift
let stateURL = FileManager.default.temporaryDirectory
    .appendingPathComponent("LocalLibrary-\(UUID().uuidString).json")
let firstStore = LocalLibraryStore(fileURL: stateURL)
try firstStore.addFolder(url: rootURL)
await firstStore.refresh()
let entryID = try! firstStore.entries.first!.id
firstStore.setWatched(entryID: entryID, value: true)
firstStore.markOpened(entryID: entryID)
firstStore.toggleWatchlist(entryID: entryID)
let secondStore = LocalLibraryStore(fileURL: stateURL)
precondition(secondStore.entries.first(where: { $0.id == entryID })?.isWatched == true)
```

- [ ] **Step 2: 运行测试确认失败**

预期因 `LocalLibraryStore` 尚未定义而失败。

- [ ] **Step 3: 实现商店初始化和保存**

商店从 `LocalLibraryPersistence` 加载快照；所有写操作立即保存；通过 `@Published` 发布状态。JSON 不存在时创建空片库，不影响 `MovieStore` 启动。

- [ ] **Step 4: 实现添加目录和刷新入口**

`addFolder(url:)` 创建目录 bookmark、去重并保存；`refresh()` 解析所有书签，调用 `LocalLibraryScanner`，合并结果并保存。刷新按钮重复触发时忽略第二次请求，避免并发扫描覆盖状态。

- [ ] **Step 5: 实现重新定位和用户状态操作**

`reattach(entryID:url:)` 使用文件签名校验新路径；相符时仅更新 folder/relative path 和状态，不覆盖匹配、收藏和已看。`markOpened` 更新最近打开时间，`setWatched` 和 `toggleWatchlist` 只更新本地状态。

- [ ] **Step 6: 运行回归测试确认通过**

运行 `/tmp/cinebar-tests/CineBarRegressionTests`，确认恢复、刷新、重新定位和状态持久化均 PASS。

- [ ] **Step 7: 提交**

```bash
git add CineBar/Sources/CineBar/LocalLibraryStore.swift \
  CineBar/Tests/RegressionBehaviorTests.swift
git commit -m "feat: persist local library state"
```

### Task 4: 实现播放器回退和 TMDB 匹配适配层

**Files:**
- Create: `CineBar/Sources/CineBar/LocalLibraryPlayback.swift`
- Create: `CineBar/Sources/CineBar/LocalLibraryMatchService.swift`
- Modify: `CineBar/Tests/RegressionBehaviorTests.swift`

**Interfaces:**
- Produces `enum ExternalPlayerKind { case iina, vlc, system }`。
- Produces `ExternalPlayerResolver.resolve(availableBundleIDs:) -> [ExternalPlayerKind]`。
- Produces `ExternalPlayerLauncher.open(fileURL:)`。
- Produces `LocalLibraryMatchCandidate` 和 `LocalLibraryMatchService.search(for:) async throws`。

- [ ] **Step 1: 写播放器回退测试**

```swift
precondition(
    ExternalPlayerResolver.resolve(
        availableBundleIDs: ["org.videolan.vlc"]
    ) == [.vlc, .system]
)
precondition(
    ExternalPlayerResolver.resolve(
        availableBundleIDs: ["com.colliderli.iina", "org.videolan.vlc"]
    ) == [.iina, .vlc, .system]
)
precondition(
    ExternalPlayerResolver.resolve(availableBundleIDs: []) == [.system]
)
```

- [ ] **Step 2: 运行测试确认失败**

预期因播放器解析器尚未定义而失败。

- [ ] **Step 3: 实现播放器解析和启动**

使用 `NSWorkspace.urlForApplication(toOpen:)` 或 bundle ID 查询应用；`ExternalPlayerLauncher` 先用 `open(_:withApplicationAt:configuration:)` 启动 IINA/VLC，全部不可用时调用 `NSWorkspace.shared.open(fileURL)`。启动后只由商店更新最近打开时间，不读取播放进度。

- [ ] **Step 4: 写匹配候选测试和适配层**

测试候选转换不会丢失 TMDB ID、类型、年份、海报 URL 和评分。`LocalLibraryMatchService` 使用现有 `TMDBClient.search` / `searchTV`，根据解析出的标题选择对应接口；网络错误原样返回给 UI，不能删除本地条目。

- [ ] **Step 5: 运行测试确认通过**

运行 Swift 回归测试，预期播放器回退和候选转换 PASS。

- [ ] **Step 6: 提交**

```bash
git add CineBar/Sources/CineBar/LocalLibraryPlayback.swift \
  CineBar/Sources/CineBar/LocalLibraryMatchService.swift \
  CineBar/Tests/RegressionBehaviorTests.swift
git commit -m "feat: add local playback and metadata matching"
```

### Task 5: 接入 CineBar 主导航和本地片库界面

**Files:**
- Create: `CineBar/Sources/CineBar/LocalLibraryView.swift`
- Modify: `CineBar/Sources/CineBar/main.swift`

**Interfaces:**
- `LocalLibraryView` 接收 `@ObservedObject var store: LocalLibraryStore`、`@ObservedObject var movieStore: MovieStore`。
- `ContentView` 接收并传递同一个 `LocalLibraryStore` 实例。
- `MainBrowseSection` 新增 `.localLibrary`，并为五种语言提供标题。

- [ ] **Step 1: 先增加导航和 UI 回归检查**

在 `RegressionBehaviorTests.swift` 增加枚举断言：

```swift
precondition(MainBrowseSection.allCases.contains(.localLibrary))
for language in AppLanguage.allCases {
    precondition(
        !MainBrowseSection.localLibrary.title(language: language).isEmpty
    )
}
```

- [ ] **Step 2: 运行测试确认失败**

预期因导航枚举和新视图尚未加入而失败。

- [ ] **Step 3: 扩展主导航状态**

在 `MovieStore` 增加 `isShowingLocalLibrary`；`mainBrowseSection` 在本地片库时返回 `.localLibrary`。选择电影、电视剧或我的片单时清除本地片库状态；选择本地片库时清除详情页、搜索、分类面板和预告播放状态，不触发在线 TMDB 列表刷新。

- [ ] **Step 4: 注入独立商店**

`AppDelegate` 持有 `private let localLibraryStore = LocalLibraryStore()`，创建 `ContentView(store: store, localLibraryStore: localLibraryStore)`。保留现有 `MovieStore` 实例和窗口行为，不改变更新、设置和菜单栏逻辑。

- [ ] **Step 5: 实现本地片库页面**

页面包含：标题、已添加目录数量、“添加文件夹”按钮、“刷新”按钮、扫描进度、搜索框、全部/未看/待匹配/文件不可用筛选。列表行显示海报或文件图标、匹配片名/文件名、年份、类型、状态、播放、已看和片单按钮。

播放动作调用 `LocalLibraryStore.markOpened` 后交给 `ExternalPlayerLauncher`；匹配动作展示候选 sheet，确认时调用 `updateMetadata`；跳过匹配不影响播放。

- [ ] **Step 6: 实现文件夹选择、重新定位和失效提示**

使用 `NSOpenPanel` 只允许选择目录；重新定位使用文件选择器选择单个视频文件。外置盘未连接时显示“存储卷未连接”，文件移动/删除时显示“重新定位文件”。

- [ ] **Step 7: 运行 Swift 回归和类型检查**

```bash
xcrun swiftc -parse-as-library -D CINEBAR_TEST \
  CineBar/Sources/CineBar/*.swift \
  CineBar/Tests/RegressionBehaviorTests.swift \
  -o /tmp/cinebar-tests/CineBarRegressionTests
/tmp/cinebar-tests/CineBarRegressionTests
xcrun swiftc -parse-as-library -typecheck CineBar/Sources/CineBar/*.swift
```

预期：两条命令均成功；手动检查本地片库分页不会显示电影/电视剧搜索栏，不会改变现有片单和详情行为。

- [ ] **Step 8: 提交**

```bash
git add CineBar/Sources/CineBar/main.swift \
  CineBar/Sources/CineBar/LocalLibraryView.swift
git commit -m "feat: add CineBar local library UI"
```

### Task 6: 添加五语言文案、安装说明和 Build 23 发布资料

**Files:**
- Modify: `CineBar/Assets/Localization/en.lproj/Localizable.strings`
- Modify: `CineBar/Assets/Localization/ja.lproj/Localizable.strings`
- Modify: `CineBar/Assets/Localization/ko.lproj/Localizable.strings`
- Modify: `CineBar/Assets/Localization/zh-Hans.lproj/Localizable.strings`
- Modify: `CineBar/Assets/Localization/zh-Hant.lproj/Localizable.strings`
- Modify: `CineBar/Info.plist`
- Create: `CineBar/ReleaseNotes/0.8.3-test.7-Build-23.txt`
- Modify: `CineBar/README.md`
- Modify: `CineBar/请先阅读-测试版安装说明.html`
- Modify: `CineBar/请先阅读-测试版安装说明.txt`
- Modify: `CineBarWebsite/app/page.tsx`
- Modify: `CineBarWebsite/tests/content.test.mjs`
- Modify: `CineBarShare/worker.js`
- Modify: `CineBarShare/tests/share-worker.test.mjs`

- [ ] **Step 1: 增加五语言本地片库文案**

为“本地片库、添加文件夹、刷新、扫描中、待匹配、确认匹配、重新定位文件、文件不可用、存储卷未连接、已看、未看、播放、匹配影片”提供五种语言字符串；界面不得把中文硬编码到英文、日文或韩文路径。

- [ ] **Step 2: 更新版本和说明**

将 `CFBundleVersion` 从 `22` 改为 `23`，短版本仍为 `0.8.3`。新增说明内容：本地片库、目录刷新、新增影片自动加入、IINA/VLC 回退、TMDB 匹配需确认、断网仍可播放。说明必须明确不提供下载资源。

- [ ] **Step 3: 更新官网和分享服务版本**

官网改为 `0.8.3-test.7（Build 23）`，功能列表增加“本地片库”；更新网站内容测试。Share worker 的 `/health` 和 `/updates/latest.json` 改为 `0.8.3-test.7` / Build 23，更新迁移说明为“Build 22 用户可直接在 CineBar 内更新到 Build 23”，并同步测试断言。

- [ ] **Step 4: 运行文案与静态检查**

```bash
node --test CineBar/Tools/tests/*.test.mjs
git diff --check
```

预期：通过，且没有旧 Build 22 作为当前版本残留在官网、更新清单或应用新功能说明中；历史 ReleaseNotes 可以保留。

- [ ] **Step 5: 提交发布资料**

```bash
git add CineBar/Assets/Localization CineBar/Info.plist \
  CineBar/ReleaseNotes CineBar/README.md \
  CineBar/请先阅读-测试版安装说明.html \
  CineBar/请先阅读-测试版安装说明.txt \
  CineBarWebsite/app/page.tsx CineBarWebsite/tests/content.test.mjs \
  CineBarShare/worker.js CineBarShare/tests/share-worker.test.mjs
git commit -m "release: prepare CineBar Build 23 local library"
```

### Task 7: 构建、签名验证、发布和最终验收

**Files/Artifacts:**
- Create: `dist/CineBar-0.8.3-test-build-23-universal.zip`
- Copy: `CineBarWebsite/public/downloads/CineBar-0.8.3-test-build-23-universal.zip`
- Modify: `CineBarWebsite/public/appcast.xml`

- [ ] **Step 1: 运行完整本地测试**

```bash
xcrun swiftc -parse-as-library -D CINEBAR_TEST \
  CineBar/Sources/CineBar/*.swift \
  CineBar/Tests/RegressionBehaviorTests.swift \
  -o /tmp/cinebar-tests/CineBarRegressionTests
/tmp/cinebar-tests/CineBarRegressionTests
node --test CineBar/Tools/tests/*.test.mjs
node --test CineBarShare/tests/share-worker.test.mjs
(cd CineBarWebsite && npm test)
git diff --check
```

预期：Swift、工具、Share worker、官网测试全部 PASS。

- [ ] **Step 2: 构建 Universal 测试包**

执行：

```bash
CineBar/Tools/build_test_package.sh
```

确认输出为 `dist/CineBar-0.8.3-test-build-23-universal.zip`，解压后检查 `CineBar.app/Contents/Info.plist` 的 Build 23、五个 `.lproj`、安装说明、ReleaseNotes 和本地片库新 Swift 代码均在包内。用 `lipo -info` 确认包含 `arm64` 和 `x86_64`。

- [ ] **Step 3: 发布 Sparkle appcast**

先复制下载包：

```bash
cp dist/CineBar-0.8.3-test-build-23-universal.zip \
  CineBarWebsite/public/downloads/CineBar-0.8.3-test-build-23-universal.zip
```

再执行：

```bash
CineBar/Tools/publish_sparkle_update.sh \
  dist/CineBar-0.8.3-test-build-23-universal.zip \
  https://cinebar.cc/downloads/CineBar-0.8.3-test-build-23-universal.zip \
  0.8.3-test.7 23 2026-08-02 \
  CineBar/ReleaseNotes/0.8.3-test.7-Build-23.txt
```

用 Sparkle `sign_update --verify` 验证签名，并确认 appcast Build 23 的 length 与 zip 实际字节数相同；不得覆盖旧 Build 22 的同版本 URL。

- [ ] **Step 4: 部署官网和 Share worker**

```bash
(cd CineBarWebsite && npm run deploy:public)
(cd CineBarShare && npx wrangler deploy --config wrangler.jsonc)
```

上线后检查：

```bash
curl -fsSL https://cinebar.cc/appcast.xml
curl -fsSL https://cinebar.cc/downloads/CineBar-0.8.3-test-build-23-universal.zip -o /tmp/CineBar-B23.zip
curl -fsSL https://share.cinebar.cc/updates/latest.json
curl -fsSL https://share.cinebar.cc/health
```

远端包的 SHA-256 必须与本地 `dist` 包一致；更新清单、官网和健康检查均必须显示 Build 23。

- [ ] **Step 5: 手动验收本地片库**

在干净用户目录中：添加多层目录，点击刷新确认新文件加入；重复刷新确认不重复；匹配一个同名影片并确认；断网打开已索引文件；卸载 IINA 后确认 VLC 回退；移除外置卷确认状态提示；重新连接或重新定位后确认状态、片单和已看标记保留。

- [ ] **Step 6: 最终提交和交付记录**

```bash
git add CineBarWebsite/public/appcast.xml \
  CineBarWebsite/public/downloads/CineBar-0.8.3-test-build-23-universal.zip \
  dist/CineBar-0.8.3-test-build-23-universal.zip
git commit -m "build: publish CineBar Build 23"
```

交付时报告：Universal zip 路径、SHA-256、Sparkle appcast URL、官网 URL、远端 Share worker 状态和全部测试结果。

## Self-review checklist

- 规格中的新增影片刷新、去重、状态保留和 TMDB 不重复请求分别由 Task 2、Task 3 和 Task 5 覆盖。
- 规格中的 IINA/VLC/系统播放器回退由 Task 4 实现并测试。
- 规格中的 security-scoped bookmark、断开外置卷和重新定位由 Task 2/3 覆盖。
- 规格中的五语言、旧版本兼容和在线更新由 Task 6/7 覆盖。
- 未发现占位符、空泛的“稍后处理”或未定义的方法名。
- 所有跨任务接口在“Interfaces shared between tasks”或对应任务中声明。
- 构建脚本已经使用 `Sources/CineBar/*.swift`，新增 Swift 文件无需修改脚本；Task 7 仍执行完整类型检查和 Universal 构建。
