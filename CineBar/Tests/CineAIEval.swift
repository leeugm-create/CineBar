import Foundation

/// CineAI 离线评测基线。
/// 目的：防止"改了一个 Prompt 悄悄弄坏其它用例"——用一组固定输入 + 确定性断言，
/// 覆盖意图路由、找片语义拆解、防剧透硬拦截、RAG prompt 结构约束、走代理 provider 消息体。
/// 只需依赖 CineAI 的离线文件，不联网、不调真模型，可单独编译运行：
///   xcrun swiftc -parse-as-library -o cinaeival CineBar/Sources/CineBar/CineAIProvider.swift \
///     CineBar/Sources/CineBar/CineAIIntent.swift CineBar/Sources/CineBar/CineMovieQuery.swift \
///     CineBar/Sources/CineBar/CineAISpoilerShield.swift CineBar/Sources/CineBar/CineAIRAG.swift \
///     CineBar/Sources/CineBar/CineAIDeepSeekProvider.swift CineBar/Tests/CineAIEval.swift
@main
struct CineAIEval {

    /// 记录每次调用 messages 的假 Provider，用于断言"prompt 里关键约束有没有丢"。
    /// 这也是防"改 Prompt 漏掉约束"的直接手段。
    private final class CaptureProvider: AIProvider {
        var captured: [AIChatMessage] = []
        func complete(
            messages: [AIChatMessage], maxTokens: Int?, reasoning: Bool
        ) async throws -> AIResult {
            captured = messages
            return AIResult(text: "ok", inputTokens: 0, outputTokens: 0)
        }
    }

    static func check(_ cond: Bool, _ name: String) {
        assert(cond, "FAIL: \(name)")
        print("PASS: \(name)")
    }

    static func main() async {
        // ---- 1. 意图路由 ----
        check(CineAIIntentRouter.route("帮我找一部时间循环的电影") == .findMovie, "route findMovie")
        check(CineAIIntentRouter.route("有没有类似盗梦空间的") == .findMovie, "route findMovie2")
        check(CineAIIntentRouter.route("老白最后死了吗") == .spoilerSafe, "route spoilerSafe")
        check(CineAIIntentRouter.route("这部剧结局是谁死了") == .spoilerSafe, "route spoilerSafe2")
        check(CineAIIntentRouter.route("今晚看什么") == .recommend, "route recommend")
        check(CineAIIntentRouter.route("这部剧讲什么") == .mediaIntro, "route intro")
        // general：非影视/闲聊不应硬塞找片
        check(CineAIIntentRouter.route("给我讲个笑话") == .general, "route general")
        check(CineAIIntentRouter.route("现在几点了") == .general, "route general2")
        check(CineAIIntentRouter.route("你好") == .general, "route general3")
        // offScope：非影视通用操作应本地硬拦截
        check(CineAIIntentRouter.route("帮我写一篇推文") == .offScope, "route offScope 推文")
        check(CineAIIntentRouter.route("帮我修改这篇文章") == .offScope, "route offScope 改文章")
        check(CineAIIntentRouter.route("写一段python代码") == .offScope, "route offScope 代码")
        check(CineAIIntentRouter.route("我想汲取灵感写自己的原创故事") == .offScope, "route offScope 写原创故事")
        check(CineAIIntentRouter.route("帮我写个故事") == .offScope, "route offScope 写故事")
        // 影视相关不被误伤
        check(CineAIIntentRouter.route("这部电影的故事讲什么") != .offScope, "route 影视故事不误伤")
        check(CineAIIntentRouter.route("推荐一部关于创作的电影") != .offScope, "route 创作电影不误伤")

        // ---- 2. 找片语义拆解 ----
        var q = CineMovieQueryParser.parse("找一部时间循环的喜剧")
        check(q.genreIDs.contains(35), "parse 喜剧")
        q = CineMovieQueryParser.parse("推荐一部高分爱情片")
        check(q.genreIDs.contains(10749) && (q.minVote ?? 0) >= 7.0, "parse 高分爱情")
        q = CineMovieQueryParser.parse("2020年的冷门动作片")
        check(q.genreIDs.contains(28) && q.year == 2020 && q.wantObscure, "parse 年份/冷门/动作")

        // ---- 3. 防剧透硬拦截 ----
        check(CineAISpoilerShield.blockReason(question: "凶手是谁", hasSeenFinal: false) != nil, "shield 未看完拦")
        check(CineAISpoilerShield.blockReason(question: "大结局", hasSeenFinal: false) != nil, "shield 大结局拦")
        check(CineAISpoilerShield.blockReason(question: "这个角色后面呢", hasSeenFinal: false) == nil, "shield 非结局放行")
        check(CineAISpoilerShield.blockReason(question: "大结局", hasSeenFinal: true) == nil, "shield 看完放行")

        // ---- 4. RAG prompt 结构约束（防"改 Prompt 丢约束"）----
        let cap = CaptureProvider()
        let rag = CineAIRAG(provider: cap, data: .init(
            fetchFacts: { _ in "事实：某片 8.8 分 2020" },
            searchMovies: { _ in "候选A、候选B" },
            spoilerContext: { "《绝命毒师》你已看到 S03E01" }
        ))

        // 4a. 找片：system 必须含"不编造/基于候选"
        _ = try? await rag.answer(.findMovie, input: "时间循环的喜剧")
        let sysFind = cap.captured.first { $0.role == "system" }?.content ?? ""
        check(sysFind.contains("不") || sysFind.contains("候选"), "findMovie system 有防编造候选约束")

        // 4b. 防剧透：system 必须含"不透露未看到/进度"，user 必须注入"已看到"
        _ = try? await rag.answer(.spoilerSafe, input: "后面怎么了")
        let sysSpoil = cap.captured.first { $0.role == "system" }?.content ?? ""
        let userSpoil = cap.captured.first { $0.role == "user" }?.content ?? ""
        check(sysSpoil.contains("未看到") || sysSpoil.contains("不透露"), "spoilerSafe system 有限进度约束")
        check(userSpoil.contains("已看到"), "spoilerSafe user 注入进度")

        // 4c. 影视问答：system 必须含"基于提供的资料/不编造"
        _ = try? await rag.answer(.mediaIntro, input: "庆余年讲什么")
        let sysIntro = cap.captured.first { $0.role == "system" }?.content ?? ""
        check(sysIntro.contains("资料") || sysIntro.contains("编造"), "mediaIntro system 有资料约束")

        // 4d. general（非影视）：应明确只管影视、拒绝无关问题，不得自由延展。
        _ = try? await rag.answer(.general, input: "给我讲个笑话")
        let sysGeneral = cap.captured.first { $0.role == "system" }?.content ?? ""
        check(
            sysGeneral.contains("只做影视") || sysGeneral.contains("只懂影视") || sysGeneral.contains("无法回答"),
            "general system 明确只管影视、拒绝无关"
        )

        // 4e. 上下文联想：传入 history 后应插在 system 之后、当前消息之前。
        _ = try? await rag.answer(
            .mediaIntro, input: "它后来怎样了",
            history: [
                AIChatMessage(role: "user", content: "《海上钢琴师》讲什么"),
                AIChatMessage(role: "assistant", content: "讲 1900 在邮轮的一生。"),
            ]
        )
        let roles = cap.captured.map { $0.role }
        check(roles.first == "system", "history: 首条为 system")
        let sysIdx = roles.firstIndex(of: "system") ?? 0
        check(
            sysIdx + 1 < roles.count && roles[sysIdx + 1] == "user"
                && cap.captured[sysIdx + 1].content.contains("海上钢琴师"),
            "history: system 后紧跟历史 user"
        )

        // ---- 5. 端到端链路 Smoke（防"每个零件都 PASS，串起来却坏"）----
        await endToEndSmoke()

        print("\nCINEAI EVAL: ALL PASS")
    }

    /// 端到端：输入 → 路由 → (防剧透拦截 or RAG) → Stub/错误 → 结果/文案。
    /// 用真实 Router + real RAG + Stub/Error Provider，绕开 MovieStore，纯离线可复现。
    private static func endToEndSmoke() async {
        // 会抛统一错误的假 Provider（模拟网络层已映射的结果）
        final class ErrorStub: AIProvider {
            let err: CineAIError
            init(_ e: CineAIError) { self.err = e }
            func complete(messages: [AIChatMessage], maxTokens: Int?, reasoning: Bool) async throws -> AIResult {
                throw err
            }
        }

        func data() -> CineAIRAG.DataSource {
            .init(
                fetchFacts: { _ in "《庆余年》剧集，8.9 分" },
                searchMovies: { _ in "《盗梦空间》(2010) 评分 8.8\n《降临》(2016) 评分 7.9" },
                spoilerContext: { "《绝命毒师》你已看到 S03E01" }
            )
        }

        // A) findMovie 完整链路 → 返回 Stub 文案（RAG 不抛）
        do {
            let rag = CineAIRAG(provider: StubAIProvider(fallback: "A 结果"), data: data())
            let intent = CineAIIntentRouter.route("找一部时间循环的喜剧")
            let r = try await rag.answer(intent, input: "找一部时间循环的喜剧")
            check(intent == .findMovie && r.text == "A 结果", "E2E-A findMovie 链路")
        } catch {
            check(false, "E2E-A findMovie 链路")
        }

        // B) spoilerSafe 未看完 → Shield 本地拦截，不走 RAG
        let blocked = CineAISpoilerShield.blockReason(question: "大结局是什么", hasSeenFinal: false)
        check(blocked != nil && blocked!.contains("结局"), "E2E-B shield 拦截")

        // C) spoilerSafe 看完 → 放行，走 RAG，user 注入进度
        do {
            let cap = CaptureProvider()
            let rag = CineAIRAG(provider: cap, data: data())
            let r = try await rag.answer(.spoilerSafe, input: "后面怎么了")
            let user = cap.captured.first { $0.role == "user" }?.content ?? ""
            check(r.text == "ok" && user.contains("已看到"), "E2E-C spoilerSafe 放行+进度注入")
        } catch {
            check(false, "E2E-C spoilerSafe 放行+进度注入")
        }

        // D) 数据源为空（TMDB 无结果）→ 不 crash，prompt 含降级提示
        do {
            let cap = CaptureProvider()
            let rag = CineAIRAG(provider: cap, data: .init(
                fetchFacts: { _ in "" }, searchMovies: { _ in "" }, spoilerContext: { "" }))
            _ = try await rag.answer(.findMovie, input: "一部不存在的冷门")
            let user = cap.captured.first { $0.role == "user" }?.content ?? ""
            check(user.contains("检索到"), "E2E-D 无结果降级提示")
        } catch {
            check(false, "E2E-D 无结果降级提示")
        }

        // E) 统一错误：Provider 抛 networkTimeout → 上层拿到 displayText
        do {
            let rag = CineAIRAG(provider: ErrorStub(.networkTimeout), data: data())
            _ = try await rag.answer(.findMovie, input: "试试")
            check(false, "E2E-E 应抛错")
        } catch {
            let text = (error as? CineAIError)?.displayText ?? ""
            check(text.contains("超时"), "E2E-E 错误映射为 displayText")
        }

        // F) 非影视操作硬拦截：不调模型、返回固定影视助手回复
        do {
            let rag = CineAIRAG(provider: ErrorStub(.networkTimeout), data: data())
            let r = try await rag.answer(.offScope, input: "帮我写一篇推文")
            check(r.text.contains("影视助手") && r.text.contains("找片"), "E2E-F offScope 固定回复且不调模型")
        } catch {
            check(false, "E2E-F offScope 应不抛错")
        }

        // G) 历史裁剪：多轮长对话后历史被限制，避免请求体过大触发 413 input too large。
        do {
            let cap = CaptureProvider()
            let rag = CineAIRAG(provider: cap, data: data())
            // 塞入 30 条超长历史（远超 6 条 / 3000 字符上限）
            var huge: [AIChatMessage] = []
            for i in 0..<30 {
                huge.append(AIChatMessage(
                    role: i % 2 == 0 ? "user" : "assistant",
                    content: "这是第\(i)条很长的历史消息，内容反复出现以撑大请求体。" + String(repeating: "字", count: 200)
                ))
            }
            _ = try await rag.answer(.findMovie, input: "找一部动作片", history: huge)
            let captured = cap.captured
            let systemCount = captured.filter { $0.role == "system" }.count
            // 历史条数应远少于 30
            let historyCount = captured.count - systemCount
            check(historyCount <= 7, "E2E-G 历史被裁剪(\(historyCount) <= 7)")
            // 历史总字符应被限制在预算内（30 条 × ~210 字 = 6300，应被压到预算内）
            let historyChars = captured
                .filter { $0.role != "system" }
                .reduce(0) { $0 + $1.content.count }
            check(historyChars <= 3200, "E2E-G 历史总长受限(\(historyChars) <= 3200)")
        } catch {
            check(false, "E2E-G 历史裁剪不抛错")
        }
    }
}
