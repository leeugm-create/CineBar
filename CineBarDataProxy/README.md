# CineBar Data Proxy

正式版通过此 Worker 请求影片与电视剧数据，用户不需要自行申请 TMDB
Token，Token 也不会被打进 macOS 安装包。

## 部署

```bash
npx wrangler login
npx wrangler secret put TMDB_TOKEN
npx wrangler deploy
```

`secret put` 后在终端粘贴 TMDB Read Access Token。部署完成后，把返回的
Worker 地址写入 CineBar `Info.plist` 的 `CineBarDataProxyURL`，例如：

```xml
<key>CineBarDataProxyURL</key>
<string>https://cinebar-data.example.workers.dev</string>
```

然后重新构建正式版。程序检测到代理地址后，会隐藏 TMDB Token 输入框并直接
使用开发者的数据服务。OMDb 暂时仍是独立可选评分接口；正式商业发布前应确认
对应数据授权并采用同类服务器代理。
