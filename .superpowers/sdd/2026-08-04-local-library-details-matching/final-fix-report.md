# Local Library final-fix report — CineBar 0.8.3-test.12 Build 28

日期：2026-08-05（Asia/Shanghai）

## 范围与提交来源

- 审查基线：`5fb01e7b8c030568b33070ef29c37144a5d9ef7b`
- 修复起点：`62c05dbafb6aab0443210d2d84e4a3e820556aee`
- Build 28 干净构建输入提交：`e27d6c5239cbb4aa2e26af21fbe75f3312e85017`
- Build 28 source tree：`d5291df426202d46eb941cdcaa44fb5d7396b8e6`
- short version：`0.8.3`
- test version：`0.8.3-test.12`
- `CFBundleVersion`：`28`
- 未新增账号、盗版资源或数据源；TMDB、OMDb、TVMaze 与 CineBar 评分策略未改变。

## Finding 1：初始自动建议的竞态与取消

修复证据：

- `LocalLibraryView.findMatches` 不再启动无句柄 `Task`，而是立即创建匹配 session。
- 初始自动建议在 sheet `onAppear` 后启动，与手动搜索共同进入 `performSearch`。
- `LocalLibraryMatchSearchState` 的 request token 同时携带 generation 与 entry ID；只有当前 token 可以提交候选或错误。
- 新请求先使旧 token 失效并取消旧 `Task`；关闭、跳过、sheet 消失和确认都取消当前任务。
- 初始建议仍调用 `search(for: entry)`，因此不会丢失文件名解析出的年份；手动搜索继续调用 `search(query:)`。

测试证据：

- 先加纯状态回归，再实现 `begin(entryID:)`、`cancel(entryID:)`、`confirm(entryID:)`。红灯编译输出包括：
  `argument passed to call that takes no arguments`、`has no member 'cancel'`、`has no member 'confirm'`。
- 回归覆盖：A 慢 B 快（B 先完成，A 的迟到结果被拒绝）、请求中关闭、确认后迟到响应。
- Node 源码回归确认初始与手动搜索共用同一任务管线，并确认 `findMatches` 中已无裸 `Task`。

## Finding 2：标题相等时年份 bonus 不可达

修复证据：

- 完全相等标题使用 `0.9` 的标题基础分，不再提前返回 `1`。
- 年份一致后统一加 `0.1`，最高为 `1`；非完全相等标题上限保留为 `0.89`，避免模糊标题在无年份时压过完全相等标题。
- 排序继续依次使用 confidence、`voteAverage`、标题、ID，保持确定性与既有评分 tie-break。
- 回归用两个同名 `Dune` 候选：1984 版评分 1，2021 版评分 10；文件名年份为 1984，最终顺序必须是 `[1984, 2021]`。

测试证据：

- 临时恢复旧的 `if candidateTitle == queryTitle { return 1 }` 后，Swift 回归在年份顺序断言处输出 `Precondition failed`；恢复修复后退出 0。

## Finding 3：未知上映年份确认后无法进入详情

修复证据：

- `LocalLibraryDetailBridge` 仍校验媒体类型、正 ID 和非空标题，但不再要求四位年份。
- 合法四位年份仍转换成 `yyyy-01-01`；未知或非四位年份转换为 `releaseDate = nil` / `firstAirDate = nil`。
- 回归覆盖电影和电视剧的未知年份桥接，以及一个原始 `.other` 条目经 `confirmMatch` 变为已确认电影后，使用 nil date 桥接进入既有电影模型。

测试证据：

- 临时恢复电影桥接的四位年份 guard 后，Swift 回归在未知年份桥接处输出
  `Fatal error: Unexpectedly found nil while unwrapping an Optional value`；恢复修复后退出 0。

## Finding 4：range whitespace

- 移除了 `docs/superpowers/specs/2026-08-02-cinebar-local-library-design.md` 的两处尾随空格。
- 移除了 `docs/superpowers/plans/2026-08-04-local-library-details-matching.md` 的 EOF 空行。
- 明确 range 检查还指出 `docs/superpowers/plans/2026-08-03-cinebar-local-library-classification.md` 有一个 EOF 空行；只移除了这一处，否则 `git diff --check 5fb01e7..HEAD` 不可能通过。

## Build 28 元数据与发布内容

- Settings/About/New Features、README、ASCII `INSTALL.md`、中文 HTML/TXT 安装说明与五种本地化同步到 Build 28。
- 新增 `CineBar/ReleaseNotes/0.8.3-test.12-Build-28.txt`。
- 官网版本、health 和下载链接同步到 Build 28。
- `CineBarWebsite/public/appcast.xml` 首项为 28，历史顺序为 `28 → 27 → 26 → 25 → 24 → 23`。
- Build 28 使用新 URL；未覆盖 Build 27 URL 或文件。
- 所有文档继续明确：应用是 ad-hoc 签名，不是 Apple Developer ID，未经 Apple 公证；Sparkle EdDSA 只验证更新归档。
- ASCII `INSTALL.md` 已在 ZIP 交付根目录核验存在。

## 测试与真实输出

### Swift 全源回归

```bash
xcrun swiftc -parse-as-library -D CINEBAR_TEST \
  CineBar/Sources/CineBar/*.swift \
  CineBar/Tests/RegressionBehaviorTests.swift \
  -o /tmp/cinebar-tests/CineBarRegressionTests
/tmp/cinebar-tests/CineBarRegressionTests
```

最终输出：无 stdout，退出码 0。

### CineBar Tools

```bash
node --test CineBar/Tools/tests/*.test.mjs
```

最终输出：`tests 18`、`pass 18`、`fail 0`。

### 官网

```bash
cd CineBarWebsite
npm test
npm run lint
CI=1 npm run deploy:dry-run
```

真实输出：

- `npm test`：vinext build 成功；`tests 18`、`pass 18`、`fail 0`。
- `npm run lint`：0 errors、1 个既有 `@next/next/no-img-element` warning，位置为 `app/page.tsx:20`。
- `CI=1 npm run deploy:dry-run`：退出码 0；读取 31 个静态文件并输出 `--dry-run: exiting now.`。
- 一次未带 `CI=1` 的 dry-run 已输出成功清单但 npm 外壳未自行退出，确认没有 Wrangler 子进程后手动中断；随后上述 `CI=1` 命令完整退出 0。
- 一次在仓库根目录误执行 `npm test` 得到缺少根 `package.json` 的 `ENOENT`；在正确的 `CineBarWebsite` 目录重跑后得到上述 18/18 结果。

### Diff whitespace

最终提交后要求运行：

```bash
git diff --check 5fb01e7b8c030568b33070ef29c37144a5d9ef7b..HEAD
```

预期且最终验收标准：无输出，退出码 0。

## ZIP、manifest、架构与代码签名

- ZIP：`/Users/bruce/Documents/Codex/2026-07-25/you/work/.worktrees/test-rating-lock-multiscreen/dist/CineBar-0.8.3-test-build-28-universal.zip`
- 大小：`6010619` bytes
- SHA-256：`fa7b63d79b2ce42ba1ff2da9d5e313207629eebcd14c557a83ad517ebf75459a`
- manifest（交付根目录与 app 内副本相同）：

```json
{"commit":"e27d6c5239cbb4aa2e26af21fbe75f3312e85017","sourceTree":"d5291df426202d46eb941cdcaa44fb5d7396b8e6","version":"0.8.3","build":"28","sourceTreeStatus":"clean"}
```

- app 内 Info.plist：short version `0.8.3`、build `28`。
- `lipo -archs`：`x86_64 arm64`。
- `codesign --verify --deep --strict --verbose=2`：valid on disk，satisfies Designated Requirement。
- `codesign -dv --verbose=4`：`Signature=adhoc`、`TeamIdentifier=not set`、Mach-O universal。
- `spctl --assess --type execute -vv`：`rejected`，与非 Developer ID、未公证披露一致。

## Appcast 与 EdDSA

- Build 28 URL：`https://cinebar.cc/downloads/CineBar-0.8.3-test-build-28-universal.zip`
- `sparkle:version`：`28`
- `sparkle:shortVersionString`：`0.8.3-test.12`
- `length`：`6010619`
- EdDSA：`iwzWZKc2nXeLDEF+tt3DsOGS5WmoeFSSUeJew6BnoZ+B/IgFRREbHZum5X5ivzXIB3WTnUBmCPjgL3YZapF2Ag==`
- Sparkle `sign_update --verify` 对本地 ZIP 和公网下载 ZIP 均退出 0。
- Build 27 appcast item 在插入 Build 28 前后 SHA-256 都是
  `6d9457a6644d785a652250f71eab410386dafdda22735fb067135ab936cb6545`。
- Build 27 静态 ZIP 在部署前后 SHA-256 都是
  `4a69faf3352e7f05f3219e0f28cea2745531d4fed903c8559c22fa26e24c4adc`。

## 部署与公网核验

部署命令：

```bash
cd CineBarWebsite
CI=1 npm run deploy:public
```

真实输出：

- Wrangler 只上传两个新或变化资产：`/appcast.xml` 和
  `/downloads/CineBar-0.8.3-test-build-28-universal.zip`。
- Worker：`cinebar-website`
- custom domain：`cinebar.cc`
- Current Version ID：`e9e50f31-7730-4a18-bfa7-373ee118a78b`

公网核验：

- `https://cinebar.cc/?build=28`：HTTP 200，含 `0.8.3-test.12（Build 28）`。
- `https://cinebar.cc/health?build=28`：HTTP 200，返回
  `0.8.3-test.12-build-28`。
- `https://cinebar.cc/appcast.xml?build=28`：HTTP 200，XML 合法，顺序
  `28 → 27 → 26 → 25 → 24 → 23`。
- Build 28 URL：HTTP 200，`6010619` bytes，SHA-256 与本地一致。
- Build 27 URL：HTTP 200，SHA-256 与部署前跟踪文件一致。
- 公网 Build 28 ZIP 与本地 ZIP `cmp` 一致，Sparkle EdDSA 验证退出 0。

## 尚未执行的手工项

- 未执行真实 GUI 流程：Local Library → Other Videos → 关闭详情 → 模糊匹配 → 最佳建议 → 确认 → Movie/TV 详情 → Back 保留筛选。
- 未对真实 TMDB 网络响应做端到端交互测试；自动与手动搜索使用的是既有数据策略，回归使用受控闭包/模型。
- 未在已安装旧版中执行真实 Sparkle 检查、下载、替换和重启；只完成 appcast/ZIP/EdDSA 的 CLI 核验。
- 未执行真实 Finder 首次启动、Control-click Open 或 Gatekeeper 交互；`spctl` 对 ad-hoc、未公证 app 的拒绝已记录。
- 未做 Apple Developer ID 签名或 Apple 公证，且本次发布明确不声称已完成这些项目。

## 保留项

所有任务开始前已有的未跟踪 Build 18 目录、替身 ZIP、`.superpowers/brainstorm/` 和
`task-7-report.md` 均未清理、未覆盖、未加入提交。
