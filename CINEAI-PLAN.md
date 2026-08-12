# CineAI — 产品与工程计划（V1）

> 最后更新：2026-08-12
> 定位：这是 CineAI V1 的正式起点文档，记录产品范围、架构与工程决策。后续迭代在此文档基础上演进。

---

## 1. 产品定位

CineBar 加入 AI 能力后的新形态，命名 **CineAI**。
在现有 CineBar（macOS 影视聚合/评分/在线播放）之上，叠加自然语言对话能力，让用户"用一句话找片、问剧情、防剧透、要推荐"。

## 2. V1 范围（经过多轮收缩后的结论）

- **平台：仅 macOS 单端。** watchOS / tvOS / iOS / Windows 本期暂不开发。
  - 好处：不需要跨端拆分、不需要 CloudKit 同步、不需要多 target；就是在现有 CineBar 工程上加一个 `CineAI` 模块。
  - 未来要上手机/电视时，再补跨端同步与薄 UI target，逻辑层不受影响，但不列为 V1 目标。
- 砍掉"全网防剧透"，只做"**基于用户观影进度的防剧透**"（详见 §6）。

## 3. CineAI V1 四大能力

1. **🔍 自然语言找电影** —— 用户口语化描述（"找一部时间循环、结局温馨的片"），AI 拆条件检索返回。
   - 主力、安全、可先做。
2. **🚫 进度感知防剧透问答** —— 记住用户看到某剧 SxxExx，不把之后的剧情资料交给 AI。
   - 差异化主打、口碑来源。
3. **📺 影视问答**（"这部剧讲什么"）—— 基于 TMDB 元数据 + 用户进度组织回答，不碰详细剧情。
4. **🎬 今晚看什么（推荐）** —— V1 先做无门槛"惊喜推荐"（随机/按已收藏类型），个性化冷启动后再说。

**界面快捷入口**（聊天界面前置预设）：
- 🎬 今晚看什么
- 🔍 帮我找一部电影
- 📺 这部剧讲什么
- 🚫 无剧透问答

## 4. 总体架构：本地 + 在线 混合

**本地完成**：用户看片记录、收藏、追剧进度、偏好标签、观影进度（SxxExx）、最近搜索、部分影视资料缓存。
**在线完成**：AI 理解问题、复杂推荐、影视问答、最新影视信息查询、自然语言生成。

> 核心原则：**影视事实优先从影视 API / 数据库实时查询，再交给 AI 组织回答，而不是让 AI 凭记忆乱答（RAG / 检索增强），从源头克制 LLM 幻觉。**

## 5. 分层结构（macOS 单端）

```
CineBar.app (macOS)
 ├─ 现有层: MovieStore / TMDB Client / MoovieStreamResolver / 视图
 └─ CineAI 模块
     ├─ AIProvider (协议)          ← 不绑定具体模型
     ├─ DeepSeekProvider           ← V1 默认实现
     ├─ IntentRouter               ← 识别用户意图 → 路由到 4 能力之一
     ├─ RAG 检索层                 ← 查数据 → 拼上下文给 AI
     ├─ 进度 LocalStore            ← 观影进度(看过的季/集)、收藏、搜索历史、偏好
     └─ 服务端限额客户端           ← 调用前先看是否仍有额度
```

- 单 macOS 端，进度/收藏/偏好**存本地文件**即可（CloudKit 同步本期不做，未来扩端再补）。
- 建议把 CineAI 相关放到独立目录/模块（如 `CineBar/Sources/CineAI/`），与现有 main.swift 逻辑分离，避免继续往巨型文件堆。

## 6. 防剧透（进度感知，诚实边界）

**实现**：利用 TMDB 官方单集 endpoint `GET /tv/{series_id}/season/{season_number}/episode/{episode_number}`。
- RAG 层**只拉 `episode_number <= 用户进度` 的每集资料**，之后的集**根本不查询、不进 prompt**。
- 承诺可兑现："CineBar 知道你看到 S02E05，因此不会主动使用 S02E06 之后的剧集资料。"

**诚实边界（不过度承诺）**：
- TMDB 单集 overview 通常只一两句话，不是详细剧情。因此"防剧透"的准确含义是"**不把用户没看过的集的资料喂给 AI**"，而非"AI 精通每一集细节"。
- 整季/整剧简介若自带结局，这是 TMDB 资料固有，V1 不额外处理。

## 7. AI 计费与 Provider 抽象

**V1 计费策略**：
- **开发者代付 + 服务端限额**：不做 BYOK（用户自带 key），不做用户订阅计费。
- 因此**需要一个开发者掌控的后端**（建议 Cloudflare Worker，用户已熟悉）：保管 DeepSeek key、转发调用、**按设备/用户限额**、用量计费与告警。
- App 不直连 DeepSeek（key 绝不进客户端）。

**模型**：默认用 DeepSeek V4 Flash **非思考模式**；当前价格低（输入约 ¥1/百万 tokens、输出约 ¥2/百万 tokens），但 DeepSeek 已预告近期整体涨价，**只能用当前低价启动，不能让架构依赖此价格永远不变**。

**必须在代码里落地**：
```
protocol AIProvider {
    func complete(messages: [AIChatMessage], maxTokens: Int?, reasoning: Bool) async throws -> AIResult
}
struct AIResult { let text: String; let inputTokens: Int; let outputTokens: Int }
final class DeepSeekProvider: AIProvider { ... }   // V1 默认
```
- 业务层只依赖 `AIProvider`，不 import 具体模型；未来换 OpenAI/本地模型只新增一个 Provider 实现。
- `AIResult` 必须返回 `inputTokens/outputTokens`，供限额与成本统计。
- **预留模型分级**：便宜的 Provider（Flash）兜底日常，贵的留给"复杂推荐"等高价值问答（即使 V1 都走 Flash，路由结构先留开关）。

**省钱三件套（开发者代付下必要）**：
- `maxTokens` 上限：限输出长度，防无限写。
- **去重缓存**：相同"意图+上下文"的查询按内容哈希短期缓存，命中不调 LLM。
- **用量监控 + 月度预算告警/降级**：价格变化时只调 Provider 与限额策略，业务层不动。

## 8. 工程落地顺序（建议）

1. 抽出 `AIProvider` 协议 + `DeepSeekProvider`（先做 Mock/可测）。
2. 进度 `LocalStore`（观影进度 SxxExx 读写）。
3. `IntentRouter` + RAG 检索层（TMDB 查 + 进度过滤 + prompt 拼装）。
4. 服务端限额客户端（接 Cloudflare Worker 代理）。
5. UI：聊天界面 + 4 个快捷入口 + 结果展示。

## 9. 待实施时决定（不锁死）

- 服务端具体实现：Cloudflare Worker + D1（限额表 / 用量表）为推荐默认。
- 本地存储形态：JSON 文件即可，未来扩端再评估。
- 缓存 TTL、限额阈值（每日每 device 调用次数 / token 预算）为可配置项。

## 10. 评测基线与强制门禁

> 目的：AI 功能没有评测基线会越来越难维护——改一个 Prompt 可能修好 A 却弄坏 B，且无人察觉。
> 此基线是唯一的防线，判定改动是否破坏既有能力。

### 10.1 离线评测基线（20 项，可重复、不联网、不耗 token）

评测程序：`CineBar/Tests/CineAIEval.swift`（独立 `@main`，绕开主程序回归测试的 GUI 限制）。

覆盖范围：
1. **意图路由**（5 项）：findMovie / spoilerSafe / recommend / mediaIntro 的关键词分类。
2. **找片语义拆解**（3 项）：中文类型词典、年份、冷门、评分限定、关键词。
3. **防剧透硬拦截**（4 项）：未看完拦结局/凶手、非结局放行、看完放行。
4. **RAG prompt 结构约束**（4 项，用 `CaptureProvider` 记录 messages）：断言关键约束没丢——findMovie system 防编造/候选约束、spoilerSafe system 限进度、spoilerSafe user **注入进度**、mediaIntro system 资料约束。
5. **端到端链路 Smoke**（5 项，防"每个零件 PASS 串起来却坏"）：E2E-A findMovie 完整链路、E2E-B 剧透拦截不走 RAG、E2E-C 剧透放行+进度注入、E2E-D 数据源无结果降级提示、E2E-E 统一错误映射为 displayText。

运行命令：
```bash
xcrun swiftc -parse-as-library -target arm64-apple-macosx13.0 -o /tmp/cinaeieval \
  CineBar/Sources/CineBar/CineAIProvider.swift \
  CineBar/Sources/CineBar/CineAIError.swift \
  CineBar/Sources/CineBar/CineAIIntent.swift \
  CineBar/Sources/CineBar/CineMovieQuery.swift \
  CineBar/Sources/CineBar/CineAISpoilerShield.swift \
  CineBar/Sources/CineBar/CineAIRAG.swift \
  CineBar/Tests/CineAIEval.swift
/tmp/cinaeieval
```
期望输出：末尾 `CINEAI EVAL: ALL PASS`（20 项 PASS）。

### 10.2 强制门禁（不可跳过）

**任何涉及 CineAI Core / Prompt（RAG 的 system·user 文案）/ RAG 检索 / SpoilerShield / 统一错误模型 的改动，在提交前必须跑完 10.1 的全部 20 项离线评测且全绿。** 未全绿不得提交。

涉及的文件（触此门禁）：`CineAIProvider.swift`、`CineAIError.swift`、`CineAIIntent.swift`、`CineMovieQuery.swift`、`CineAIRAG.swift`、`CineAISpoilerShield.swift`，以及任何改动这些 prompt/逻辑/错误映射的调用方（`CineAIAssembly.swift`、`CineAIView.swift`、`CineAIProgressStore.swift`、`CineAIDeepSeekProvider.swift` 若影响上述行为）。

> 理由（决定）；2026-08-12：Core 功能已基本齐备，再叠模块收益递减。当前最大风险是"改动 Prompt 悄悄破坏既有能力且无人发现"。故设立此离线评测门禁。

### 10.3 真模型 golden set（预留，不进 CI）

- 离线评测只覆盖**确定性**逻辑；真模型的回答质量（是否编造、推荐是否合理）需真模型验证。
- 预留：一组固定输入 + 期望覆盖点，仅在**开发者本地有模型 key / 代理可用**时手动跑，人工核对。
- 当前代理（`CineAIProxy`）未部署、无真 key，此 golden set 暂不落地脚本，仅记录该门禁存在。

