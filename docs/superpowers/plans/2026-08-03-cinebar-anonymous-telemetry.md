# CineBar Anonymous Installation Telemetry Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 通过 Cloudflare Worker + D1 统计匿名安装实例和版本分布，并在受保护的统一页面查看。

**Architecture:** macOS 客户端生成随机安装实例 ID，启动时低频上报固定字段；Worker 使用 HMAC 将 ID 转为不可逆哈希后写入 D1；统计页面只输出聚合数据并由 Cloudflare Access 或 Worker 管理员 Token 保护。客户端默认开启且没有关闭按钮，但在应用和官网隐私说明中明确披露。

**Tech Stack:** Swift/Foundation、Cloudflare Workers、D1、Wrangler、Node.js `node:test`、现有 CineBarWebsite 部署。

## Global Constraints

- 不收集 Apple ID、用户名、本地路径、文件名、电影信息或播放记录。
- 不把原始 IP 写入 D1，也不向管理页面返回原始安装 ID。
- 客户端统计默认开启，不提供关闭按钮；必须在安装说明、官网隐私说明和关于页面披露。
- 统计失败不得阻塞应用启动、片库扫描、播放或在线更新。
- 管理页面必须鉴权；未授权请求返回 401/404。
- 统计文案必须使用“安装实例数”，不能写“真实用户数”。
- 与 Build 26 一起发布，版本为 `0.8.3-test.10`。

## 文件结构与职责

- Create: `CineBarTelemetry/schema.sql` — D1 表和索引。
- Create: `CineBarTelemetry/package.json` — Worker 测试脚本和 Node.js 模块配置。
- Create: `CineBarTelemetry/wrangler.jsonc` — Worker 名称、D1 绑定和路由。
- Create: `CineBarTelemetry/worker.js` — 上报、聚合和鉴权接口。
- Create: `CineBarTelemetry/tests/telemetry-worker.test.mjs` — Worker 协议和聚合测试。
- Modify: `CineBar/Sources/CineBar/main.swift` — 客户端遥测模型、ID 持久化和启动上报。
- Modify: `CineBar/Tests/RegressionBehaviorTests.swift` — 客户端 ID、频率和失败隔离测试。
- Modify: `CineBar/Assets/Localization/*/Localizable.strings` — 匿名统计披露文案。
- Modify: `CineBar/README.md`、`CineBar/INSTALL.md`、安装说明 HTML/TXT — 隐私披露。
- Modify: `CineBarWebsite/app/page.tsx`、`CineBarWebsite/app/globals.css` — 统计入口/隐私链接。
- Create: `CineBarWebsite/app/admin/analytics/page.tsx` — 受保护的统计页面代理。
- Modify: `CineBarWebsite/tests/content.test.mjs` — 隐私和统计文案测试。
- Modify: `CineBarWebsite/wrangler.public.jsonc` — 管理页面部署配置。

## Shared Interfaces

```swift
struct TelemetryInstallPayload: Codable, Hashable {
    let installID: String
    let appVersion: String
    let build: Int
    let platform: String
    let osMajor: Int
    let architecture: String
    let language: String
    let occurredAt: Date
}

struct CineBarTelemetryClient {
    func recordLaunchIfNeeded() async
}
```

```text
POST /v1/telemetry/install
GET  /v1/telemetry/summary?range=30d
GET  /health
```

### Task 1: 建立 D1 schema 和 Worker 上报接口

**Files:**
- Create: `CineBarTelemetry/schema.sql`
- Create: `CineBarTelemetry/wrangler.jsonc`
- Create: `CineBarTelemetry/worker.js`
- Create: `CineBarTelemetry/tests/telemetry-worker.test.mjs`

**Interfaces:** `POST /v1/telemetry/install`、`GET /health`。

- [ ] **Step 1: 写失败测试**

在 `telemetry-worker.test.mjs` 中测试：合法 payload 返回 204；缺少字段、未知字段、超长字符串和错误 Content-Type 返回 400；重复 install hash 使用 upsert 不增加第二条记录。先创建不依赖第三方包的 `package.json`：

```json
{
  "name": "cinebar-telemetry",
  "private": true,
  "type": "module",
  "scripts": { "test": "node --test tests/telemetry-worker.test.mjs" }
}
```

- [ ] **Step 2: 运行测试确认失败**

```bash
cd CineBarTelemetry
npm test
```

预期：Worker handler 尚未定义而失败。

- [ ] **Step 3: 创建 D1 schema**

创建 `installation_events` 表，字段为 `install_hash`、`first_seen_at`、`last_seen_at`、`app_version`、`build`、`platform`、`os_major`、`architecture`、`language`，并添加最近活跃和版本索引。

- [ ] **Step 4: 实现固定字段验证和 HMAC**

Worker 只接受固定 JSON 字段；使用 `env.TELEMETRY_HMAC_SECRET` 对 install ID 做 HMAC-SHA256；D1 只保存 hash 和聚合字段。不要记录 request headers 或原始 IP。

- [ ] **Step 5: 实现幂等 upsert**

同一 hash 更新 `last_seen_at`、版本和平台字段；新 hash 插入一条。返回 204 和 `cache-control: no-store`。

- [ ] **Step 6: 运行测试确认通过**

```bash
node --test CineBarTelemetry/tests/telemetry-worker.test.mjs
```

- [ ] **Step 7: 提交**

```bash
git add CineBarTelemetry
git commit -m "feat: add anonymous telemetry worker"
```

### Task 2: 实现受保护的聚合统计接口和管理页面

**Files:**
- Modify: `CineBarTelemetry/worker.js`
- Modify: `CineBarTelemetry/tests/telemetry-worker.test.mjs`
- Create: `CineBarWebsite/app/admin/analytics/page.tsx`
- Modify: `CineBarWebsite/app/globals.css`
- Modify: `CineBarWebsite/tests/content.test.mjs`

**Interfaces:** `GET /v1/telemetry/summary?range=30d`；页面显示累计安装实例和近 30 天活跃安装实例。

- [ ] **Step 1: 写失败测试**

测试没有管理员凭据返回 401；正确 `Authorization: Bearer $TELEMETRY_ADMIN_TOKEN` 才返回累计、活跃、版本、架构、系统和语言聚合数据；响应不包含 `install_hash`。

- [ ] **Step 2: 运行测试确认失败**

```bash
node --test CineBarTelemetry/tests/telemetry-worker.test.mjs
```

- [ ] **Step 3: 实现管理员鉴权和 SQL 聚合**

验证 Bearer Token 后执行 D1 聚合查询；默认 range 为 30d，只接受 `7d`、`30d`、`90d`。未知范围返回 400。仅返回数字、版本和分类统计。

- [ ] **Step 4: 实现官网统计页面**

页面通过服务端代理调用 Worker，不在浏览器中硬编码管理员 Token；显示“安装实例数，不等于真实用户数”、累计安装实例、近 30 天活跃、版本分布、芯片架构、macOS 版本和语言。未授权时显示通用错误，不泄露统计接口细节。

- [ ] **Step 5: 运行 Worker 和官网测试**

```bash
node --test CineBarTelemetry/tests/telemetry-worker.test.mjs
cd CineBarWebsite && npm test
```

- [ ] **Step 6: 提交**

```bash
git add CineBarTelemetry CineBarWebsite/app/admin \
  CineBarWebsite/app/globals.css CineBarWebsite/tests/content.test.mjs
git commit -m "feat: add protected installation analytics dashboard"
```

### Task 3: 接入 macOS 客户端启动上报

**Files:**
- Modify: `CineBar/Sources/CineBar/main.swift`
- Modify: `CineBar/Tests/RegressionBehaviorTests.swift`

**Interfaces:** `CineBarTelemetryClient.recordLaunchIfNeeded() async`；`TelemetryInstallPayload`。

- [ ] **Step 1: 写失败测试**

使用临时 `UserDefaults` 测试首次调用生成稳定 install ID，连续调用在同一日期只产生一次上报；模拟网络错误时不会抛到 AppDelegate。

- [ ] **Step 2: 运行测试确认失败**

运行 Swift 回归编译命令，预期遥测类型尚未定义。

- [ ] **Step 3: 实现安装 ID 和频率限制**

在现有应用支持目录/`UserDefaults` 中保存随机 UUID；保存最后上报日期。不要读取或发送本地片库状态。使用 `Bundle.main` 的版本、Build、系统版本、架构和语言生成固定 payload。

- [ ] **Step 4: 实现 HTTPS 上报**

新增 `CineBarTelemetryURL` 配置（默认 `https://telemetry.cinebar.cc/v1/telemetry/install`），使用现有网络请求策略；请求超时或 TLS/DNS 失败时静默返回。上报不阻塞 `applicationDidFinishLaunching`。

- [ ] **Step 5: 在 AppDelegate 启动时调用**

启动完成后创建 detached Task 调用 `recordLaunchIfNeeded()`；不增加用户交互按钮，不提供客户端关闭开关。

- [ ] **Step 6: 运行 Swift 回归测试**

确认 ID 稳定性、频率限制和失败隔离通过，并确认已有电影、电视剧、片库和更新测试不回归。

- [ ] **Step 7: 提交**

```bash
git add CineBar/Sources/CineBar/main.swift CineBar/Tests/RegressionBehaviorTests.swift
git commit -m "feat: report anonymous CineBar installations"
```

### Task 4: 完成隐私披露、Cloudflare 配置和发布验证

**Files:**
- Modify: `CineBar/README.md`
- Modify: `CineBar/INSTALL.md`
- Modify: `CineBar/请先阅读-测试版安装说明.html`
- Modify: `CineBar/请先阅读-测试版安装说明.txt`
- Modify: `CineBar/Assets/Localization/zh-Hans.lproj/Localizable.strings`
- Modify: `CineBar/Assets/Localization/zh-Hant.lproj/Localizable.strings`
- Modify: `CineBar/Assets/Localization/en.lproj/Localizable.strings`
- Modify: `CineBar/Assets/Localization/ja.lproj/Localizable.strings`
- Modify: `CineBar/Assets/Localization/ko.lproj/Localizable.strings`
- Modify: `CineBarWebsite/app/page.tsx`
- Modify: `CineBarWebsite/tests/content.test.mjs`
- Modify: `CineBarWebsite/wrangler.public.jsonc`

- [ ] **Step 1: 写隐私文案测试**

Node 测试必须确认五种语言和安装说明包含“匿名安装实例/版本信息”“不上传本地文件和个人身份数据”“安装实例数不等于真实用户数”。

- [ ] **Step 2: 完成隐私披露和关于页**

不增加开关；在安装说明、官网隐私说明和应用关于页面明确列出固定上报字段和用途。

- [ ] **Step 3: 配置 Worker/D1**

创建 D1、执行 `schema.sql`、设置 `TELEMETRY_HMAC_SECRET` 和 `TELEMETRY_ADMIN_TOKEN` secrets，配置 `telemetry.cinebar.cc` 路由。管理页面只使用服务器端 secret。

- [ ] **Step 4: 部署并验证 Worker**

```bash
npx wrangler d1 create cinebar-telemetry --location apac
npx wrangler d1 execute cinebar-telemetry --remote --file=CineBarTelemetry/schema.sql
npx wrangler deploy --config CineBarTelemetry/wrangler.jsonc
```

使用合法、重复、非法 payload 验证 204/400/401；确认 `/health` 显示 Build 26 配置。

- [ ] **Step 5: 运行完整测试**

```bash
node --test CineBarTelemetry/tests/telemetry-worker.test.mjs
node --test CineBar/Tools/tests/*.test.mjs
cd CineBarWebsite && npm test
cd ..
xcrun swiftc -parse-as-library -D CINEBAR_TEST \
  CineBar/Sources/CineBar/*.swift \
  CineBar/Tests/RegressionBehaviorTests.swift \
  -o /tmp/cinebar-tests/CineBarRegressionTests \
  && /tmp/cinebar-tests/CineBarRegressionTests
git diff --check
```

- [ ] **Step 6: 提交发布说明**

```bash
git add CineBar/README.md CineBar/INSTALL.md \
  CineBar/请先阅读-测试版安装说明.html \
  CineBar/请先阅读-测试版安装说明.txt \
  CineBar/Assets/Localization CineBarWebsite
git commit -m "docs: disclose anonymous installation telemetry"
```
