import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct LocalLibraryView: View {
    @ObservedObject var store: LocalLibraryStore
    @ObservedObject var movieStore: MovieStore

    @State private var searchText = ""
    @State private var filter = LocalLibraryFilter.all
    @State private var actionMessage: String?
    @State private var matchSession: LocalLibraryMatchSession?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            filterBar
            if let message = actionMessage ?? store.message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.bottom, 6)
            }
            ScrollView {
                LazyVStack(spacing: 8) {
                    if filteredEntries.isEmpty {
                        ContentUnavailableView(
                            "本地片库为空",
                            systemImage: "externaldrive.badge.plus",
                            description: Text("添加包含视频文件的文件夹后，使用刷新扫描目录。")
                        )
                        .padding(.top, 48)
                    } else {
                        ForEach(filteredEntries) { entry in
                            LocalLibraryEntryRow(
                                entry: entry,
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
                onConfirm: { candidate in
                    store.updateMetadata(
                        entryID: session.entry.id,
                        metadata: candidate.metadata
                    )
                    matchSession = nil
                },
                onDismiss: { matchSession = nil }
            )
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Label("本地片库", systemImage: "externaldrive.fill")
                        .font(.title3.bold())
                    Text("已添加 \(store.folders.count) 个目录 · \(store.entries.count) 个视频")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("添加文件夹", systemImage: "folder.badge.plus") {
                    chooseFolders()
                }
                Button {
                    Task { await store.refresh() }
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
                .disabled(store.isScanning || store.folders.isEmpty)
            }

            Picker(
                "内容类型",
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
        HStack(spacing: 8) {
            TextField(String(localized: "搜索本地视频"), text: $searchText)
                .textFieldStyle(.roundedBorder)
            Picker("筛选", selection: $filter) {
                ForEach(LocalLibraryFilter.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 110)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    private var scanDescription: String {
        guard let progress = store.scanProgress else { return String(localized: "正在扫描…") }
        return "正在扫描 \(progress.displayName) · \(progress.mediaFilesFound) 个视频"
    }

    private var filteredEntries: [LocalLibraryEntry] {
        store.entries.filter { entry in
            guard filter.includes(entry) else { return false }
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
        panel.prompt = "添加"
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            do {
                try store.addFolder(url: url)
            } catch {
                actionMessage = error.localizedDescription
            }
        }
    }

    private func play(_ entry: LocalLibraryEntry) {
        guard entry.state == .available,
              let folder = store.folders.first(where: { $0.id == entry.folderID })
        else {
            actionMessage = "文件当前不可用。请重新定位文件后再播放。"
            return
        }
        Task {
            do {
                let resolved = try LocalLibraryFolderBookmark.resolve(folder.bookmarkData)
                defer { resolved.stopAccessing() }
                let fileURL = resolved.url.appendingPathComponent(entry.relativePath)
                guard FileManager.default.fileExists(atPath: fileURL.path) else {
                    actionMessage = "找不到文件。请重新定位文件。"
                    return
                }
                store.markOpened(entryID: entry.id)
                if !(await ExternalPlayerLauncher().open(fileURL: fileURL)) {
                    actionMessage = "无法启动播放器打开 \(entry.signature.fileName)。"
                }
            } catch {
                actionMessage = error.localizedDescription
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
                matchSession = LocalLibraryMatchSession(
                    entry: entry,
                    candidates: try await service.search(for: entry)
                )
            } catch {
                actionMessage = "匹配失败：\(error.localizedDescription)"
            }
        }
    }

    private func relocate(_ entry: LocalLibraryEntry) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.movie]
        panel.prompt = "重新定位"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try store.reattach(entryID: entry.id, url: url)
        } catch {
            actionMessage = error.localizedDescription
        }
    }
}

private enum LocalLibraryFilter: CaseIterable, Identifiable {
    case all, unwatched, unmatched, unavailable

    var id: Self { self }

    var title: String {
        switch self {
        case .all: return String(localized: "全部")
        case .unwatched: return String(localized: "未看")
        case .unmatched: return String(localized: "待匹配")
        case .unavailable: return String(localized: "文件不可用")
        }
    }

    func includes(_ entry: LocalLibraryEntry) -> Bool {
        switch self {
        case .all: return true
        case .unwatched: return !entry.isWatched
        case .unmatched: return entry.matchState != .confirmed
        case .unavailable: return entry.state != .available
        }
    }
}

private struct LocalLibraryMatchSession: Identifiable {
    let entry: LocalLibraryEntry
    let candidates: [LocalLibraryMatchCandidate]

    var id: UUID { entry.id }
}

private struct LocalLibraryEntryRow: View {
    let entry: LocalLibraryEntry
    let onPlay: () -> Void
    let onToggleWatched: () -> Void
    let onToggleWatchlist: () -> Void
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
                    if entry.isWatched { Label("已看", systemImage: "checkmark.circle") }
                    if entry.isInWatchlist { Label("片单", systemImage: "bookmark.fill") }
                }
                .font(.caption2)
                .foregroundStyle(
                    entry.state == .available ? Color.secondary : Color.orange
                )
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 5) {
                Button("播放", systemImage: "play.fill", action: onPlay)
                    .buttonStyle(.borderedProminent)
                    .disabled(entry.state != .available)
                HStack(spacing: 4) {
                    Button(entry.isWatched ? "未看" : "已看", action: onToggleWatched)
                    Button(entry.isInWatchlist ? "移除片单" : "加入片单", action: onToggleWatchlist)
                }
                .buttonStyle(.borderless)
                HStack(spacing: 4) {
                    Button("匹配", action: onMatch).buttonStyle(.borderless)
                    if entry.state != .available {
                        Button("重新定位文件", action: onRelocate).buttonStyle(.borderless)
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
        let year = entry.metadata?.year ?? String(localized: "未知年份")
        let kind = entry.metadata?.kind == .television
            ? String(localized: "电视剧")
            : String(localized: "电影")
        return "\(year) · \(kind) · \(entry.signature.fileName)"
    }

    private var fileStateTitle: String {
        switch entry.state {
        case .available: return String(localized: "文件可用")
        case .missing: return String(localized: "重新定位文件")
        case .volumeUnavailable: return String(localized: "存储卷未连接")
        }
    }

    private var fileStateIcon: String {
        entry.state == .available ? "checkmark.circle" : "exclamationmark.triangle"
    }

    private var matchStateTitle: String {
        switch entry.matchState {
        case .unmatched: return String(localized: "待匹配")
        case .suggested: return String(localized: "有建议")
        case .confirmed: return String(localized: "已匹配")
        }
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

private struct LocalLibraryMatchSheet: View {
    let session: LocalLibraryMatchSession
    let onConfirm: (LocalLibraryMatchCandidate) -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("确认影片匹配").font(.title3.bold())
            Text("选择后将覆盖当前匹配信息；跳过不会影响本地文件或播放。")
                .font(.caption)
                .foregroundStyle(.secondary)
            if session.candidates.isEmpty {
                ContentUnavailableView("没有找到候选项", systemImage: "magnifyingglass")
            } else {
                List(session.candidates) { candidate in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(candidate.title).font(.headline)
                            Text(
                                candidate.year + " · " +
                                    (candidate.kind == .movie ? "电影" : "电视剧")
                            )
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("确认匹配") { onConfirm(candidate) }
                    }
                }
            }
            HStack {
                Spacer()
                Button("跳过", action: onDismiss)
            }
        }
        .padding()
        .frame(width: 460, height: 360)
    }
}
