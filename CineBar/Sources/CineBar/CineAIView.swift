import SwiftUI

/// CineAI 的 Provider 工厂（产品正式路径**只走服务端代理**，不走任何直连）。
///
/// 硬防线：baseURL 的 host 必须在允许的代理白名单内，否则拒绝——
/// 防止 UserDefaults 被误配/污染成直连 DeepSeek 而绕过代理/限额。
struct CineAIProviderFactory {
    /// 允许的代理 host（含默认域名）。其它一律拒绝。
    private static let allowedProxyHosts: Set<String> = [
        "cineai.cinebar.cc",
    ]
    private static let defaultProxy = "https://cineai.cinebar.cc"

    static func make() -> AIProvider {
        let d = UserDefaults.standard
        let base = d.string(forKey: "cineai.proxyBaseURL")
            ?? defaultProxy
        let url = URL(string: base)
        guard let url,
              let host = url.host,
              allowedProxyHosts.contains(host.lowercased()) else {
            // 非法/被污染的 baseURL：拒绝走它，回落到受控代理域。
            return CineAIProxyProvider(
                baseURL: URL(string: defaultProxy)!
            )
        }
        return CineAIProxyProvider(baseURL: url)
    }
}

/// CineAI 聊天界面：消息列表 + 4 个快捷入口 + 输入框。
struct CineAIView: View {
    @ObservedObject var store: MovieStore
    @State private var messages: [AIChatMessage] = [
        AIChatMessage(
            role: "system",
            content: "你是 CineAI，CineBar 的影视助手。回答用中文、简洁；影视事实以提供的数据为准，不编造。"
        )
    ]
    @State private var input = ""
    @State private var busy = false

    private static let quickPrompts: [(String, String)] = [
        ("🎬 今晚看什么", "今晚看什么，推荐几部"),
        ("🔍 帮我找一部电影", "帮我找一部电影"),
        ("📺 这部剧讲什么", "这部剧讲什么"),
        ("🚫 无剧透问答", "别剧透，我只想聊到目前进度为止"),
    ]

    var body: some View {
        VStack(spacing: 8) {
            // 快捷入口
            HStack(spacing: 6) {
                ForEach(Self.quickPrompts, id: \.0) { title, prompt in
                    Button {
                        input = prompt
                    } label: {
                        Text(title)
                            .font(.caption.bold())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(
                                Color.accentColor.opacity(0.12),
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                Button("返回") { store.isShowingCineAI = false }
                    .controlSize(.small)
                    .buttonStyle(.bordered)
            }
            .padding(.horizontal)

            // 消息列表
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(messages.enumerated()), id: \.offset) { _, msg in
                            chatBubble(msg)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 4)
                }
                .onChange(of: messages.count) { _ in
                    if !messages.isEmpty {
                        withAnimation {
                            proxy.scrollTo(messages.count - 1, anchor: .bottom)
                        }
                    }
                }
            }

            // 输入
            HStack(spacing: 6) {
                TextField("问问 CineAI…（例如：找一部时间循环的科幻片）", text: $input)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { send() }
                    .disabled(busy)
                Button {
                    send()
                } label: {
                    if busy {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "paperplane.fill")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(busy || input.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
    }

    private func chatBubble(_ msg: AIChatMessage) -> some View {
        HStack {
            if msg.role == "user" {
                Spacer(minLength: 40)
            }
            Text(msg.content)
                .font(.callout)
                .textSelection(.enabled)
                .padding(10)
                .background(
                    (msg.role == "user"
                        ? Color.accentColor.opacity(0.16)
                        : Color.secondary.opacity(0.10)),
                    in: RoundedRectangle(cornerRadius: 10)
                )
            if msg.role == "assistant" {
                Spacer(minLength: 40)
            }
        }
    }

    private func send() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !busy else { return }
        input = ""
        let userMsg = AIChatMessage(role: "user", content: text)
        messages.append(userMsg)
        busy = true

        let intent = CineAIIntentRouter.route(text)
        // spoilerSafe 先做本地硬拦截：结局类问题 + 未看完 → 直接挡回，不进模型、不耗 token。
        if intent == .spoilerSafe,
           let shield = store.spoilerShield(for: text) {
            messages.append(
                AIChatMessage(role: "assistant", content: shield)
            )
            busy = false
            return
        }
        let rag = store.makeCineAIRAG(provider: CineAIProviderFactory.make())
        Task {
            do {
                let result = try await rag.answer(intent, input: text)
                await MainActor.run {
                    messages.append(
                        AIChatMessage(role: "assistant", content: result.text)
                    )
                }
            } catch {
                // 统一错误模型：只展示 displayText，不直接处理底层网络/HTTP 原始错误。
                let text = (error as? CineAIError)?.displayText
                    ?? "出错了，请重试。"
                await MainActor.run {
                    messages.append(
                        AIChatMessage(role: "assistant", content: text)
                    )
                }
            }
            await MainActor.run { busy = false }
        }
    }
}
