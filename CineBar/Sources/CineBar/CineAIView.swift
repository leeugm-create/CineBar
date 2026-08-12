import SwiftUI

/// CineAI 的 Provider 工厂：从 UserDefaults 读配置（本地开发可直连 DeepSeek，
/// 生产走服务端限额代理）。未配置时用 Stub（提示未配置，不联网、不乱答）。
struct CineAIProviderFactory {
    static func make() -> AIProvider {
        let d = UserDefaults.standard
        if let base = d.string(forKey: "cineai.baseURL"),
           !base.isEmpty {
            return DeepSeekProvider(
                baseURL: URL(string: base)!,
                apiKey: d.string(forKey: "cineai.apiKey"),
                model: d.string(forKey: "cineai.model") ?? "deepseek-chat"
            )
        }
        return StubAIProvider(fallback: "尚未配置 CineAI 模型（请在设置里配置 baseURL / API Key）。")
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
                await MainActor.run {
                    messages.append(
                        AIChatMessage(role: "assistant", content: "出错：\(error.localizedDescription)")
                    )
                }
            }
            await MainActor.run { busy = false }
        }
    }
}
