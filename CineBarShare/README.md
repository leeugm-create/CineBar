# CineBar Share

这是不含社区评价和数据库的独立品牌分享服务。

## 部署

1. 打开 Cloudflare Dashboard，进入 **Workers & Pages**。
2. 在本目录执行 `npx wrangler login`。
3. 执行 `npx wrangler deploy`。
4. 将返回的 `https://cinebar-share.<你的子域>.workers.dev` 写入
   CineBar `Info.plist` 的 `CineBarShareURL`，然后重新构建应用。

部署后可访问：

- `/`：健康检查。
- `/cinebar-logo.svg`：CineBar Logo。
- `/share/movies/<TMDB ID>`：带 CineBar 名称和 Logo 的电影分享页。
- `/updates/latest.json`：CineBar 客户端更新清单。

本服务不需要 D1，不保存用户评价，也不需要用户注册。

发布新版时，请同步修改 `worker.js` 中 `/updates/latest.json` 返回的
`version`、`build`、`published_at`、`download_url` 和 `notes`，再重新部署。
