import Foundation

/// spoilerSafe 的本地硬拦截（不靠 LLM、不耗 token）：识别"结局类/剧终类"问题，
/// 若该剧用户还没看完，就直接在本地挡住，根本不让这类越界问题进入模型。
///
/// 原则：
///  - 只拦"全局结局/剧终"型问题（结局、大结局、谁死了、凶手是谁……）。
///  - 判定"是否可能越界"用「该剧是否已看完」：看完了就不拦（用户有资格问结局）。
///  - 非结局型（如某集片段），本地不拦，交给模型按注入的已看上下文答。
///  - 这是启发式硬拦截，宁可多挡，不剧透。
enum CineAISpoilerShield {

    /// 强"结局/剧终"触发词（命中即视为越界敏感）。
    private static let finalKeywords: [String] = [
        "大结局", "结局", "剧终", "结尾", "尾声", "收场", "落幕",
        "谁死", "死了", "凶手", "元凶", "真凶", "最终", "最后结局",
    ]

    /// 判定是否需要本地拦截。
    /// - Parameters:
    ///   - question: 用户问题。
    ///   - hasSeenFinal: 该剧是否已看完（进度到最后一季/最后一集）。
    /// - Returns: 非 nil 表示要拦截，返回给用户看的提示文案；nil 表示放行。
    static func blockReason(
        question: String,
        hasSeenFinal: Bool
    ) -> String? {
        guard !hasSeenFinal else { return nil }
        let hit = finalKeywords.contains { question.localizedCaseInsensitiveContains($0) }
        guard hit else { return nil }
        return "这条涉及结局/未看到的部分，我替你先不透露——等你看到大结局再来问，留个惊喜。"
    }
}
