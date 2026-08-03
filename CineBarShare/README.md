# CineBar Share

这是不含社区评价和数据库的独立品牌分享服务。

## 部署

1. 打开 Cloudflare Dashboard，进入 **Workers & Pages**。
2. 在本目录执行 `npx wrangler login`。
3. 将 TMDB Read Access Token 安全写入 Cloudflare Secret：

   ```bash
   npx wrangler secret put TMDB_BEARER_TOKEN --name cinebar-share-test
   ```

4. 执行 `npx wrangler deploy --name cinebar-share-test`。
5. 将返回的 `https://cinebar-share-test.<你的子域>.workers.dev` 写入
   CineBar `Info.plist` 的 `CineBarShareURL`，然后重新构建应用。

测试版建议使用独立名称，避免与未来正式服务混淆：

```bash
cd CineBarShare
npx wrangler deploy --name cinebar-share-test
```

部署完成后，终端会显示测试服务地址。把完整的 `https://...workers.dev`
地址写入 `CineBarShareURL`，不要添加 `/m/...` 或 `/t/...` 路径。

部署后可访问：

- `/`：健康检查。
- `/cinebar-logo.svg`：CineBar Logo。
- `/m/<TMDB ID>`：带 CineBar 名称、Logo 和资料的电影永久短链接。
- `/t/<TMDB ID>`：带 CineBar 名称、Logo 和资料的电视剧永久短链接。
- `/updates/latest.json`：CineBar 客户端更新清单。

本服务不需要 D1，不保存用户评价，也不需要用户注册。

`CINEBAR_DOWNLOAD_URL` 是可选的 HTTPS 下载页地址。没有正式下载页时保持
`wrangler.jsonc` 中的空字符串，分享页不会显示下载按钮；有正式地址以后再填写并
重新部署。不要填写临时路径或不存在的安装包地址。

发布新版时，请同步修改 `worker.js` 中 `/updates/latest.json` 返回的
`version`、`build`、`published_at`、`download_url` 和 `notes`，再重新部署。当前测试版已同步到 Build 26。
