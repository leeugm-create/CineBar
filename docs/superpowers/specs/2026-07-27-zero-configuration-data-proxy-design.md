# CineBar 零配置公开测试版设计

**日期：** 2026-07-27  
**目标版本：** 0.8.2-test.1（Build 15）  
**状态：** 用户已确认

## 目标

制作无需用户申请、填写或部署任何数据服务的 CineBar 公开测试版。TMDB 与
OMDb 密钥由开发者统一保存到 Cloudflare，客户端仅访问 CineBar 数据代理，同时
保留现有 TMDB、IMDb、烂番茄和 Metacritic 多重评分。

本版没有 Apple Developer ID，仍采用测试包形式分发；用户第一次打开时需要完成
macOS Gatekeeper 安全确认，但不需要配置 Cloudflare、TMDB、OMDb、D1 或社区账号。

## 1. 统一数据代理

继续使用 `CineBarDataProxy` Cloudflare Worker，同时代理 TMDB 与 OMDb。

### TMDB

- 保留客户端当前使用的路径结构，减少客户端改动。
- 只允许 CineBar 已使用的 `/trending/`、`/search/`、`/discover/`、
  `/movie/`、`/tv/`、`/person/` 路径，以及精确的
  `/configuration/countries` 国家地区清单路径。
- 拒绝非 GET 请求、路径穿越和不在允许列表中的路径。
- Worker 使用 Cloudflare Secret `TMDB_TOKEN` 添加上游授权。
- 成功响应缓存 15 分钟；失败响应不缓存。

### OMDb

- 新增 `/omdb?i=<IMDb ID>`。
- 只允许格式为 `tt` 加数字的 IMDb 编号。
- 不接受客户端提供的 `apikey`、标题搜索、自由查询或其他 OMDb 参数。
- Worker 使用 Cloudflare Secret `OMDB_API_KEY` 添加上游密钥。
- 成功响应缓存 6 小时，降低 OMDb 免费额度消耗；失败响应不缓存。

### 共同安全边界

- API 密钥不写入源代码、Wrangler 普通变量、Git、安装包或错误信息。
- 代理不是通用转发器，不能由请求指定任意上游地址。
- 返回 `x-content-type-options: nosniff`。
- 上游未配置或暂时失败时返回明确、无密钥信息的状态。
- 公开测试服务无法依靠客户端内置常量实现真正的访问控制，因此主要通过严格路由、
  参数校验、缓存及 Cloudflare 请求监控控制滥用；不加入可被反编译提取的伪密钥。

## 2. 客户端数据流

`CineBarDataProxyURL` 写入已部署的数据代理地址。

- `TMDBClient` 检测到代理地址后始终使用代理，不读取或要求本机 TMDB Token。
- `OMDbClient` 检测到代理地址后请求 `/omdb?i=<IMDb ID>`，不发送 API Key。
- `hasToken` 和 `hasOMDbKey` 在代理可用时均视为已配置。
- 现有 TMDB 详情、演员、电视剧、预告、剧照、观看平台和国家地区功能保持不变。
- 现有 IMDb、烂番茄和 Metacritic 多重评分保持不变。
- 用户旧版本中保存的本机 Token/Key 不迁移、不上传；新版不需要读取它们。
- 数据代理失败时显示“CineBar 数据服务暂时不可用，请稍后重试”，不再引导正式
  零配置版本的用户申请 Token。

## 3. 数据来源设置页

当安装包配置了 `CineBarDataProxyURL` 时：

- 完全隐藏 TMDB Token 和 OMDb Key 输入框。
- 隐藏“申请影片数据 Token”和“申请外部评分 Key”链接。
- 显示只读状态“CineBar 内置数据服务已启用”。
- 列出：
  - TMDB：电影、电视剧、演员、海报及观看平台；
  - OMDb：IMDb、烂番茄和 Metacritic 多重评分；
  - TVMaze：剧集播出时间。
- 保留观看地区选择和“保存并刷新”按钮。

没有配置代理的开发测试构建继续保留现有手动 Token/Key 输入能力，方便本地诊断；
正式零配置测试包不展示这些输入项。

## 4. 现有线上服务

- 社区评分继续使用已部署的 `CineBarCommunity` 与 D1。
- 品牌分享、短链接和更新清单继续使用 `CineBarShare`。
- 数据代理部署为独立的 `cinebar-data` Worker。
- 本版先使用 Cloudflare `workers.dev` 地址，不要求用户购买或配置域名。
- 后续有正式域名时只需替换安装包中的服务根地址。

## 5. 版本与分发

- `CFBundleShortVersionString`：`0.8.2`
- `CFBundleVersion`：`15`
- 包名：`CineBar-0.8.2-test.1-universal.zip`
- 同时包含 Apple 芯片和 Intel 架构。
- 继续使用临时签名，不冒充 Apple 公证正式版。
- 安装说明明确：用户无需任何 API Key，但首次打开仍需通过 macOS 安全确认。
- 不上传 GitHub，不创建 GitHub Release。

## 6. 测试与验收

- Data Proxy 自动化测试覆盖 TMDB 允许路由、拒绝路由和路径穿越。
- 自动化测试覆盖 OMDb 合法 IMDb 编号、非法编号、禁止客户端 `apikey`、缓存和
  上游失败。
- 测试证明响应或构建产物中不包含 TMDB/OMDb 密钥。
- Swift 回归测试证明配置代理后 TMDB 与 OMDb 均不需要本机密钥。
- 数据来源设置页在代理构建中不出现密钥输入框或申请链接。
- 电影详情可加载 TMDB 数据和 OMDb 多重评分。
- 电视剧、演员、预告、剧照、观看平台与社区评分回归正常。
- Cloudflare Data Proxy 部署后对真实 TMDB 与 OMDb 请求进行烟雾测试。
- 社区测试、分享测试、数据代理测试、Swift 回归测试、类型检查和语言文件校验
  全部通过。
- 通用包通过签名验证，包含 `x86_64` 与 `arm64`，版本为 Build 15，并带有 HTML
  与纯文本安装说明。

## 7. 交付

生成：

`CineBar-0.8.2-test.1-universal.zip`

用户安装后可直接浏览和评分，不需要部署后台或填写任何密钥。
