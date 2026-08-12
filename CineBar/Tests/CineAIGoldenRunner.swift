import Foundation

/// CineAI 真模型 Golden Set 运行器。
///
/// 组合「客户端逻辑 + 真实代理 + 真模型」，逐条输出真实回答供人工核对。
/// 用途：在 20 项离线评测基础上，验证真模型的回答质量与防剧透可靠性。
///
/// 只测代理真链路，不含 MovieStore/UI；进度/找片候选用注入 mock。
/// 走代理的 provider 在此自写（不依赖 CineAIDeepSeekProvider.swift 里的 provider）。
///
/// 运行（需代理已部署、DEEPSEEK_API_KEY 已配）：
///   xcrun swiftc -parse-as-library -target arm64-apple-macosx13.0 -o /tmp/golden \
///     CineBar/Sources/CineBar/CineAIProvider.swift \
///     CineBar/Sources/CineBar/CineAIError.swift \
///     CineBar/Sources/CineBar/CineAIIntent.swift \
///     CineBar/Sources/CineBar/CineMovieQuery.swift \
///     CineBar/Sources/CineBar/CineAISpoilerShield.swift \
///     CineBar/Sources/CineBar/CineAIRAG.swift \
///     CineBar/Tests/CineAIGoldenRunner.swift
@main
struct CineAIGoldenRunner {

    /// 自写"走真实代理"的 provider：URLSession 调 /v1/chat/completions。
    private final class ProxyClient: AIProvider {
        let base = URL(string: "https://cineai.cinebar.cc/v1/chat/completions")!
        let device = "golden-runner"
        func complete(
            messages: [AIChatMessage], maxTokens: Int?, reasoning: Bool
        ) async throws -> AIResult {
            var req = URLRequest(url: base)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let payload: [String: Any] = [
                "device": device,
                "messages": messages.map { ["role": $0.role, "content": $0.content] },
            ]
            req.httpBody = try JSONSerialization.data(withJSONObject: payload)
            var data: Data
            var response: URLResponse
            do {
                (data, response) = try await URLSession.shared.data(for: req)
            } catch let e as URLError {
                throw e.code == .timedOut ? CineAIError.networkTimeout : CineAIError.networkUnavailable
            }
            guard let http = response as? HTTPURLResponse else { throw CineAIError.badResponse }
            guard http.statusCode == 200 else {
                if http.statusCode == 429 { throw CineAIError.rateLimited }
                if http.statusCode >= 500 { throw CineAIError.serverError }
                throw CineAIError.badResponse
            }
            let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            guard let result = body?["result"] as? [String: Any] else { throw CineAIError.badResponse }
            let choices = result["choices"] as? [[String: Any]]
            let first = choices?.first
            let msg = first?["message"] as? [String: Any]
            let text = msg?["content"] as? String ?? ""
            let usage = result["usage"] as? [String: Any]
            return AIResult(
                text: text,
                inputTokens: (usage?["prompt_tokens"] as? Int) ?? 0,
                outputTokens: (usage?["completion_tokens"] as? Int) ?? 0
            )
        }
    }

    /// 模拟一份"看过的集"进度上下文（防剧透数据源，替代 MovieStore）。
    private static func seenContext() -> String {
        "《绝命毒师》你已看到 S03E01。S01E01 试飞噩梦、S01E02 分水岭、S01E03 肿瘤诊断、S01E04 Let's get to it、S01E05 赌注、S01E06 守财奴、S01E07 一条黑道、S02E01 第837号、S02E02 赌气、S02E03 绿洲、S02E04 溃败、S02E05 凶器、S02E06 下注、S02E07 黑与蓝、S02E08 更好的呼叫索尔、S02E09 四天缺一、S02E10 豁免、S02E11 满月、S02E12 曼陀罗、S02E13 凤凰、S03E01 无人知晓"
    }

    static func caseRun(
        _ name: String, intent: CineAIIntent, input: String,
        data: CineAIRAG.DataSource
    ) async {
        do {
            let rag = CineAIRAG(provider: ProxyClient(), data: data)
            let result = try await rag.answer(intent, input: input)
            print("\n=== \(name) === intent=\(intent) input=「\(input)」")
            print("回复：\(result.text)")
        } catch CineAIError.rateLimited {
            print("\n=== \(name) === 被限流(429) 未得回答")
        } catch let e as CineAIError {
            print("\n=== \(name) === 错误：\(e.displayText)")
        } catch {
            print("\n=== \(name) === 未知错误：\(error)")
        }
    }

    static func main() async {
        print("CineAI 真模型 Golden Set（人工核对）——代理已部署，V4 Flash\n")

        let mockData = CineAIRAG.DataSource(
            fetchFacts: { _ in "《海上钢琴师》：1998 意大利剧情片，豆瓣 9.3，讲述 1900 于邮轮上的传奇一生。" },
            searchMovies: { _ in "《记忆碎片》(2000) 8.6 悬疑\n《源代码》(2011) 8.4 科幻\n《土拨鼠之日》(1993) 8.3 喜剧奇幻\n《时空恋旅人》(2013) 8.7 喜剧爱情" },
            spoilerContext: { seenContext() }
        )

        // 1) 找片
        await caseRun("找片-时间循环", intent: .findMovie, input: "找一部时间循环的电影", data: mockData)
        await caseRun("找片-深夜孤独", intent: .findMovie, input: "适合深夜独自看的电影", data: mockData)

        // 2) 防剧透：放行后，验证不透露进度之后内容
        await caseRun("防剧透-进度内", intent: .spoilerSafe, input: "你设定老白目前的处境是怎样的", data: mockData)
        await caseRun("防剧透-问后续", intent: .spoilerSafe, input: "老白最后会不会被抓", data: mockData)

        // 3) 影视问答（防编造）
        await caseRun("问答-事实", intent: .mediaIntro, input: "《海上钢琴师》讲的是什么", data: mockData)
        await caseRun("问答-防编造", intent: .mediaIntro, input: "《不存在的这部片xyz》导演是谁", data: mockData)

        // 4) 推荐
        await caseRun("推荐", intent: .recommend, input: "今晚给3部高分冷门片", data: mockData)

        print("\n——人工核对要点：回答是否基于给定候选/进度、是否编造不存在影片、防剧透是否未透露后续 ——")
    }
}
