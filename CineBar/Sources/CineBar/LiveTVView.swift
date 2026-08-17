import AppKit
import SwiftUI

/// 电视直播面板（排版对标 zip0.com/tv 的 watch-tv 页）：
/// 左栏 = 播放器舞台（16:9 圆角黑底，加载/失败遮罩）+ 「当前频道」摘要 + 当前分组频道列表；
/// 右栏 = 「切换分组」侧边栏（共 N 个分组，各含频道数），点击即切组并自动播放该组首个频道。
/// 频道数据来自 GitHub 开源源 best-fan/iptv-sources（经 worker /api/iptv 中转）。
/// 直播流是标准 HLS（m3u8 live），复用 MooviePlayerView 的 AVPlayer（原生支持直播）。
struct LiveTVView: View {
    let store: MovieStore

    @State private var groups: [CineBarIPTVClient.IPTVGroup] = []
    @State private var selectedGroup: String?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var playingChannel: CineBarIPTVClient.Channel?
    @State private var playbackStatus: MooviePlaybackStatus = .loading
    @State private var currentTime: Double = 0
    @State private var playbackRate: Double = 1
    @State private var danmakuVisible = true
    @State private var inlinePaused = false

    private var activeGroup: CineBarIPTVClient.IPTVGroup? {
        guard let selectedGroup else { return groups.first }
        return groups.first { $0.name == selectedGroup } ?? groups.first
    }

    var body: some View {
        VStack(spacing: 0) {
            headerRow
            Divider()
            content
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            if groups.isEmpty, !isLoading {
                Task { await load() }
            }
        }
    }

    // MARK: - 顶栏

    private var headerRow: some View {
        HStack(spacing: 10) {
            // 明确返回入口：直播界面顶栏固定「返回」按钮（520 宽主面板 6 个分区 tab 过挤，
            // 用户可能找不到顶部 tab，导致"进了直播回不去"——Build 128 修复）。
            Button {
                store.setMainBrowseSection(.movies)
            } label: {
                Label("返回", systemImage: "chevron.left")
            }
            .help("返回电影 / 电视剧")
            Text("电视直播")
                .font(.headline)
            if isLoading {
                ProgressView().controlSize(.small)
            }
            Spacer()
            if let playingChannel {
                Text("正在收看：\(playingChannel.name)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Button {
                Task { await load() }
            } label: {
                Label("刷新", systemImage: "arrow.clockwise")
            }
            .disabled(isLoading)
            .help("重新拉取直播源（GitHub 每日更新）")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - 内容区

    @ViewBuilder
    private var content: some View {
        if isLoading && groups.isEmpty {
            VStack(spacing: 10) {
                ProgressView()
                Text("正在载入电视台数据…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage, groups.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "antenna.radiowaves.left.and.right.slash")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text("暂无电视直播数据")
                    .font(.headline)
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
                Button("重试") {
                    Task { await load() }
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            HStack(spacing: 12) {
                watchMain
                groupSidebar
            }
            .padding(12)
        }
    }

    // MARK: - 左栏：播放器 + 频道列表

    private var watchMain: some View {
        VStack(alignment: .leading, spacing: 10) {
            playerStage
            if let playingChannel {
                nowPlayingSummary(channel: playingChannel)
            }
            channelSection
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// 播放器舞台：16:9 黑底圆角，带加载/失败遮罩（对标 zip0 player-shell / player-state）。
    private var playerStage: some View {
        ZStack {
            if let playingChannel, let url = playingChannel.streamURL {
                MooviePlayerView(
                    url: url,
                    danmaku: [],
                    currentTime: $currentTime,
                    playbackRate: $playbackRate,
                    danmakuVisible: $danmakuVisible,
                    paused: inlinePaused,
                    registerInline: true,
                    onStatus: { status in
                        switch status {
                        case .loading:
                            playbackStatus = .loading
                        case .readyToPlay:
                            playbackStatus = .readyToPlay
                        case .failed:
                            playbackStatus = .failed("")
                        }
                    },
                    isLive: true
                )
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "tv")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("选择一个频道开始收看")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            if playbackStatus == .loading, playingChannel != nil {
                ZStack {
                    Color.black.opacity(0.55)
                    VStack(spacing: 10) {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.orange)
                        Text("正在连接直播信号")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.85))
                    }
                }
                .allowsHitTesting(false)
            }

            if case .failed = playbackStatus, playingChannel != nil {
                VStack(spacing: 8) {
                    Image(systemName: "wifi.exclamationmark")
                        .font(.title2)
                        .foregroundStyle(.orange)
                    Text("该电视台直连线路暂未响应")
                        .font(.callout.bold())
                        .foregroundStyle(.white)
                    Text("请在右侧列表中选择其它频道")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.65))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.opacity(0.78))
            }
        }
        .aspectRatio(16.0 / 9.0, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.25), radius: 12, y: 6)
    }

    /// 「当前频道」摘要（对标 zip0 now-playing）。
    private func nowPlayingSummary(channel: CineBarIPTVClient.Channel) -> some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("当前频道")
                    .font(.caption2.bold())
                    .foregroundStyle(.orange)
                Text(channel.name)
                    .font(.title3.bold())
                    .lineLimit(1)
                Text("\(channel.group) · 全天候 24 小时直播信号")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            if let url = channel.streamURL {
                Button {
                    MooviePlaybackController.shared.show(
                        url: url,
                        title: channel.name,
                        danmaku: [],
                        mode: .floating,
                        isLive: true
                    )
                } label: {
                    Label("浮窗", systemImage: "pip.enter")
                }
                .controlSize(.small)
                .help("在独立浮窗中播放，可继续浏览频道")
                Button {
                    playingChannel = nil
                    playbackStatus = .loading
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("停止播放")
            }
        }
        .padding(.horizontal, 4)
    }

    /// 频道列表（对标 zip0 related-videos + tv-station-grid）。
    private var channelSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let activeGroup {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(activeGroup.name) 频道列表")
                        .font(.headline)
                    Spacer()
                    Text("共计 \(activeGroup.channels.count) 个频道")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 150), spacing: 10)],
                        spacing: 10
                    ) {
                        ForEach(activeGroup.channels) { channel in
                            channelCard(channel)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// 频道卡片（对标 zip0 tv-station-card：logo + 台名 + 分组 · 直播源，当前频道高亮）。
    private func channelCard(_ channel: CineBarIPTVClient.Channel) -> some View {
        let isPlaying = playingChannel?.id == channel.id
        return Button {
            playingChannel = channel
            playbackStatus = .loading
        } label: {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.primary.opacity(0.06))
                    if let logo = channel.logo,
                       let encoded = logo.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                       let url = URL(string: "https://cinebar.cc/api/iptv/logo?url=\(encoded)") {
                        AsyncImage(url: url) { image in
                            image.resizable().scaledToFit()
                        } placeholder: {
                            Image(systemName: "tv")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                        }
                        .padding(4)
                    } else {
                        Image(systemName: "tv")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 36, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 2) {
                    Text(channel.name)
                        .font(.caption.bold())
                        .lineLimit(1)
                    Text("\(channel.group) · 直播源")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isPlaying
                        ? Color.orange.opacity(0.12)
                        : Color.primary.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        isPlaying
                            ? Color.orange.opacity(0.6)
                            : Color.clear,
                        lineWidth: 1
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("播放 \(channel.name)")
    }

    // MARK: - 右栏：切换分组侧边栏（对标 zip0 source-panel--watch）

    private var groupSidebar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "globe.asia.australia")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("切换分组")
                        .font(.caption.bold())
                    Text("共计 \(groups.count) 个分组")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(12)

            Divider()

            ScrollView {
                VStack(spacing: 4) {
                    ForEach(groups) { group in
                        groupOption(group)
                    }
                }
                .padding(6)
            }
        }
        .frame(width: 150)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.primary.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private func groupOption(_ group: CineBarIPTVClient.IPTVGroup) -> some View {
        let isActive = activeGroup?.id == group.id
        return Button {
            switchGroup(group)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(group.name)
                    .font(.caption.bold())
                    .lineLimit(1)
                Text("\(group.channels.count) 个电视台")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isActive
                        ? Color.orange.opacity(0.12)
                        : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("切换到 \(group.name)")
    }

    // MARK: - 数据与播放

    private func switchGroup(_ group: CineBarIPTVClient.IPTVGroup) {
        selectedGroup = group.name
        // 对标 zip0：切换分组后自动播放该组第一个频道。
        if let first = group.channels.first {
            playingChannel = first
            playbackStatus = .loading
        }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let fetched = try await CineBarIPTVClient.fetchGroups()
            groups = fetched
            if selectedGroup == nil
                || !fetched.contains(where: { $0.name == selectedGroup }) {
                selectedGroup = fetched.first?.name
            }
            // 对标 zip0：进入即自动播放第一个频道。
            if let playingChannel,
               !fetched.contains(where: { $0.channels.contains(playingChannel) }) {
                self.playingChannel = nil
            }
            if playingChannel == nil, let first = fetched.first?.channels.first {
                playingChannel = first
                playbackStatus = .loading
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
