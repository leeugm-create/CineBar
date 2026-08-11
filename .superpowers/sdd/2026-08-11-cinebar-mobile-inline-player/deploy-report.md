# CineBar 移动首页内嵌播放器部署记录

- 部署日期：2026-08-11（Asia/Shanghai）
- 公网地址：[https://cinebar.cc/](https://cinebar.cc/)
- Cloudflare Worker：`cinebar-website`
- Cloudflare Version ID：`ea1c32d9-e351-4f90-9352-600c61b77979`
- 更新清单：[https://cinebar.cc/appcast.xml](https://cinebar.cc/appcast.xml)

## 本次内容

- 手机浏览器首页突出搜索入口。
- 手机端搜索结果点击后在首页内展开播放器区域；不会跳到详情页。
- 播放区域只在用户点击播放后创建媒体元素，支持关闭、重试和播放错误提示。
- 桌面端、分享页和 macOS 客户端界面保持不变。
- 保留中文、英文、日文、韩文和繁体中文文案。

## 验证

- `npm test`：23/23 通过。
- `npm run lint`：0 errors；仅保留既有 `no-img-element` warnings。
- `CI=1 npm run deploy:dry-run`：通过。
- 公网首页：HTTP 200。
- 手机 UA 请求：已返回 `site-home` 和搜索文案。
- 公网 `appcast.xml`：HTTP 200。

## 重要限制

当前 `/api/search` 返回的是 TMDB 元数据，尚未配置可合法嵌入的在线播放源，因此搜索结果若没有 `WatchSource`，播放器会明确显示“暂无可在线播放源”。本次部署没有接入第三方盗版资源、磁力或迅雷地址，也没有复用 `CineBarShare` 的第三方流媒体解析接口。要真正在线播放，需要后续接入你拥有授权、且允许网页嵌入的片源服务。
