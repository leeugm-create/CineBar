import Foundation
import AppKit

/// DeepSeek V4 Flash 的 Provider 实现（OpenAI /v1/chat/completions 兼容接口）。
///
/// 计费策略为"开发者代付 + 服务端限额"：
///  - 生产：`baseURL` 指向开发者自己的限额代理（key 不进客户端），由代理转发并限额。
///  - 本地调试：可临时设 baseURL 到 DeepSeek 官方，并传入测试 key，直连验证。
/// 模型名、价格等不写死在业务层；换模型只需换 Provider。
final class DeepSeekProvider: AIProvider {

    /// 服务端代付代理地址，如 "https://cineai-proxy.example.com/v1"。
    private let baseURL: URL
    private let apiKey: String?
    private let model: String
    private let session: URLSession

    init(
        baseURL: URL,
        apiKey: String? = nil,
        model: String = "deepseek-chat",
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.model = model
        self.session = session
    }

    func complete(
        messages: [AIChatMessage],
        maxTokens: Int?,
        reasoning: Bool
    ) async throws -> AIResult {
        let endpoint = baseURL.appendingPathComponent("chat/completions")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKey {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        var body: [String: Any] = [
            "model": model,
            "messages": messages.map { ["role": $0.role, "content": $0.content] },
        ]
        if let maxTokens {
            body["max_tokens"] = maxTokens
        }
        if reasoning {
            // V1 一律非思考；此开关为未来复杂推荐预留。
            body["reasoning"] = true
        }
        request.httpBody = try JSONSerialization.data(
            withJSONObject: body,
            options: []
        )

        var data: Data
        var response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let urlError as URLError {
            if urlError.code == .timedOut {
                throw CineAIError.networkTimeout
            }
            throw CineAIError.networkUnavailable
        }
        guard let http = response as? HTTPURLResponse else {
            throw CineAIError.badResponse
        }
        guard http.statusCode == 200 else {
            if http.statusCode == 429 {
                throw CineAIError.rateLimited
            }
            if http.statusCode >= 500 {
                throw CineAIError.serverError
            }
            throw CineAIError.badResponse
        }

        let payload = try JSONDecoder().decode(ChatCompletion.self, from: data)
        let text = payload.choices.first?.message.content ?? ""
        let usage = payload.usage
        return AIResult(
            text: text,
            inputTokens: usage?.promptTokens ?? 0,
            outputTokens: usage?.completionTokens ?? 0
        )
    }
}

// MARK: - DeepSeek/OpenAI chat completions 响应模型

private struct ChatCompletion: Decodable {
    struct Choice: Decodable {
        struct Msg: Decodable {
            let content: String?
        }
        let message: Msg
    }
    struct Usage: Decodable {
        let promptTokens: Int?
        let completionTokens: Int?
        enum CodingKeys: String, CodingKey {
            case promptTokens = "prompt_tokens"
            case completionTokens = "completion_tokens"
        }
    }
    let choices: [Choice]
    let usage: Usage?
}

/// 走「服务端代理」的 Provider：客户端只发 messages + 匿名 device，
/// 不接触任何模型 Key（Key 由代理保管并做限额/缓存）。这是产品正式路径。
final class CineAIProxyProvider: AIProvider {

    private let baseURL: URL
    private let device: String
    private let session: URLSession
    init(
        baseURL: URL,
        device: String = CineBarDeviceIdentity.value(),
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.device = device
        self.session = session
    }

    func complete(
        messages: [AIChatMessage],
        maxTokens: Int?,
        reasoning: Bool
    ) async throws -> AIResult {
        let endpoint = baseURL.appendingPathComponent("v1/chat/completions")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload: [String: Any] = [
            "device": device,
            "messages": messages.map { ["role": $0.role, "content": $0.content] },
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        var data: Data
        var response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let urlError as URLError {
            if urlError.code == .timedOut {
                throw CineAIError.networkTimeout
            }
            throw CineAIError.networkUnavailable
        }
        guard let http = response as? HTTPURLResponse else {
            CineBarLogCenter.recordProxyFailure(status: -1, body: data, baseURL: baseURL)
            throw CineAIError.badResponse
        }
        // 非 200：收敛到统一错误（429→限流，5xx→服务错，其它→badResponse）。
        guard http.statusCode == 200 else {
            CineBarLogCenter.recordProxyFailure(status: http.statusCode, body: data, baseURL: baseURL)
            switch http.statusCode {
            case 429: throw CineAIError.rateLimited
            case 500..<600: throw CineAIError.serverError
            default: throw CineAIError.badResponse
            }
        }
        let body = (try? JSONSerialization.jsonObject(with: data))
            as? [String: Any]
        // 代理返回 { cached, result: <DeepSeek chat/completions 响应> }。
        guard let result = body?["result"] as? [String: Any] else {
            CineBarLogCenter.recordProxyFailure(status: http.statusCode, body: data, baseURL: baseURL)
            throw CineAIError.badResponse
        }
        let choices = result["choices"] as? [[String: Any]]
        let firstMessage = choices?.first?["message"] as? [String: Any]
        let text = firstMessage?["content"] as? String ?? ""
        let usage = result["usage"] as? [String: Any]
        return AIResult(
            text: text,
            inputTokens: (usage?["prompt_tokens"] as? Int) ?? 0,
            outputTokens: (usage?["completion_tokens"] as? Int) ?? 0
        )
    }
}

/// CineBar 本地错误日志中心：统一记录各类故障（AI/网络/播放/数据源等）到
/// ~/Library/Logs/CineBar/cinebar.log，供排查问题与后续上传分析。
/// 只记技术诊断（错误码、来源、摘要、时间），不记对话内容与个人隐私。
enum CineBarLogCenter {
    private static let logURL: URL = {
        let fm = FileManager.default
        let base = fm.urls(for: .libraryDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library")
        let dir = base.appendingPathComponent("Logs/CineBar", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("cinebar.log")
    }()

    private static let stampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    private static let lock = NSLock()

    /// 追加一条日志。category：错误来源（ai/proxy/playback/network/magnet/…）。
    static func log(_ category: String, _ message: String) {
        let stamp = stampFormatter.string(from: Date())
        let line = "[\(stamp)] [\(category)] \(message)\n"
        lock.lock()
        defer { lock.unlock() }
        if let handle = try? FileHandle(forWritingTo: logURL) {
            handle.seekToEndOfFile()
            if let d = line.data(using: .utf8) { try? handle.write(contentsOf: d) }
            try? handle.close()
        } else {
            try? line.data(using: .utf8)?.write(to: logURL)
        }
    }

    /// 记录一次 AI 代理调用失败（含状态码与响应体前缀），供排查"无法解析"等 badResponse。
    static func recordProxyFailure(status: Int, body: Data, baseURL: URL) {
        var msg = "proxy status=\(status) url=\(baseURL.absoluteString)"
        if let s = String(data: body.prefix(2000), encoding: .utf8) {
            msg += " body=\(s)"
        } else {
            msg += " body=<非utf8 \(body.count)字节>"
        }
        log("ai/proxy", msg)
    }

    /// 日志文件路径（给用户排查用）。
    static var logFilePath: String { logURL.path }

    /// 日志文件内容（最多返回尾部若干 KB），供导出/上传。
    static func recentLog(maxBytes: Int = 16_384) -> String {
        guard let data = try? Data(contentsOf: logURL) else { return "" }
        let s = String(data: data, encoding: .utf8) ?? ""
        guard s.utf8.count > maxBytes else { return s }
        let start = s.utf8.index(s.utf8.startIndex, offsetBy: s.utf8.count - maxBytes)
        return String(s[start...])
    }

    /// 用系统默认文本编辑器打开日志文件，方便用户查看/手动发送。
    static func openLogFile() {
        NSWorkspace.shared.open(logURL)
    }

    /// 把最近日志复制到剪贴板，供用户粘贴发给开发者。
    static func copyLogToPasteboard() -> String {
        let content = recentLog(maxBytes: 16_384)
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(content, forType: .string)
        return content
    }

    /// 构造"邮件发送日志"的 mailto URL（日志作为正文），打开默认邮件客户端。
    static func mailLog(to email: String) {
        let content = recentLog(maxBytes: 16_384)
        let body = "以下是我遇到的 CineBar 错误日志（仅技术诊断）：\n\n" + content
        var comps = URLComponents()
        comps.scheme = "mailto"
        comps.path = email
        comps.queryItems = [
            URLQueryItem(name: "subject", value: "CineBar 错误日志反馈"),
            URLQueryItem(name: "body", value: body),
        ]
        if let url = comps.url {
            NSWorkspace.shared.open(url)
        }
    }
}
