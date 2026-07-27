# CineBar Community

这是 CineBar 的匿名共享评分后端，使用 Cloudflare Worker + D1。

## 能力

- 同时支持电影和电视剧。
- 每个安装实例对每个条目保留一条评分，可随时修改或删除。
- 评分范围 0–10，以 0.5 分为间隔；0 分是有效评分。
- 返回所有用户的 CineBar 平均分、评分人数，以及当前安装实例自己的评分。
- 不需要社区账号、昵称或短评。
- 服务端只保存设备标识的 SHA-256 摘要。
- 提供 `/share/movies/:id` 品牌分享页面，展示 CineBar 名称、Logo 和影片资料。
- 分享页面是公开网页；评价 API 仍受 `PUBLIC_KEY` 校验。

## 部署

1. 安装 Node.js，在本目录执行 `npm init -y` 和
   `npm i -D wrangler@latest`，然后运行 `npx wrangler login` 登录 Cloudflare。
2. 复制配置：`cp wrangler.toml.example wrangler.toml`。
3. 创建 D1 数据库：`npx wrangler d1 create cinebar-community`。
4. 将返回的数据库 ID 写入 `wrangler.toml` 的 `database_id`。
5. 初始化数据库（旧版数据库也可再次执行，以新增 `ratings` 表）：
   `npx wrangler d1 execute cinebar-community --remote --file=./schema.sql`
6. 生成两段不同的随机值，并设置两个 Secret：
   `npx wrangler secret put DEVICE_SALT`
   `npx wrangler secret put PUBLIC_KEY`
7. 执行 `npx wrangler deploy`。
8. 将 Worker 的 HTTPS 地址和 `PUBLIC_KEY` 分别写入 CineBar `Info.plist`
   的 `CineBarCommunityURL` 与 `CineBarCommunityPublicKey`，重新构建应用。

普通用户不需要 Cloudflare 账号、社区账号或 API 配置；他们在电影或电视剧
详情中直接打分即可。Cloudflare 账号只由应用发布者使用一次。

`PUBLIC_KEY` 会随客户端分发，只能作为基本入口校验，不能替代服务端限频、
内容审核、举报处理和正式账号系统。

`public/cinebar-logo.svg` 会由 Wrangler 作为静态资源与 Worker 一起部署，
不需要单独上传 Logo。
