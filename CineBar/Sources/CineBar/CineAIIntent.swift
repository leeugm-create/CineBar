import Foundation

/// CineAI V1 的四大能力。
enum CineAIIntent: Equatable {
    /// 自然语言找电影
    case findMovie
    /// 进度感知防剧透问答
    case spoilerSafe
    /// 影视问答（这部剧/片讲什么）
    case mediaIntro
    /// 今晚看什么（推荐）
    case recommend
}

/// 把用户输入路由到四大能力之一（V1 用轻量关键词规则，离线、可测、零成本）。
/// 后续若规则不能满足，可替换为"在线模型意图识别"，但 V1 先保持简单可靠。
enum CineAIIntentRouter {

    static func route(_ input: String) -> CineAIIntent {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return .findMovie }

        // 防剧透：含"剧透/剧透吗/结局/谁死了/最后.../别剧透"等。
        if contains(text, anyOf: [
            "剧透", "结局", "谁死", "最后", "活没活", "死了没", "别剧透",
            "凶手", "真相", "反转", "大结局",
        ]) {
            return .spoilerSafe
        }

        // 推荐："今晚看什么/推荐/看点什么/求推荐/有没有好看的"
        if contains(text, anyOf: [
            "今晚看什么", "推荐", "看点什么", "求推荐", "有什么好看", "片单",
        ]) {
            return .recommend
        }

        // 该剧/片讲什么："这部剧讲什么/介绍/剧情/讲什么/讲述"
        if contains(text, anyOf: [
            "讲什么", "讲的是", "剧情", "介绍", "简介", "讲述", "这是个",
        ]) {
            return .mediaIntro
        }

        // 其余默认为找片
        return .findMovie
    }

    private static func contains(_ text: String, anyOf keywords: [String]) -> Bool {
        keywords.contains { text.localizedCaseInsensitiveContains($0) }
    }
}
