# CineBar 匿名安装统计

这是一个只接收最小匿名安装信息的 Cloudflare Worker。客户端生成随机安装编号，
Worker 使用 HMAC-SHA-256 立即转换为不可逆的哈希后再写入 D1；原始安装编号、IP
地址、文件名、影片内容和账号信息都不保存。

## 部署

```sh
npm test
npx wrangler d1 execute cinebar-telemetry-test --file schema.sql --remote
npx wrangler secret put TELEMETRY_HMAC_SECRET
npx wrangler secret put TELEMETRY_ADMIN_TOKEN
npx wrangler deploy
```

统计接口 `GET /v1/telemetry/summary?range=30d` 必须携带
`Authorization: Bearer <TELEMETRY_ADMIN_TOKEN>`，只返回汇总数量，不返回安装哈希。
客户端接口为 `POST /v1/telemetry/install`。统计目前不提供客户端关闭按钮，应用内
会在隐私说明中明确告知。
