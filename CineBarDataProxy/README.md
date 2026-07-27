# CineBar Data Proxy

正式版通过此 Worker 请求 TMDB 影片、电视剧资料以及 OMDb 多重评分。用户不需要
自行申请 TMDB Token 或 OMDb API Key，凭据也不会被打进 macOS 安装包。

## 部署

```bash
npx wrangler login
npx wrangler secret put TMDB_TOKEN --name cinebar-data
npx wrangler secret put OMDB_API_KEY --name cinebar-data
npx wrangler deploy --name cinebar-data
```

两次 `secret put` 后，分别粘贴 TMDB Read Access Token 和 OMDb API Key。
这些值必须存为 Cloudflare Secret，禁止写入 `vars`、源码或安装包。

公开接口仅允许：

- TMDB：`/trending/`、`/search/`、`/discover/`、`/movie/`、`/tv/`、
  `/person/`，以及精确路径 `/configuration/countries`
- OMDb：`/omdb?i=tt<数字>`，不接受客户端传入 `apikey` 或片名搜索

部署完成后，把返回的 Worker 地址写入 CineBar `Info.plist` 的
`CineBarDataProxyURL`，例如：

```xml
<key>CineBarDataProxyURL</key>
<string>https://cinebar-data.example.workers.dev</string>
```

然后重新构建正式版。程序检测到代理地址后，会隐藏 TMDB Token 输入框并直接
使用内置数据服务；OMDb 多重评分也通过同一地址读取。TMDB 成功响应缓存 15
分钟，OMDb 成功响应缓存 6 小时，失败响应不缓存。
