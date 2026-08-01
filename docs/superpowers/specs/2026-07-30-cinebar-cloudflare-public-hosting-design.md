# CineBar Cloudflare 公共托管迁移设计

日期：2026-07-30
状态：等待用户确认  
前置原因：Sites 私有生产部署成功，但工作区禁止公开互联网发布，匿名访问返回 403。

## 1. 目标

将已经完成并通过审查的 `CineBarWebsite` 公开部署到用户现有的
Cloudflare 账户，并最终由 `https://cinebar.cc` 提供官网。

本次只改变官网托管方式，不修改 CineBar Build 16 功能、数据代理、社区评分、
分享页面或 GitHub Releases。

## 2. 选定方案

采用独立 Cloudflare Worker 承载 vinext 生产构建：

- 新 Worker 名称：`cinebar-website`；
- Worker 静态资源：`CineBarWebsite/dist/client`；
- Worker 入口：`CineBarWebsite/dist/server/index.js`；
- 临时验证地址：Cloudflare 返回的 `workers.dev` 地址；
- 正式公开域名：`cinebar.cc`。

不把官网合并进 `CineBarShare/worker.js`。合并虽然少一个 Worker，但会让官网发布、
分享页和旧版更新检查互相影响，故不采用。

## 3. 域名边界

迁移后保持：

- `cinebar.cc` → 新的 `cinebar-website` Worker；
- `share.cinebar.cc` → 现有 `cinebar-share-test` Worker；
- `api.cinebar.cc` → 现有数据代理；
- `community.cinebar.cc` → 现有社区评分服务。

切换前先部署并验证 `workers.dev` 地址。只有临时地址的首页、静态资源和 `/health`
均成功后，才从 `CineBarShare/wrangler.jsonc` 删除根域路由，并把同一根域交给官网。

## 4. 配置与构建

在 `CineBarWebsite` 增加受版本控制的 Cloudflare Worker 部署配置与脚本。
配置必须显式包含：

- `name: cinebar-website`；
- `main: dist/server/index.js`；
- `assets.directory: dist/client`；
- `compatibility_flags: nodejs_compat`；
- 与已验证构建一致的兼容日期；
- 第一阶段不在配置中声明 `cinebar.cc`，避免部署即切流。

部署顺序：

1. 从干净源码运行测试和生产构建；
2. 执行 Wrangler dry-run，检查入口和静态资源；
3. 部署新 Worker，但不接根域；
4. 验证临时生产地址；
5. 再提交并部署根域路由迁移；
6. 从公网验证 `cinebar.cc`、`share.cinebar.cc` 和相关健康接口。

## 5. 安全与凭证

- 继续使用现有 Wrangler OAuth 登录；
- 不把 OAuth Token、API Token 或临时凭证写入仓库、URL、日志或报告；
- 不删除 Sites 项目，保留它作为已验证构建记录，但不向用户提供其 403 地址；
- PayPal 表单和 GitHub Releases 链接保持不变；
- 不上传 Sparkle 私钥；自动更新工作仍是后续独立任务。

## 6. 验证标准

临时地址必须满足：

- `/` 返回 200 并包含“今晚看什么？”；
- `/health` 返回 200、`cinebar-website`、`cache-control: no-store`；
- `/og.png` 返回 200 且尺寸为 1200×630；
- HTML 中 Open Graph 与 X 图片地址为绝对 HTTPS URL。

正式切换后必须满足：

- `https://cinebar.cc/` 返回官网；
- `https://cinebar.cc/health` 返回官网健康信息；
- `https://share.cinebar.cc/m/<ID>` 和 `/t/<ID>` 仍由分享服务处理；
- `api.cinebar.cc`、`community.cinebar.cc` 未更改；
- TLS 证书正常且浏览器不再显示“不安全”；
- 任一关键检查失败，立即把 `cinebar.cc` 路由恢复给原 Worker。

## 7. 明确不做

- 不购买新的云服务器；
- 不将域名转移出阿里云；
- 不改 Cloudflare 账户权限或付款设置；
- 不上传 GitHub；
- 不把本次官网迁移包装成 CineBar 正式稳定版发布；
- 不在本任务中集成 Sparkle。
