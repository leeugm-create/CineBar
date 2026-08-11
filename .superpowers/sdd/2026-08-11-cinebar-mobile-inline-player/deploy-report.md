# CineBar 移动首页内嵌播放器部署记录

- 部署日期：2026-08-11（Asia/Shanghai）
- 公网地址：[https://cinebar.cc/](https://cinebar.cc/)
- Cloudflare Worker：`cinebar-website`
- Cloudflare Version ID：`7074eb20-15a2-41f2-9d48-133296211406`
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

## 公网复核

- 手机 UA 首页：HTTP 200，引用 `/assets/index-BGXj08Ab.css`。
- 公网 CSS：包含 `@media (max-width:560px)`，不再只输出旧 WebView 无法识别的范围语法。
- 公网 appcast：Build 65 → 64 → 63，Build 65 EdDSA 签名和长度字段存在。
- 公网 Build 65 下载：HTTP 200；官网下载按钮不再返回 404。

## 手机端极简首页

- 手机断点只保留顶部 CineBar Logo 与搜索入口。
- 首页宣传、演示 GIF、评分、功能、安装、支持、联系和页脚均不在手机端显示。
- 搜索打开后，结果和内嵌播放器仍在搜索区域显示；桌面端布局不变。
- 公网 CSS 已确认包含 `.site-home .hero,.site-home .section,.site-home footer{display:none}`。

## 移动端兼容性修复（待部署）

- 原因：部分手机浏览器或内嵌 WebView 不识别构建产物中的媒体查询范围语法
  `@media (width<=560px)`，因此移动端会退回桌面布局。
- 修复：将网站构建目标下调到 Safari/iOS 13 与 Chrome 80，确保输出传统
  `max-width` 媒体查询；同时补齐官网已指向但尚未公开的 Build 65 下载归档，并重新生成签名 appcast。
- 验证：`npm test` 24/24 通过；`npm run lint` 0 errors（8 个既有图片优化 warnings）；
  `CI=1 npm run deploy:dry-run` 通过。

## 重要限制

当前 `/api/search` 返回的是 TMDB 元数据，尚未配置可合法嵌入的在线播放源，因此搜索结果若没有 `WatchSource`，播放器会明确显示“暂无可在线播放源”。本次部署没有接入第三方盗版资源、磁力或迅雷地址，也没有复用 `CineBarShare` 的第三方流媒体解析接口。要真正在线播放，需要后续接入你拥有授权、且允许网页嵌入的片源服务。
