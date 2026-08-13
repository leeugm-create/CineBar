import SwiftUI

/// 从文本里提取《片名》（中文《…》内容，去空/去重，保持出现顺序）。
/// 供回答气泡的海报条复用。
func cineAITitles(from text: String, limit: Int = Int.max) -> [String] {
    guard let regex = try? NSRegularExpression(pattern: #"《([^》]+)》"#) else { return [] }
    let ns = text as NSString
    let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
    var titles: [String] = []
    var seen = Set<String>()
    for m in matches {
        let t = ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespaces)
        if !t.isEmpty, seen.insert(t).inserted {
            titles.append(t)
            if titles.count >= limit { break }
        }
    }
    return titles
}

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
    @State private var input = ""
    @State private var busy = false
    @FocusState private var inputFocused: Bool

    /// 对话历史来自 store（持久化到多轮重进）。
    private var messages: [AIChatMessage] {
        store.cineAIMessages
    }

    private var canSend: Bool {
        !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static let quickPrompts: [(String, String)] = [
        ("🎬 今晚看什么", "今晚看什么，推荐几部"),
        ("🔍 帮我找一部电影", "帮我找一部电影"),
        ("📺 这部剧讲什么", "这部剧讲什么"),
        ("🚫 无剧透问答", "别剧透，我只想聊到目前进度为止"),
    ]

    var body: some View {
        VStack(spacing: 4) {
            // 快捷入口：点击直接触发对应能力（立即发送）。
            HStack(spacing: 6) {
                ForEach(Self.quickPrompts, id: \.0) { title, prompt in
                    Button {
                        send(prompt)
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
                    .disabled(busy)
                }
                Spacer()
                Button {
                    clearChat()
                } label: {
                    Label("清屏", systemImage: "trash")
                        .font(.caption)
                }
                .controlSize(.small)
                .buttonStyle(.borderless)
                .help("清空当前聊天记录")
                Button("返回") { store.isShowingCineAI = false }
                    .controlSize(.small)
                    .buttonStyle(.bordered)
            }
            .padding(.horizontal)

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        // 只显示 user/assistant；system 不当作气泡。
                        let visible = messages.filter { $0.role != "system" }
                        if visible.isEmpty {
                            welcomeView
                        } else {
                            ForEach(Array(visible.enumerated()), id: \.offset) { _, msg in
                                chatBubble(msg)
                            }
                            if busy {
                                thinkingBubble
                            }
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 6)
                }
                .onAppear {
                    // 重新进入聊天框：自动滚到最底部（最新消息），避免停在顶部。
                    DispatchQueue.main.async {
                        withAnimation(.none) {
                            proxy.scrollTo("bottom", anchor: .bottom)
                        }
                    }
                }
                .onChange(of: messages) { _ in
                    // 有新消息/回答后滚到底部
                    withAnimation {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
                .onChange(of: busy) { isBusy in
                    // 显示/隐藏"思考中"时也滚到底部
                    if isBusy {
                        withAnimation {
                            proxy.scrollTo("bottom", anchor: .bottom)
                        }
                    }
                }
            }

            // 输入（composer）：圆角聚焦容器 + 圆形发送按钮，固定在底部。
            HStack(alignment: .center, spacing: 8) {
                TextField("问问 CineAI…例如：找一部80年代喜剧港片", text: $input)
                    .textFieldStyle(.plain)
                    .focused($inputFocused)
                    .onSubmit { send() }
                    .disabled(busy)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .frame(height: 34)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(Color.secondary.opacity(0.08))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(
                                inputFocused
                                    ? Color.accentColor.opacity(0.7)
                                    : Color.secondary.opacity(0.25),
                                lineWidth: 1
                            )
                    )
                Button {
                    send()
                } label: {
                    Image(systemName: busy ? "hourglass" : "paperplane.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(
                            Circle().fill(
                                canSend
                                    ? Color.accentColor
                                    : Color.secondary.opacity(0.3)
                            )
                        )
                }
                .buttonStyle(.plain)
                .disabled(busy || input.trimmingCharacters(in: .whitespaces).isEmpty)
                .help("发送")
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            // 底部拉伸手柄：拖动可上下调整窗口高度（与主页一致）。
            Divider()
            HStack {
                Spacer()
                ZStack {
                    ResizeTriangle()
                        .fill(.secondary.opacity(0.55))
                        .padding(3)
                    VerticalResizeHandle()
                }
                .frame(width: 24, height: 24)
                .help("拖动这里可上下拉伸")
            }
            .font(.caption)
            .padding(.horizontal)
            .frame(height: 32)
        }
        // 给 CineAI 页面加不透明背景，避免面板透明（isOpaque=false）时透出桌面。
        .background {
            Color(nsColor: .windowBackgroundColor)
                .opacity(max(store.glassBackgroundOpacity, 0.92))
        }
        .environment(\.openURL, OpenURLAction { url in
            // 点击回答里的《片名》→ 按片名进入详情页。
            if url.scheme == "cineai", url.host == "title" {
                let title = url.pathComponents.dropFirst().joined(separator: "/")
                    .removingPercentEncoding ?? ""
                if !title.isEmpty {
                    store.selectMovieByTitle(title)
                }
                return .handled
            }
            return .systemAction
        })
        .onAppear {
            // 进入聊天：光标自动落到输入框，随时可打字。
            inputFocused = true
            consumePendingQuery()
        }
        .onChange(of: store.cineAIPendingQuery) { _ in
            // 面板已开着时从菜单栏再次搜索，也要能消费并发送。
            consumePendingQuery()
        }
    }

    /// 消费菜单栏搜索框带入的待发送查询：有则清空并直接发送。
    private func consumePendingQuery() {
        guard let pending = store.cineAIPendingQuery, !pending.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        store.cineAIPendingQuery = nil
        send(pending)
    }

    /// 空态引导：告诉用户 4 个能力能干嘛。
    private var welcomeView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CineAI 影视助手")
                .font(.headline)
            Text("可以直接跟我聊：")
                .font(.caption)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text("🎬 今晚看什么 —— 给我片单/按心情推荐")
                Text("🔍 帮我找一部电影 —— 用一句话描述想看的片")
                Text("📺 这部剧讲什么 —— 问某部剧/片的剧情")
                Text("🚫 无剧透问答 —— 记住你的观看到哪，不剧透后面")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
    }

    /// 发送中气泡：提示模型正在回答，避免"点了没反应"。
    private var thinkingBubble: some View {        HStack {
            ProgressView().controlSize(.small)
            Text("正在思考…")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 40)
        }
        .padding(10)
        .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
    }

    private func chatBubble(_ msg: AIChatMessage) -> some View {
        HStack(alignment: .bottom) {
            if msg.role == "user" {
                Spacer(minLength: 40)
            }
            VStack(alignment: msg.role == "user" ? .trailing : .leading, spacing: 3) {
                if msg.role == "user" {
                    Text(msg.content)
                        .font(.callout)
                        .textSelection(.enabled)
                        .padding(10)
                        .background(
                            Color.accentColor.opacity(0.16),
                            in: RoundedRectangle(cornerRadius: 10)
                        )
                } else {
                    // assistant：来源标签 + 内容（片名《…》可点击进详情）。
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 9, weight: .bold))
                        Text("CineBar AI")
                            .font(.system(size: 10, weight: .medium))
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(.secondary)
                    Text(linkedText(msg.content))
                        .font(.callout)
                        .textSelection(.enabled)
                        .tint(.orange)
                        .padding(10)
                        .background(
                            Color.secondary.opacity(0.10),
                            in: RoundedRectangle(cornerRadius: 10)
                        )
                    AIPosterStrip(message: msg.content, store: store)
                }
                timestampView(msg)
            }
            if msg.role == "assistant" {
                Spacer(minLength: 40)
            }
        }
        .contentShape(Rectangle())
    }

    /// 气泡下方的时间戳：显示该条消息的产生时间（已存时间则显示，否则不显示）。
    @ViewBuilder
    private func timestampView(_ msg: AIChatMessage) -> some View {
        if let date = msg.publishedAt {
            Text(formattedTime(date))
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
                .textSelection(.disabled)
        }
    }

    private func formattedTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }

    /// 回答完即结束：截掉末尾的问题延展（反问/引导继续对话），避免把用户带偏一直聊下去。
    /// 硬兜底——即使模型还是加了，也会被这里去掉。
    private func trimFollowUp(_ raw: String) -> String {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // 用换行分段（推荐列表/多段回答），从末尾起逐句看是否为延展句，是则去掉。
        var parts = text.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        while let last = parts.last, !last.isEmpty {
            if Self.isFollowUpLine(last) {
                parts.removeLast()
            } else {
                break
            }
        }
        // 若整段是一句话，用正则去掉末尾的问句延展。
        let joined = parts.joined(separator: "\n")
        let trimmed = Self.stripTrailingFollowUp(joined)
        return trimmed.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isFollowUpLine(_ line: String) -> Bool {
        let triggers = [
            "要不要", "想不想", "需要我", "需要的话", "如果你感兴趣",
            "还想看", "还想了解", "还想找", "可以告诉我", "告诉我吧",
            "感兴趣吗", "想看吗", "了解吗", "试试吗", "要看看吗",
            "随时告诉我", "随时问我", "有需要可以",
        ]
        return triggers.contains { line.localizedCaseInsensitiveContains($0) }
    }

    private static func stripTrailingFollowUp(_ text: String) -> String {
        // 去掉末尾"？"前的延展句（如"要不要我帮你找别的？"）
        var result = text
        var changed = true
        while changed {
            changed = false
            let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let range = trimmed.range(of: "(?:[。！？!?]|^)\\s*[^。！？!?]*?(要不要|想不想|需要我|想了解更多|感兴趣吗|想看吗)[^。！？!?]*[？?]$", options: .regularExpression) else { break }
            let cut = trimmed.distance(from: trimmed.startIndex, to: range.lowerBound)
            if cut <= 0 { break }
            let newText = String(trimmed.prefix(cut))
            if newText.count < result.count {
                result = newText
                changed = true
            } else {
                break
            }
        }
        return result
    }

    /// 把 AI 回答里的《片名》渲染成可点击链接（scheme: cineai://title/…）。
    private func linkedText(_ raw: String) -> AttributedString {
        var attr = AttributedString(raw)
        guard let regex = try? NSRegularExpression(
            pattern: #"《([^》]+)》"#
        ) else { return attr }
        let ns = raw as NSString
        let matches = regex.matches(in: raw, range: NSRange(location: 0, length: ns.length))
        for m in matches {
            let title = ns.substring(with: m.range(at: 1))
            guard !title.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            let rawStart = raw.utf16.index(raw.utf16.startIndex, offsetBy: m.range.location)
            let rawEnd = raw.utf16.index(
                raw.utf16.startIndex, offsetBy: m.range.location + m.range.length)
            guard let start = AttributedString.Index(rawStart, within: attr),
                  let end = AttributedString.Index(rawEnd, within: attr),
                  start < end else { continue }
            let r = start..<end
            attr[r].link = URL(
                string: "cineai://title/"
                    + (title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")
            )
            attr[r].inlinePresentationIntent = .stronglyEmphasized
        }
        return attr
    }

    /// 从回答文本提取片名（中文《…》内的内容，去空/去重）；无则返回 nil。
    private func extractTitles(from text: String) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: #"《([^》]+)》"#
        ) else { return nil }
        let ns = text as NSString
        let matches = regex.matches(
            in: text,
            range: NSRange(location: 0, length: ns.length)
        )
        var titles: [String] = []
        var seen = Set<String>()
        for m in matches {
            let t = ns.substring(with: m.range(at: 1))
                .trimmingCharacters(in: .whitespaces)
            if !t.isEmpty, seen.insert(t).inserted {
                titles.append(t)
            }
        }
        return titles.isEmpty ? nil : titles.joined(separator: " ")
    }

    private func copyToPasteboard(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    /// 发送：支持显式传入 prompt（快捷入口直接触发）；否则用输入框内容。
    /// 清空当前聊天记录（恢复为初始 system 提示），用户自行决定是否清除。
    private func clearChat() {
        busy = false
        input = ""
        var system = messages.first { $0.role == "system" }
        if system == nil {
            system = AIChatMessage(
                role: "system",
                content: "你是 CineAI，CineBar 的影视助手。回答用中文、简洁；影视事实以提供的数据为准，不编造。"
            )
        }
        store.cineAIMessages = [system!]
    }

    private func send(_ promptOverride: String? = nil) {
        let text = (promptOverride ?? input)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !busy else { return }
        input = ""
        let userMsg = AIChatMessage(role: "user", content: text)
        store.cineAIMessages.append(userMsg)
        busy = true

        let intent = CineAIIntentRouter.route(text)
        // spoilerSafe 先做本地硬拦截：结局类问题 + 未看完 → 直接挡回，不进模型、不耗 token。
        if intent == .spoilerSafe,
           let shield = store.spoilerShield(for: text) {
            store.cineAIMessages.append(
                AIChatMessage(role: "assistant", content: shield)
            )
            busy = false
            return
        }
        // 历史：发送前已有的 user/assistant 对话（含上文），供 AI 联想读取。
        let history = messages.filter { $0.role != "system" }
        let rag = store.makeCineAIRAG(provider: CineAIProviderFactory.make())
        Task {
            do {
                let result = try await rag.answer(intent, input: text, history: history)
                await MainActor.run {
                    store.cineAIMessages.append(
                        AIChatMessage(role: "assistant", content: trimFollowUp(result.text))
                    )
                }
            } catch {
                // 统一错误模型：只展示 displayText，不直接处理底层网络/HTTP 原始错误。
                let text = (error as? CineAIError)?.displayText
                    ?? "出错了，请重试。"
                CineBarLogCenter.log(
                    "ai/answer",
                    "调用失败 error=\(error) display=\(text) intent=\(intent)"
                )
                await MainActor.run {
                    store.cineAIMessages.append(
                        AIChatMessage(role: "assistant", content: text)
                    )
                }
            }
            await MainActor.run { busy = false }
        }
    }
}

/// 回答气泡下方的海报条：从消息里提取《片名》（最多 5 部），
/// 逐部 TMDB 解析并展示海报小卡；点击海报进入对应详情页。
/// 无海报命中或解析失败时不做任何展示（降级为纯文字，不影响聊天）。
private struct AIPosterStrip: View {
    let message: String
    @ObservedObject var store: MovieStore

    @State private var movies: [Movie] = []
    @State private var loaded = false

    private static let maxPosters = 5
    /// 已展示片名缓存，避免同一回复重复解析。
    private static var titleCache: [String: [Movie]] = [:]

    var body: some View {
        Group {
            if !movies.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(movies.enumerated()), id: \.offset) { _, movie in
                            AIPosterCard(movie: movie) {
                                store.selectMovieByTitle(movie.title)
                            }
                        }
                    }
                }
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            load()
        }
    }

    private func load() {
        let titles = cineAITitles(from: message, limit: Self.maxPosters)
        let cacheKey = message
        if let cached = Self.titleCache[cacheKey] {
            movies = cached
            return
        }
        Task {
            var resolved: [Movie] = []
            for title in titles {
                if let m = await store.cineAIMovieByTitle(title) {
                    resolved.append(m)
                }
            }
            Self.titleCache[cacheKey] = resolved
            await MainActor.run { movies = resolved }
        }
    }
}

/// 单张海报小卡：海报图 + 片名叠底，点击进详情。
private struct AIPosterCard: View {
    let movie: Movie
    let action: () -> Void

    @State private var posterImage: NSImage?

    var body: some View {
        Button {
            action()
        } label: {
            VStack(spacing: 2) {
                Group {
                    if let posterImage {
                        Image(nsImage: posterImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 72, height: 104)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    } else {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.secondary.opacity(0.15))
                            .frame(width: 72, height: 104)
                            .overlay(
                                Text(verbatim: String(movie.title.prefix(2)))
                                    .font(.caption.bold())
                                    .foregroundStyle(.secondary)
                            )
                    }
                }
                Text(movie.title)
                    .font(.system(size: 10))
                    .lineLimit(1)
                    .frame(width: 72)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .task {
            guard posterImage == nil, let url = movie.posterURL else { return }
            posterImage = await cachedPosterImage(for: url)
        }
    }
}
