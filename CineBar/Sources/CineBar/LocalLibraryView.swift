import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum LocalLibraryLocalization {
    static func string(_ key: String, language: AppLanguage) -> String {
        let resourceName: String
        switch language {
        case .zhCN: resourceName = "zh-Hans"
        case .zhHK, .zhTW: resourceName = "zh-Hant"
        case .enUS: resourceName = "en"
        case .jaJP: resourceName = "ja"
        case .koKR: resourceName = "ko"
        }
        guard let path = Bundle.main.path(
            forResource: resourceName,
            ofType: "lproj"
        ), let bundle = Bundle(path: path) else {
            return key
        }
        return bundle.localizedString(forKey: key, value: key, table: nil)
    }

    static func message(
        _ message: LocalLibraryStoreMessage,
        language: AppLanguage
    ) -> String {
        let key: String
        switch message {
        case .selectedFolderRemoved:
            key = "所选文件夹已不在片库中。"
        case .folderAuthorizationStale:
            key = "文件夹权限需要更新。请重新添加同一文件夹。"
        case .refreshCancelled:
            key = "片库刷新已取消。"
        case .saveFailed:
            key = "无法保存本地片库。"
        case .selectedEntryRemoved:
            key = "所选片库项目已不存在。"
        }
        return string(key, language: language)
    }
}

enum LocalLibraryGenreLocalization {
    private static let names: [Int: [String]] = [
        12: ["冒险", "冒險", "Adventure", "アドベンチャー", "모험"],
        14: ["奇幻", "奇幻", "Fantasy", "ファンタジー", "판타지"],
        16: ["动画", "動畫", "Animation", "アニメーション", "애니메이션"],
        18: ["剧情", "劇情", "Drama", "ドラマ", "드라마"],
        27: ["恐怖", "恐怖", "Horror", "ホラー", "공포"],
        28: ["动作", "動作", "Action", "アクション", "액션"],
        35: ["喜剧", "喜劇", "Comedy", "コメディ", "코미디"],
        36: ["历史", "歷史", "History", "歴史", "역사"],
        37: ["西部", "西部", "Western", "西部劇", "서부"],
        53: ["惊悚", "驚悚", "Thriller", "スリラー", "스릴러"],
        80: ["犯罪", "犯罪", "Crime", "犯罪", "범죄"],
        99: ["纪录片", "紀錄片", "Documentary", "ドキュメンタリー", "다큐멘터리"],
        878: ["科幻", "科幻", "Science Fiction", "SF", "SF"],
        9648: ["悬疑", "懸疑", "Mystery", "ミステリー", "미스터리"],
        10402: ["音乐", "音樂", "Music", "音楽", "음악"],
        10749: ["爱情", "愛情", "Romance", "ロマンス", "로맨스"],
        10751: ["家庭", "家庭", "Family", "ファミリー", "가족"],
        10752: ["战争", "戰爭", "War", "戦争", "전쟁"],
        10759: ["动作与冒险", "動作與冒險", "Action & Adventure", "アクション＆アドベンチャー", "액션 & 어드벤처"],
        10762: ["儿童", "兒童", "Kids", "キッズ", "키즈"],
        10763: ["新闻", "新聞", "News", "ニュース", "뉴스"],
        10764: ["真人秀", "真人秀", "Reality", "リアリティ", "리얼리티"],
        10765: ["科幻与奇幻", "科幻與奇幻", "Sci-Fi & Fantasy", "SF＆ファンタジー", "SF & 판타지"],
        10766: ["肥皂剧", "肥皂劇", "Soap", "ソープ", "연속극"],
        10767: ["脱口秀", "脫口秀", "Talk", "トーク", "토크"],
        10768: ["战争与政治", "戰爭與政治", "War & Politics", "戦争＆政治", "전쟁 & 정치"],
        10770: ["电视电影", "電視電影", "TV Movie", "テレビ映画", "TV 영화"]
    ]

    static func title(id: Int, language: AppLanguage) -> String {
        guard let values = names[id] else { return String(id) }
        switch language {
        case .zhCN: return values[0]
        case .zhHK, .zhTW: return values[1]
        case .enUS: return values[2]
        case .jaJP: return values[3]
        case .koKR: return values[4]
        }
    }
}

extension LocalLibraryCategoryFilter {
    func title(language: AppLanguage) -> String {
        switch self {
        case .all: return LocalLibraryLocalization.string("全部", language: language)
        case .movie: return LocalLibraryLocalization.string("电影", language: language)
        case .television: return LocalLibraryLocalization.string("电视剧", language: language)
        case .other: return LocalLibraryLocalization.string("其他视频", language: language)
        }
    }
}

extension LocalLibraryStatusFilter {
    func title(language: AppLanguage) -> String {
        switch self {
        case .all: return LocalLibraryLocalization.string("全部", language: language)
        case .unwatched: return LocalLibraryLocalization.string("未看", language: language)
        case .unmatched: return LocalLibraryLocalization.string("待匹配", language: language)
        case .unavailable:
            return LocalLibraryLocalization.string("文件不可用", language: language)
        }
    }
}

struct LocalLibraryView: View {
    @ObservedObject var store: LocalLibraryStore
    @ObservedObject var movieStore: MovieStore

    @Binding var searchText: String
    @Binding var categoryFilter: LocalLibraryCategoryFilter
    @Binding var statusFilter: LocalLibraryStatusFilter
    @State private var actionMessage: String?
    @State private var failedPlaybackPath: String?
    @State private var matchSession: LocalLibraryMatchSession?
    @State private var fileDetailEntry: LocalLibraryEntry?
    @State private var pendingMatchEntry: LocalLibraryEntry?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            filterBar
            if let message = actionMessage ?? store.message.map({
                LocalLibraryLocalization.message(
                    $0,
                    language: movieStore.appLanguage
                )
            }) {
                HStack(alignment: .top, spacing: 8) {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let failedPlaybackPath {
                        Button(localized("复制路径")) {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(
                                failedPlaybackPath,
                                forType: .string
                            )
                        }
                        .buttonStyle(.borderless)
                        .font(.caption)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 6)
            }
            ScrollView {
                LazyVStack(spacing: 8) {
                    if filteredEntries.isEmpty {
                        LocalLibraryEmptyState(
                            state: LocalLibraryEmptyState.library(
                                language: movieStore.appLanguage
                            )
                        )
                        .padding(.top, 48)
                    } else {
                        ForEach(filteredEntries) { entry in
                            LocalLibraryEntryRow(
                                entry: entry,
                                language: movieStore.appLanguage,
                                onPlay: { play(entry) },
                                onToggleWatched: {
                                    store.setWatched(
                                        entryID: entry.id,
                                        value: !entry.isWatched
                                    )
                                },
                                onToggleWatchlist: {
                                    store.toggleWatchlist(entryID: entry.id)
                                },
                                onDetail: { openDetails(for: entry) },
                                onMatch: { findMatches(for: entry) },
                                onRelocate: { relocate(entry) }
                            )
                        }
                    }
                }
                .padding()
            }
        }
        .sheet(item: $matchSession) { session in
            LocalLibraryMatchSheet(
                session: session,
                language: movieStore.appLanguage,
                onConfirm: { candidate in
                    store.confirmMatch(
                        entryID: session.entry.id,
                        metadata: candidate.metadata
                    )
                    matchSession = nil
                    fileDetailEntry = nil
                    guard store.entries.contains(where: {
                        $0.id == session.entry.id &&
                            $0.matchState == .confirmed &&
                            $0.metadata == candidate.metadata
                    }) else { return }
                    openExternalDetail(for: candidate.metadata)
                },
                onDismiss: { matchSession = nil }
            )
        }
        .sheet(item: $fileDetailEntry, onDismiss: presentPendingMatch) { entry in
            LocalLibraryFileDetailView(
                entry: entry,
                folder: store.folders.first { $0.id == entry.folderID },
                language: movieStore.appLanguage,
                onMatch: {
                    pendingMatchEntry = entry
                    fileDetailEntry = nil
                },
                onDismiss: { fileDetailEntry = nil }
            )
        }
    }

    private func presentPendingMatch() {
        guard let entry = pendingMatchEntry else { return }
        pendingMatchEntry = nil
        findMatches(for: entry)
    }

    private var header: some View {
        VStack(spacing: 10) {
            HStack {
                Button {
                    NotificationCenter.default.post(
                        name: .cineBarPanelWillHide,
                        object: nil
                    )
                    NSApplication.shared.keyWindow?.orderOut(nil)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .help(localized("关闭片库"))

                VStack(alignment: .leading, spacing: 2) {
                    Label(localized("本地片库"), systemImage: "externaldrive.fill")
                        .font(.title3.bold())
                    Text(String(format: localized("已添加 %lld 个目录 · %lld 个视频"), store.folders.count, store.entries.count))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(localized("添加文件夹"), systemImage: "folder.badge.plus") {
                    chooseFolders()
                }
                Button {
                    Task { await store.refresh() }
                } label: {
                    Label(localized("刷新"), systemImage: "arrow.clockwise")
                }
                .disabled(store.isScanning || store.folders.isEmpty)
            }

            Picker(
                localized("内容类型"),
                selection: Binding(
                    get: { movieStore.mainBrowseSection },
                    set: { movieStore.setMainBrowseSection($0) }
                )
            ) {
                ForEach(MainBrowseSection.allCases) { section in
                    Text(section.title(language: movieStore.appLanguage)).tag(section)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if store.isScanning {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(scanDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
        }
        .padding()
    }

    private var filterBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                TextField(localized("搜索本地视频"), text: $searchText)
                    .textFieldStyle(.roundedBorder)
                Picker(localized("筛选"), selection: $statusFilter) {
                    ForEach(LocalLibraryStatusFilter.allCases) { option in
                        Text(option.title(language: movieStore.appLanguage))
                            .tag(option)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 110)
            }
            Picker(localized("内容类型"), selection: $categoryFilter) {
                ForEach(LocalLibraryCategoryFilter.allCases) { option in
                    Text(option.title(language: movieStore.appLanguage))
                        .tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    private var scanDescription: String {
        guard let progress = store.scanProgress else { return localized("正在扫描…") }
        return String(format: localized("正在扫描 %@ · %lld 个视频"), progress.displayName, progress.mediaFilesFound)
    }

    private var filteredEntries: [LocalLibraryEntry] {
        store.entries.filter { entry in
            guard categoryFilter.includes(entry) else { return false }
            guard statusFilter.includes(entry) else { return false }
            let haystack = [entry.signature.fileName, entry.metadata?.title ?? ""]
                .joined(separator: " ")
            return searchText.isEmpty || haystack.localizedCaseInsensitiveContains(searchText)
        }
        .sorted { lhs, rhs in
            lhs.metadata?.title ?? lhs.signature.fileName < rhs.metadata?.title ?? rhs.signature.fileName
        }
    }

    private func chooseFolders() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = localized("添加")
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            do {
                try store.addFolder(url: url)
            } catch {
                actionMessage = localized("无法添加文件夹。")
            }
        }
    }

    private func play(_ entry: LocalLibraryEntry) {
        guard entry.state == .available,
              let folder = store.folders.first(where: { $0.id == entry.folderID })
        else {
            actionMessage = localized("文件当前不可用。请重新定位文件后再播放。")
            return
        }
        Task {
            do {
                let resolved = try LocalLibraryFolderBookmark.resolve(folder.bookmarkData)
                defer { resolved.stopAccessing() }
                let fileURL = resolved.url.appendingPathComponent(entry.relativePath)
                guard FileManager.default.fileExists(atPath: fileURL.path) else {
                    actionMessage = localized("找不到文件。请重新定位文件。")
                    return
                }
                let result = await ExternalPlayerLauncher().open(fileURL: fileURL)
                if store.recordPlayback(result: result, entryID: entry.id) {
                    failedPlaybackPath = nil
                    actionMessage = nil
                } else {
                    failedPlaybackPath = fileURL.path
                    actionMessage = playbackFailureMessage(
                        result: result,
                        path: fileURL.path
                    )
                }
            } catch {
                failedPlaybackPath = nil
                actionMessage = localized("无法播放本地文件。")
            }
        }
    }

    private func findMatches(for entry: LocalLibraryEntry) {
        actionMessage = nil
        Task {
            do {
                let service = LocalLibraryMatchService(
                    client: TMDBClient(
                        token: movieStore.token,
                        language: movieStore.appLanguage.apiCode
                    )
                )
                let parsed = LocalLibraryFilenameParser.parse(
                    entry.signature.fileName
                )
                matchSession = LocalLibraryMatchSession(
                    entry: entry,
                    candidates: entry.contentCategory == .other
                        ? []
                        : try await service.search(for: entry),
                    initialQuery: entry.contentCategory == .other
                        ? ""
                        : (parsed.isTrustedTitle ? parsed.title : ""),
                    initialKind: entry.contentCategory == .television
                        ? .television
                        : .movie,
                    search: { query in
                        try await service.search(query: query)
                    }
                )
            } catch {
                actionMessage = localized("匹配影片失败。")
            }
        }
    }

    private func openDetails(for entry: LocalLibraryEntry) {
        guard entry.matchState == .confirmed,
              let metadata = entry.metadata,
              openExternalDetail(for: metadata)
        else {
            fileDetailEntry = entry
            return
        }
    }

    @discardableResult
    private func openExternalDetail(for metadata: LocalLibraryMetadata) -> Bool {
        movieStore.isShowingLocalLibrary = true
        switch metadata.kind {
        case .movie:
            guard let movie = LocalLibraryDetailBridge.movie(from: metadata) else {
                return false
            }
            movieStore.select(movie)
        case .television:
            guard let show = LocalLibraryDetailBridge.television(from: metadata) else {
                return false
            }
            movieStore.selectTV(show)
        }
        return true
    }

    private func relocate(_ entry: LocalLibraryEntry) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.movie]
        panel.prompt = localized("重新定位")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try store.reattach(entryID: entry.id, url: url)
        } catch {
            actionMessage = localLibraryErrorMessage(error)
        }
    }

    private func localized(_ key: String) -> String {
        LocalLibraryLocalization.string(key, language: movieStore.appLanguage)
    }

    private func playbackFailureMessage(
        result: ExternalPlayerLaunchResult,
        path: String
    ) -> String {
        guard case let .failed(failures) = result else {
            return String(format: localized("无法启动播放器。文件路径：%@"), path)
        }
        let reasons = failures.map { failure in
            let player: String
            switch failure.player {
            case .iina: player = "IINA"
            case .vlc: player = "VLC"
            case .system: player = localized("系统播放器")
            }
            let reasonKey: String
            switch failure.reason {
            case .notInstalled: reasonKey = "未安装"
            case .launchFailed: reasonKey = "启动失败"
            case .timedOut: reasonKey = "启动超时"
            case .systemRejected: reasonKey = "系统拒绝打开"
            }
            let reason = localized(reasonKey)
            if let detail = failure.detail, !detail.isEmpty {
                return "\(player)：\(reason)（\(detail)）"
            }
            return "\(player)：\(reason)"
        }.joined(separator: " · ")
        return String(
            format: localized("无法启动播放器。%@。文件路径：%@"),
            reasons,
            path
        )
    }

    private func localLibraryErrorMessage(_ error: Error) -> String {
        guard let storeError = error as? LocalLibraryStoreError else {
            return localized("无法重新定位文件。")
        }
        switch storeError {
        case .entryNotFound:
            return localized("片库项目已不存在。")
        case .signatureMismatch:
            return localized("所选文件与片库项目不匹配。")
        case .fileOutsideAuthorizedFolders:
            return localized("所选文件不在已授权的文件夹中。")
        case .notAFile:
            return localized("所选项目不是文件。")
        }
    }
}

private struct LocalLibraryMatchSession: Identifiable {
    let entry: LocalLibraryEntry
    let candidates: [LocalLibraryMatchCandidate]
    let initialQuery: String
    let initialKind: LocalLibraryMediaKind
    let search: (LocalLibraryMatchQuery) async throws -> [LocalLibraryMatchCandidate]

    var id: UUID { entry.id }
}

struct LocalLibraryMatchSearchState {
    private(set) var generation = 0
    private(set) var isSearching = false
    private(set) var hasSearched: Bool

    init(initialHasSearched: Bool = false) {
        hasSearched = initialHasSearched
    }

    mutating func begin() -> Int {
        generation += 1
        isSearching = true
        return generation
    }

    func isCurrent(_ requestGeneration: Int) -> Bool {
        requestGeneration == generation
    }

    @discardableResult
    mutating func finish(
        generation requestGeneration: Int,
        receivedResults: Bool
    ) -> Bool {
        guard isCurrent(requestGeneration) else { return false }
        isSearching = false
        if receivedResults {
            hasSearched = true
        }
        return true
    }

    mutating func reset() {
        generation += 1
        isSearching = false
        hasSearched = false
    }

    static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }
        if let urlError = error as? URLError,
           urlError.code == .cancelled {
            return true
        }
        let error = error as NSError
        return error.domain == NSURLErrorDomain &&
            error.code == NSURLErrorCancelled
    }
}

private struct LocalLibraryEntryRow: View {
    let entry: LocalLibraryEntry
    let language: AppLanguage
    let onPlay: () -> Void
    let onToggleWatched: () -> Void
    let onToggleWatchlist: () -> Void
    let onDetail: () -> Void
    let onMatch: () -> Void
    let onRelocate: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            poster
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.metadata?.title ?? entry.signature.fileName)
                    .font(.headline)
                    .lineLimit(1)
                Text(details)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Label(fileStateTitle, systemImage: fileStateIcon)
                    Label(matchStateTitle, systemImage: "sparkles")
                    if entry.isWatched { Label(localized("已看"), systemImage: "checkmark.circle") }
                    if entry.isInWatchlist { Label(localized("片单"), systemImage: "bookmark.fill") }
                }
                .font(.caption2)
                .foregroundStyle(
                    entry.state == .available ? Color.secondary : Color.orange
                )
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 5) {
                Button(localized("查看详情"), action: onDetail)
                    .buttonStyle(.borderedProminent)
                Button(localized("播放"), systemImage: "play.fill", action: onPlay)
                    .buttonStyle(.bordered)
                    .disabled(entry.state != .available)
                HStack(spacing: 4) {
                    Button(entry.isWatched ? localized("未看") : localized("已看"), action: onToggleWatched)
                    Button(entry.isInWatchlist ? localized("移除片单") : localized("加入片单"), action: onToggleWatchlist)
                }
                .buttonStyle(.borderless)
                HStack(spacing: 4) {
                    Button(localized("匹配"), action: onMatch).buttonStyle(.borderless)
                    if entry.state != .available {
                        Button(localized("重新定位文件"), action: onRelocate).buttonStyle(.borderless)
                    }
                }
            }
            .font(.caption)
        }
        .padding(10)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private var poster: some View {
        if let url = LocalLibraryPosterURL.resolve(entry.metadata?.posterPath) {
            AsyncImage(url: url) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Image(systemName: "film").font(.title2).foregroundStyle(.secondary)
            }
            .frame(width: 42, height: 62)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        } else {
            Image(systemName: "film")
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(width: 42, height: 62)
                .background(.tertiary, in: RoundedRectangle(cornerRadius: 6))
        }
    }

    private var details: String {
        let year = entry.metadata?.year ?? localized("未知年份")
        let kind: String
        switch entry.contentCategory {
        case .movie: kind = localized("电影")
        case .television: kind = localized("电视剧")
        case .other: kind = localized("其他视频")
        }
        return "\(year) · \(kind) · \(entry.signature.fileName)"
    }

    private var fileStateTitle: String {
        switch entry.state {
        case .available: return localized("文件可用")
        case .missing: return localized("重新定位文件")
        case .volumeUnavailable: return localized("存储卷未连接")
        }
    }

    private var fileStateIcon: String {
        entry.state == .available ? "checkmark.circle" : "exclamationmark.triangle"
    }

    private var matchStateTitle: String {
        switch entry.matchState {
        case .unmatched: return localized("待匹配")
        case .suggested: return localized("有建议")
        case .confirmed: return localized("已匹配")
        }
    }

    private func localized(_ key: String) -> String {
        LocalLibraryLocalization.string(key, language: language)
    }
}

struct LocalLibraryFileDetailView: View {
    let entry: LocalLibraryEntry
    let folder: LocalLibraryFolder?
    let language: AppLanguage
    let onMatch: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .help(localized("关闭详情"))

                Spacer()
                Text(localized("文件详情")).font(.headline)
                Spacer()
                Color.clear.frame(width: 20, height: 20)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    LabeledContent(localized("文件名")) {
                        selectableText(entry.signature.fileName)
                    }
                    LabeledContent(localized("路径")) {
                        selectableText(entry.relativePath)
                    }
                    LabeledContent(localized("文件夹")) {
                        selectableText(folder?.displayName ?? localized("未知"))
                    }
                    LabeledContent(localized("文件大小")) {
                        Text(fileSize)
                    }
                    LabeledContent(localized("观看状态")) {
                        Label(
                            entry.isWatched ? localized("已看") : localized("未看"),
                            systemImage: entry.isWatched
                                ? "checkmark.circle.fill"
                                : "circle"
                        )
                    }
                    LabeledContent(localized("片单状态")) {
                        Label(
                            entry.isInWatchlist ? localized("片单") : localized("加入片单"),
                            systemImage: entry.isInWatchlist
                                ? "bookmark.fill"
                                : "bookmark"
                        )
                    }

                    Divider()

                    Button(localized("匹配影片或电视剧"), action: onMatch)
                        .buttonStyle(.borderedProminent)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .padding()
            }
        }
        .frame(width: 480, height: 400)
    }

    private var fileSize: String {
        ByteCountFormatter.string(
            fromByteCount: entry.signature.byteCount,
            countStyle: .file
        )
    }

    private func selectableText(_ value: String) -> some View {
        Text(value)
            .lineLimit(2)
            .multilineTextAlignment(.trailing)
            .textSelection(.enabled)
    }

    private func localized(_ key: String) -> String {
        LocalLibraryLocalization.string(key, language: language)
    }
}

enum LocalLibraryPosterURL {
    static func resolve(_ storedValue: String?) -> URL? {
        guard let storedValue,
              !storedValue.isEmpty
        else { return nil }

        if let url = URL(string: storedValue), url.scheme != nil {
            return url
        }
        if storedValue.hasPrefix("/t/p/") {
            return URL(string: "https://image.tmdb.org\(storedValue)")
        }
        return URL(string: "https://image.tmdb.org/t/p/w154\(storedValue)")
    }
}

struct LocalLibraryEmptyState: View {
    struct Descriptor: Equatable {
        let title: String
        let description: String?
        let systemImage: String
    }

    static func library(language: AppLanguage) -> Descriptor {
        Descriptor(
            title: LocalLibraryLocalization.string("本地片库为空", language: language),
            description: LocalLibraryLocalization.string(
                "添加包含视频文件的文件夹后，使用刷新扫描目录。",
                language: language
            ),
            systemImage: "externaldrive.badge.plus"
        )
    }

    static func match(language: AppLanguage) -> Descriptor {
        Descriptor(
            title: LocalLibraryLocalization.string("没有找到候选项", language: language),
            description: nil,
            systemImage: "magnifyingglass"
        )
    }

    let state: Descriptor

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: state.systemImage)
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text(state.title)
                .font(.headline)
            if let description = state.description {
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.vertical, 24)
    }
}

private struct LocalLibraryMatchSheet: View {
    let session: LocalLibraryMatchSession
    let language: AppLanguage
    let onConfirm: (LocalLibraryMatchCandidate) -> Void
    let onDismiss: () -> Void

    @State private var queryText: String
    @State private var kind: LocalLibraryMediaKind
    @State private var candidates: [LocalLibraryMatchCandidate]
    @State private var searchState: LocalLibraryMatchSearchState
    @State private var searchError: String?
    @State private var searchTask: Task<Void, Never>?

    init(
        session: LocalLibraryMatchSession,
        language: AppLanguage,
        onConfirm: @escaping (LocalLibraryMatchCandidate) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.session = session
        self.language = language
        self.onConfirm = onConfirm
        self.onDismiss = onDismiss
        _queryText = State(initialValue: session.initialQuery)
        _kind = State(initialValue: session.initialKind)
        _candidates = State(initialValue: session.candidates)
        _searchState = State(
            initialValue: LocalLibraryMatchSearchState(
                initialHasSearched: session.entry.contentCategory != .other
            )
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Button(action: dismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .help(localized("关闭匹配"))

                Spacer()
                Text(localized("确认影片匹配")).font(.title3.bold())
                Spacer()
                Color.clear.frame(width: 20, height: 20)
            }
            Text(localized("最佳建议仅供参考；确认需手动操作，且当前条目的匹配不可撤销。"))
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                TextField(localized("搜索片名"), text: $queryText)
                    .textFieldStyle(.roundedBorder)
                Button {
                    clearSearch()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(localized("清除搜索"))
                Picker(localized("内容类型"), selection: $kind) {
                    Text(localized("电影")).tag(LocalLibraryMediaKind.movie)
                    Text(localized("电视剧")).tag(LocalLibraryMediaKind.television)
                }
                .pickerStyle(.menu)
                Button {
                    search()
                } label: {
                    if searchState.isSearching {
                        ProgressView().controlSize(.small)
                    } else {
                        Label(localized("搜索"), systemImage: "magnifyingglass")
                    }
                }
                .disabled(
                    queryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                        searchState.isSearching
                )
            }
            if let searchError {
                Text(searchError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            if candidates.isEmpty && searchState.isSearching {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if candidates.isEmpty {
                LocalLibraryEmptyState(
                    state: searchState.hasSearched
                        ? LocalLibraryEmptyState.match(language: language)
                        : LocalLibraryEmptyState.Descriptor(
                            title: localized("请输入片名"),
                            description: nil,
                            systemImage: "text.cursor"
                        )
                )
            } else {
                List {
                    ForEach(Array(candidates.enumerated()), id: \.element.id) { offset, candidate in
                        HStack(spacing: 12) {
                            if let posterURL = candidate.posterURL {
                                AsyncImage(url: posterURL) { image in
                                    image.resizable().scaledToFill()
                                } placeholder: {
                                    Image(systemName: "film")
                                        .foregroundStyle(.secondary)
                                }
                                .frame(width: 46, height: 68)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            } else {
                                Image(systemName: "film")
                                    .foregroundStyle(.secondary)
                                    .frame(width: 46, height: 68)
                            }
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Text(candidate.title).font(.headline)
                                    if offset == 0 {
                                        Text(localized("最佳建议"))
                                            .font(.caption2.bold())
                                            .foregroundStyle(.tint)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(.tint.opacity(0.12), in: Capsule())
                                    }
                                }
                                Text(
                                    candidate.year + " · " +
                                        (candidate.kind == .movie
                                            ? localized("电影")
                                            : localized("电视剧"))
                                )
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                if !candidate.genreIDs.isEmpty {
                                    Text(candidate.genreIDs.map {
                                        LocalLibraryGenreLocalization.title(
                                            id: $0,
                                            language: language
                                        )
                                    }.joined(separator: " · "))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Label(
                                    String(format: "%.1f / 10", candidate.voteAverage),
                                    systemImage: "star.fill"
                                )
                                .font(.caption2)
                                .foregroundStyle(.orange)
                                Text(
                                    localized("相似度") + " " +
                                        String(Int((candidate.confidence * 100).rounded())) + "%"
                                )
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(localized("确认匹配")) { onConfirm(candidate) }
                        }
                    }
                }
            }
            HStack {
                Spacer()
                Button(localized("跳过"), action: dismiss)
            }
        }
        .padding()
        .frame(width: 560, height: 500)
    }

    private func search() {
        let query = LocalLibraryMatchQuery(text: queryText, kind: kind)
        let previousTask = searchTask
        let generation = searchState.begin()
        previousTask?.cancel()
        searchTask = Task {
            do {
                let results = try await session.search(query)
                guard searchState.isCurrent(generation),
                      !Task.isCancelled
                else { return }
                guard searchState.finish(
                    generation: generation,
                    receivedResults: true
                ) else { return }
                candidates = results
                searchError = nil
            } catch {
                guard searchState.isCurrent(generation) else { return }
                guard !(Task.isCancelled ||
                    LocalLibraryMatchSearchState.isCancellation(error))
                else {
                    searchState.finish(
                        generation: generation,
                        receivedResults: false
                    )
                    return
                }
                guard searchState.finish(
                    generation: generation,
                    receivedResults: false
                ) else { return }
                searchError = localized("匹配影片失败。")
            }
        }
    }

    private func clearSearch() {
        searchState.reset()
        searchTask?.cancel()
        searchTask = nil
        queryText = ""
        candidates = []
        searchError = nil
    }

    private func dismiss() {
        searchState.reset()
        searchTask?.cancel()
        onDismiss()
    }

    private func localized(_ key: String) -> String {
        LocalLibraryLocalization.string(key, language: language)
    }
}
