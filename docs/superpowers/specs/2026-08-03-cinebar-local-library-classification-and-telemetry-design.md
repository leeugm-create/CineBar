# CineBar 本地片库分类、手动匹配与匿名安装统计设计规格

日期：2026-08-03
状态：设计已确认，等待实施计划
范围：macOS CineBar 本地片库与 Cloudflare 匿名安装统计

## 1. 目标

本次改动解决两个问题：

1. 本地片库扫描到的自拍、相机视频、录屏等零碎视频不应污染电影/电视剧匹配；它们仍要保留并可播放。
2. 用户可以按电影名或电视剧名手动搜索 TMDB 元数据，看到候选后自行确认匹配；匹配窗口和片库页面都要有明确的关闭入口。
3. 提供一个强制开启、但最小化且明确披露的匿名安装实例统计，供作者在统一管理页面查看。

本次只处理本地文件索引和合法元数据匹配，不抓取或聚合下载链接、磁力链接、迅雷链接或第三方片源。

## 2. 非目标

- 不自动确认 TMDB 匹配。
- 不把个人视频上传到服务器或发送给 TMDB。
- 不把本地文件路径、文件名、文件内容、Apple ID 或用户名发送到统计服务。
- 不将匿名安装实例数表述为真实用户数。
- 不在本次设计中引入账号登录系统。

## 3. 产品规则

### 3.1 条目分类

每个本地文件条目新增 `contentCategory`：

- `movie`：电影候选或已确认电影。
- `television`：电视剧候选或已确认电视剧。
- `other`：个人视频、录屏、相机视频、无可靠片名的视频。

个人视频保留在本地片库中，可以播放、标记已看、加入片单和搜索文件名，但不会参与电影/电视剧候选列表。

### 3.2 保守的自动候选

刷新时扫描器只生成候选，不写入 TMDB metadata，也不自动确认。

文件名清理规则：

- 移除分辨率、编码、字幕、压制组和常见发布标签。
- 解析四位年份。
- 解析 `S01E02`、`Season 1` 等电视剧标记。
- `IMG_`、`VID_`、`PXL_`、录屏命名、纯时间戳、清理后没有有效标题的文件直接归入 `other`。
- 其余有可信标题的文件进入 `unmatched` 或 `suggested`，但只显示候选，不持久化匹配结果。

候选搜索使用现有 TMDB 代理。候选必须由用户点击“确认匹配”后才写入海报、片名、年份、类型、评分和简介。

### 3.3 手动匹配

匹配窗口包含：

- 可编辑搜索框，默认填充清理后的文件名。
- `电影 / 电视剧` 类型切换。
- 搜索按钮和加载状态。
- 候选海报、片名、年份、类型、评分和简介。
- 每个候选的“确认匹配”按钮。
- “跳过”按钮，关闭窗口且不改变文件和播放能力。

确认新的候选会覆盖旧 metadata，但保留已看、片单和最近打开时间。搜索失败或无结果时，条目继续保持 `other` 或 `unmatched`，不会阻止播放。

### 3.4 片库筛选与关闭

片库筛选新增：

- 全部
- 电影
- 电视剧
- 其他视频
- 待匹配
- 未看
- 文件不可用

片库左上角增加 `xmark.circle.fill` 关闭按钮，行为与主列表一致：只隐藏 CineBar 面板，不退出应用。扫描或匹配进行中仍可关闭，任务在后台继续；再次打开后恢复状态。

## 4. 数据模型与迁移

在 `LocalLibraryEntry` 增加：

```swift
enum LocalLibraryContentCategory: String, Codable, Hashable {
    case movie
    case television
    case other
}

var contentCategory: LocalLibraryContentCategory
```

迁移规则：

- 已有 `metadata.kind == .movie` 的条目设为 `movie`。
- 已有 `metadata.kind == .television` 的条目设为 `television`。
- 没有 metadata 的旧条目按文件名保守规则重新分类。
- 缺失字段使用 `other`，避免旧 JSON 导致应用启动失败。
- 现有文件签名、目录书签、已看、片单、最近打开时间和文件状态保持不变。

`LocalLibraryRefreshMerger` 必须按文件的目录 ID + 规范化相对路径去重，并在刷新时保留已有条目的用户状态和已确认 metadata。

## 5. 组件边界

### `LocalLibraryScanner`

负责递归扫描授权目录、识别媒体文件、解析文件名并生成分类/候选提示。不得执行网络请求，不得写入 metadata。

### `LocalLibraryMatchService`

负责通过 TMDB 代理搜索电影和电视剧，接受用户提供的搜索词和媒体类型，返回可展示的候选。自动候选和手动搜索共用候选转换逻辑。

### `LocalLibraryStore`

负责分类、匹配确认、状态迁移、持久化和扫描结果合并。不负责 UI 和播放器启动。

### `LocalLibraryView`

负责分类筛选、关闭按钮、匹配入口、手动搜索界面、确认操作、播放和本地状态展示。

### `CineBarTelemetryClient`

负责生成/读取本机随机安装实例 ID、限制上报频率、发送匿名安装事件。不读取本地片库内容。

### `CineBarTelemetryWorker`

负责验证请求格式、哈希安装实例、写入 D1、提供管理员统计接口。不得返回原始安装实例 ID。

### `CineBarTelemetryDashboard`

负责在 `https://cinebar.cc/admin/analytics` 展示聚合统计。必须受 Cloudflare Access 或 Worker 管理员 Token 保护。

## 6. 匿名统计协议

客户端首次启动生成随机 UUID 作为本机安装实例 ID，并在本机保存。每次启动最多上报一次；网络失败时静默跳过，不阻塞主界面。

客户端只发送：

```json
{
  "install_id": "random-uuid",
  "app_version": "0.8.3-test.9",
  "build": 25,
  "platform": "macOS",
  "os_major": 15,
  "architecture": "arm64",
  "language": "zh-CN",
  "occurred_at": "2026-08-03T00:00:00Z"
}
```

Worker 在写入前使用服务端密钥对 `install_id` 进行 HMAC，D1 不保存原始 ID。服务端不保存原始 IP，只保留聚合所需字段和最近活跃时间。

建议 D1 表：

```sql
CREATE TABLE installation_events (
  install_hash TEXT PRIMARY KEY,
  first_seen_at TEXT NOT NULL,
  last_seen_at TEXT NOT NULL,
  app_version TEXT NOT NULL,
  build INTEGER NOT NULL,
  platform TEXT NOT NULL,
  os_major INTEGER NOT NULL,
  architecture TEXT NOT NULL,
  language TEXT NOT NULL
);

CREATE INDEX installation_events_last_seen_idx
  ON installation_events(last_seen_at);
CREATE INDEX installation_events_version_idx
  ON installation_events(app_version, build);
```

统计默认开启且不提供客户端关闭按钮，但必须在安装说明、官网隐私说明和应用“关于”页面披露：应用会发送匿名安装实例与版本信息，不发送本地文件或个人身份数据。

## 7. 统计页面

管理页面提供：

- 累计安装实例数。
- 近 30 天活跃安装实例数。
- 按版本和 Build 分布。
- Apple 芯片 / Intel 分布。
- macOS 主版本分布。
- 语言分布。
- 最近上报时间。

页面必须显示说明：“安装实例数，不等于真实用户数”。卸载重装、清理数据、离线使用和用户网络阻断都会导致漏报；同一用户在多台机器上会计为多个实例。

## 8. 隐私与安全

- 统计接口只接受固定 JSON 字段和合理长度，拒绝额外字段。
- 管理接口不得公开；没有管理员凭据时返回 404 或 401。
- 统计请求不包含电影标题、文件名、路径、播放记录或目录书签。
- 片库匹配只把搜索词发送到现有 TMDB 代理，不上传本地视频。
- 所有远程请求继续使用 HTTPS 和现有端点回退策略。
- 遥测失败不能影响片库扫描、播放或应用启动。

## 9. 测试与验收

### 本地片库

- 相机命名和录屏文件被归入 `other`。
- 含可信电影名和年份的文件进入待匹配候选，但刷新后 metadata 仍为空。
- `S01E02` 和 `Season 1` 文件可进入电视剧候选。
- 其他视频不会出现在电影/电视剧筛选结果中。
- 手动搜索支持修改关键词和切换电影/电视剧。
- 只有确认候选后 metadata 才写入；重新确认会覆盖 metadata 但保留用户状态。
- 重启后分类、匹配和状态保持。
- 片库关闭按钮只隐藏窗口，不终止进程。
- 扫描进行中关闭并重新打开不会丢失任务状态。

### 匿名统计

- 首次启动生成并持久化随机安装 ID。
- 同一安装实例重复启动不会重复增加累计实例。
- 不同安装实例可以分别统计。
- 请求失败不阻塞应用。
- Worker 拒绝缺字段、超长字段和未知字段。
- D1 聚合查询返回累计、活跃、版本、架构和语言统计。
- 管理页面未授权时不可读取统计数据。

## 10. 发布与迁移

- 先完成本地片库数据迁移和测试，再接入遥测 Worker/D1。
- 更新应用版本和简短更新说明，保留旧版本 appcast 条目。
- 更新官网隐私说明、安装说明和应用“关于”文案。
- 发布前验证远程 Worker、D1 绑定、管理员保护、客户端上报和 Sparkle 更新包。
