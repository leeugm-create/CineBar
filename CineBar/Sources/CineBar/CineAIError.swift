import Foundation

/// CineAI 统一的错误模型。
///
/// 原则：CineAI 内部所有失败/业务边界都收敛成 `CineAIError`，
/// 上层（视图层）只读取 `displayText`，禁止直接处理 DeepSeek / HTTP / URLSession 的原始错误。
/// 这样底层网络细节（超时、状态码、响应体）不与 UI 耦合；改 Provider 或网关不影响 UI。
enum CineAIError: Error, Equatable {
    /// 网关/请求超时
    case networkTimeout
    /// 断网/网络不可达
    case networkUnavailable
    /// 429：次数或 token 超限
    case rateLimited
    /// 上游 5xx
    case serverError
    /// 响应 JSON / Schema 异常（解析失败、缺字段）
    case badResponse
    /// TMDB 等数据源无结果
    case noResults
    /// 防剧透需要但无观看进度
    case noProgress
    /// SpoilerShield 本地拦截（业务提示，非真正故障）
    case spoilerBlocked
    /// 其它未预期
    case unknown(String)

    /// 用户可读文案（用于 UI 展示，不泄露底层 HTTP 细节）。
    var displayText: String {
        switch self {
        case .networkTimeout:
            return "请求超时，请稍后重试。"
        case .networkUnavailable:
            return "网络不可用，请检查连接后再试。"
        case .rateLimited:
            return "今日 AI 用量已达上限，请明天再试。"
        case .serverError:
            return "AI 服务暂时出错了，请稍后重试。"
        case .badResponse:
            return "AI 返回了无法解析的内容，请重试。"
        case .noResults:
            return "没有找到符合条件的作品，换个说法试试。"
        case .noProgress:
            return "还没有这部剧的观看进度，先看几集再来问。"
        case .spoilerBlocked:
            return "这条涉及结局/未看到的部分，我替你先不透露。"
        case .unknown(let detail):
            return "出错了：\(detail)"
        }
    }
}
