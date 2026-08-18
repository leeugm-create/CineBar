import AVKit
import AppKit
import SwiftUI

/// 在线播放器的加载/失败状态（供 UI 显示加载遮罩与错误提示）。
enum MooviePlaybackStatus: Equatable {
    case loading
    case readyToPlay
    case failed(String)
}

/// 程序内在线正片播放器：AVPlayerView（自带播放/暂停、进度、音量、全屏控制条）
/// 之上叠加弹幕层，支持倍速与弹幕开关。详情页内嵌与独立窗口共用。
struct MooviePlayerView: View {
    let url: URL
    let danmaku: [DanmakuItem]
    @Binding var currentTime: Double
    @Binding var playbackRate: Double
    @Binding var danmakuVisible: Bool
    /// 是否暂停（打开独立播放窗口时暂停内嵌播放器，避免双路播放）。
    var paused: Bool = false
    /// 是否把播放器注册到控制器供窗口键盘快捷键（空格/方向键）使用。
    /// 仅独立播放窗口设为 true。
    var registerPlayer: Bool = false
    /// 是否把播放器注册为"内嵌播放"（主面板内联播放），供主面板键盘快捷键使用。
    var registerInline: Bool = false
    /// 播放状态回调（加载中/可播放/失败），直播流 UI 用它显示遮罩。默认 nil 不回调。
    var onStatus: ((MooviePlaybackStatus) -> Void)? = nil
    /// 是否为直播流（HLS live）。直播流用纯 AVPlayerLayer 渲染，避免 AVPlayerView
    /// 对无时长直播流的 SwiftUI 绑定崩溃（Build 125 崩溃报告）。
    var isLive: Bool = false
    /// 观影记录续播：>0 时起播后 seek 到该秒数（2026-08-18 新增）。
    var resumeFrom: Double = 0
    /// 视频时长就绪回调（观影记录需要时长计算进度条/剩余时间）。
    var onDuration: ((Double) -> Void)? = nil

    var body: some View {
        ZStack {
            Color.black
            MoovieVideoView(
                url: url,
                rate: $playbackRate,
                paused: paused,
                registerPlayer: registerPlayer,
                registerInline: registerInline,
                onTick: { currentTime = $0 },
                onStatus: onStatus,
                isLive: isLive,
                resumeFrom: resumeFrom,
                onDuration: onDuration
            )
            if danmakuVisible, !danmaku.isEmpty {
                DanmakuOverlay(items: danmaku, currentTime: currentTime)
                    .allowsHitTesting(false)
            }
        }
    }
}

/// AVPlayerView 包装：周期上报播放时间，倍速变化时同步播放速率。
struct MoovieVideoView: NSViewRepresentable {
    let url: URL
    @Binding var rate: Double
    var paused: Bool = false
    var registerPlayer: Bool = false
    var registerInline: Bool = false
    let onTick: (Double) -> Void
    var onStatus: ((MooviePlaybackStatus) -> Void)? = nil
    var isLive: Bool = false
    var resumeFrom: Double = 0
    var onDuration: ((Double) -> Void)? = nil

    final class VideoNSView: NSView {
        let playerView = AVPlayerView()
        let player = AVPlayer()

        private var loadedURL: URL?
        private var observer: Any?
        private var itemStatusObserver: NSKeyValueObservation?
        private var timeControlObserver: NSKeyValueObservation?
        private var stallWorkItem: DispatchWorkItem?
        private var onTick: ((Double) -> Void)?
        private var onStatus: ((MooviePlaybackStatus) -> Void)?
        private var resumeFrom: Double = 0
        private var didSeekResume = false
        private var onDuration: ((Double) -> Void)?
        private var didReportDuration = false
        private var videoCheckWork: DispatchWorkItem?
        private var playerLayer: CALayer?
        private var didReportLiveStart = false
        private var lastTick: Double = -1
        /// 直播流等待起播超过该时长视为信号失败（针对 HLS live 卡死但 item 状态仍是 ready 的情况）。
        private static let stallTimeout: TimeInterval = 12

        init(frame frameRect: NSRect, isLive: Bool, resumeFrom: Double = 0, onDuration: ((Double) -> Void)? = nil) {
            super.init(frame: frameRect)
            self.resumeFrom = resumeFrom
            self.onDuration = onDuration
            // 统一用 AVPlayerView（自带控制条/全屏按钮/正常渲染）。Build 125 曾因
            // "无时长直播流 + SwiftUI 绑定"崩溃改为纯 AVPlayerLayer，导致直播无控制条、
            // 无法全屏，且 h265 央视流黑屏有声（2026-08-18 反馈）。
            // 崩溃真正源头是 onTick 每 0.2s 把直播时间写进 SwiftUI binding——isLive 时
            // 跳过 onTick 更新即可规避，AVPlayerView 渲染与交互恢复。
            playerView.translatesAutoresizingMaskIntoConstraints = false
            playerView.player = player
            playerView.controlsStyle = .inline
            playerView.videoGravity = .resizeAspect
            playerView.showsFullScreenToggleButton = true
            playerView.allowsPictureInPicturePlayback = true
            addSubview(playerView)
            NSLayoutConstraint.activate([
                playerView.leadingAnchor.constraint(equalTo: leadingAnchor),
                playerView.trailingAnchor.constraint(equalTo: trailingAnchor),
                playerView.topAnchor.constraint(equalTo: topAnchor),
                playerView.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])
            let interval = CMTime(seconds: 0.2, preferredTimescale: 600)
            observer = player.addPeriodicTimeObserver(
                forInterval: interval,
                queue: .main
            ) { [weak self] time in
                let seconds = time.seconds
                guard seconds.isFinite, seconds >= 0 else { return }
                // isLive 直播流无 duration，频繁写 binding 曾触发 AVPlayerView 崩溃（Build 125）；
                // 直播也不展示进度，直接跳过。但时间走起来必须报告 readyToPlay：
                // 否则 h265 直播的 timeControlStatus 可能停在 waiting，LiveTV 的加载遮罩
                // 一直盖着画面 = 用户看到"黑屏有声"（2026-08-18 实测 presentationSize 正常）。
                if isLive {
                    if seconds > 0.5 {
                        if let self, !self.didReportLiveStart {
                            self.didReportLiveStart = true
                            self.reportStatus(.readyToPlay)
                        }
                    }
                    return
                }
                if abs(seconds - (self?.lastTick ?? -1)) > 0.15 {
                    self?.lastTick = seconds
                    self?.onTick?(seconds)
                }
            }
        }

        required init?(coder: NSCoder) {
            nil
        }

        deinit {
            // 视图销毁时显式停止播放（2026-08-18 反馈"返回后直播仍出声"：
            // 不能依赖 AVPlayer 随释放自动停止的时序，显式暂停并清空播放项）。
            player.pause()
            player.replaceCurrentItem(with: nil)
            playerLayer?.removeFromSuperlayer()
        }

        func setOnTick(_ closure: @escaping (Double) -> Void) {
            onTick = closure
        }

        func setOnStatus(_ closure: ((MooviePlaybackStatus) -> Void)?) {
            onStatus = closure
        }

        private func reportStatus(_ status: MooviePlaybackStatus) {
            onStatus?(status)
        }

        /// 黑屏检测（2026-08-18 央视 h265 黑屏有声反馈）：播放 8 秒后
        /// 有音频轨但无视频画面（presentationSize 为 0）→ 明确提示换台，
        /// 不再无声黑屏干等。换台/重播会重新检测。
        private func armVideoCheck() {
            videoCheckWork?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                let size = self.player.currentItem?.presentationSize ?? .zero
                let hasAudio = (self.player.currentItem?.tracks.contains {
                    $0.assetTrack?.mediaType == .audio
                }) ?? false
                if hasAudio && (size.width == 0 || size.height == 0) {
                    self.reportStatus(.failed("视频流解码失败（H.265 源在部分设备黑屏），请换台"))
                }
            }
            videoCheckWork = work
            DispatchQueue.main.asyncAfter(
                deadline: .now() + 8,
                execute: work
            )
        }

        private func armStallTimer() {
            stallWorkItem?.cancel()
            let work = DispatchWorkItem { [weak self] in
                self?.reportStatus(.failed("该电视台直连线路暂未响应，请换一个频道"))
            }
            stallWorkItem = work
            DispatchQueue.main.asyncAfter(
                deadline: .now() + Self.stallTimeout,
                execute: work
            )
        }

        func play(_ url: URL, rate: Double, paused: Bool) {
            if loadedURL != url {
                loadedURL = url
                player.pause()
                itemStatusObserver?.invalidate()
                timeControlObserver?.invalidate()
                didReportLiveStart = false
                // 注意：不要对 HLS 直播流设置 videoComposition（AVMutableVideoComposition），
                // 实测 Build 135 会闪退（2026-08-18 用户反馈点击电视台即崩）。
                // 黑屏有声问题改走换源方向，不再尝试色彩转换 workaround。
                let item = AVPlayerItem(url: url)
                player.replaceCurrentItem(with: item)

                reportStatus(.loading)
                armStallTimer()
                armVideoCheck()

                itemStatusObserver = item.observe(\.status, options: [.new]) {
                    [weak self] item, _ in
                    DispatchQueue.main.async {
                        switch item.status {
                        case .failed:
                            let message = item.error?.localizedDescription
                                ?? "该电视台直连线路暂未响应，请换一个频道"
                            self?.reportStatus(.failed(message))
                        case .readyToPlay:
                            // 观影记录续播：就绪后 seek 到上次进度（仅一次，容差归零避免跳帧）。
                            if let self, self.resumeFrom > 0, !self.didSeekResume {
                                self.didSeekResume = true
                                let target = CMTime(seconds: self.resumeFrom, preferredTimescale: 600)
                                self.player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
                            }
                            // 时长就绪回调（观影记录进度条用）。
                            if let self, !self.didReportDuration {
                                let dur = item.duration.seconds
                                if dur.isFinite, dur > 0 {
                                    self.didReportDuration = true
                                    self.onDuration?(dur)
                                }
                            }
                            break // 起播与否由 timeControlStatus 决定
                        case .unknown:
                            break
                        @unknown default:
                            break
                        }
                    }
                }

                timeControlObserver = player.observe(\.timeControlStatus, options: [.new]) {
                    [weak self] player, _ in
                    DispatchQueue.main.async {
                        switch player.timeControlStatus {
                        case .playing:
                            self?.stallWorkItem?.cancel()
                            self?.reportStatus(.readyToPlay)
                        case .waitingToPlayAtSpecifiedRate:
                            self?.reportStatus(.loading)
                        case .paused:
                            break
                        @unknown default:
                            break
                        }
                    }
                }

                if !paused {
                    player.rate = Float(rate)
                }
            } else if paused {
                player.pause()
            } else if player.rate == 0 {
                player.rate = Float(rate)
            }
        }

        func setRate(_ rate: Double, paused: Bool) {
            guard player.currentItem != nil else { return }
            if paused {
                player.pause()
            } else if player.rate == 0 {
                player.rate = Float(rate)
            }
        }
    }

    func makeNSView(context: Context) -> VideoNSView {
        let view = VideoNSView(frame: .zero, isLive: isLive, resumeFrom: resumeFrom, onDuration: onDuration)
        view.setOnTick(onTick)
        view.setOnStatus(onStatus)
        view.play(url, rate: rate, paused: paused)
        Task { @MainActor in
            if registerPlayer {
                MooviePlaybackController.shared.registerKeyboardPlayer(view.player)
            }
            if registerInline {
                MooviePlaybackController.shared.registerInlinePlayer(view.player)
            }
        }
        return view
    }

    func updateNSView(_ nsView: VideoNSView, context: Context) {
        nsView.setOnTick(onTick)
        nsView.setOnStatus(onStatus)
        nsView.play(url, rate: rate, paused: paused)
        nsView.setRate(rate, paused: paused)
    }
}

/// 弹幕渲染层：按当前播放时间显示滚动/顶部/底部弹幕。
struct DanmakuOverlay: View {
    let items: [DanmakuItem]
    let currentTime: Double

    private static let scrollDuration: Double = 11
    private static let topDisplayDuration: Double = 5

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let active = activeItems(in: geo.size)
            ZStack {
                ForEach(Array(active.scroll.enumerated()), id: \.offset) { _, item in
                    let elapsed = currentTime - item.time
                    let progress = elapsed / Self.scrollDuration
                    Text(item.text)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(hexColor(item.color))
                        .shadow(color: .black.opacity(0.9), radius: 1)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 4))
                        .position(
                            x: width * (1 - progress),
                            y: laneY(for: item, in: geo.size)
                        )
                }
                ForEach(Array(active.top.enumerated()), id: \.offset) { _, item in
                    Text(item.text)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(hexColor(item.color))
                        .shadow(color: .black.opacity(0.9), radius: 1)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 4))
                        .position(
                            x: width / 2,
                            y: geo.size.height * 0.22
                        )
                }
                ForEach(Array(active.bottom.enumerated()), id: \.offset) { _, item in
                    Text(item.text)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(hexColor(item.color))
                        .shadow(color: .black.opacity(0.9), radius: 1)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 4))
                        .position(
                            x: width / 2,
                            y: geo.size.height * 0.78
                        )
                }
            }
        }
        .clipped()
    }

    private func activeItems(in size: CGSize) -> (
        scroll: [DanmakuItem],
        top: [DanmakuItem],
        bottom: [DanmakuItem]
    ) {
        var scroll: [DanmakuItem] = []
        var top: [DanmakuItem] = []
        var bottom: [DanmakuItem] = []
        for item in items {
            switch item.mode {
            case 1:
                if currentTime >= item.time,
                   currentTime <= item.time + Self.topDisplayDuration {
                    top.append(item)
                }
            case 2:
                if currentTime >= item.time,
                   currentTime <= item.time + Self.topDisplayDuration {
                    bottom.append(item)
                }
            default:
                if currentTime >= item.time,
                   currentTime <= item.time + Self.scrollDuration {
                    scroll.append(item)
                }
            }
        }
        return (scroll, top, bottom)
    }

    private func laneY(for item: DanmakuItem, in size: CGSize) -> CGFloat {
        let laneHeight: CGFloat = 32
        let lanes = max(Int((size.height * 0.6) / laneHeight), 4)
        let bucket = abs(Int(item.text.hashValue)) % lanes
        return laneHeight * CGFloat(bucket) + laneHeight / 2 + 24
    }

    private func hexColor(_ hex: String?) -> Color {
        guard let hex, !hex.isEmpty else { return .white }
        let value = hex.trimmingCharacters(
            in: CharacterSet(charactersIn: "#")
        )
        guard value.count == 6, let int = Int(value, radix: 16) else {
            return .white
        }
        return Color(
            red: Double((int >> 16) & 0xFF) / 255,
            green: Double((int >> 8) & 0xFF) / 255,
            blue: Double(int & 0xFF) / 255
        )
    }
}

/// Moovie 独立播放窗口（浮窗/全屏），Esc 或关闭后恢复主面板。
final class MooviePlayerWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    /// 播放快捷键：空格播放/暂停、左右快退/快进 15 秒。
    /// AVPlayerView 内建键盘在内嵌 SwiftUI/NSHostingView 里拿不到焦点，
    /// 这里在窗口层统一处理，保证独立播放窗口按键始终生效。
    override func keyDown(with event: NSEvent) {
        if [49, 123, 124].contains(event.keyCode) {
            Task { @MainActor in
                MooviePlaybackController.shared.handleKey(from: event)
            }
            return
        }
        super.keyDown(with: event)
    }

    override func cancelOperation(_ sender: Any?) {
        // 只有自己可见时响应 ESC，避免事件沿响应链误关主面板。
        guard isVisible else { return }
        // 延迟到按键事件处理结束后再关窗：cancelOperation 正位于 keyDown
        // 的事件分发栈内，同步 close 会释放窗口对象造成 use-after-free
        // （autorelease pool pop 时崩溃，详见 Build 54 崩溃报告）。
        DispatchQueue.main.async {
            MooviePlaybackController.shared.closeAndRestoreMainPanel()
        }
    }
}

enum MooviePlaybackMode {
    case floating
    case fullScreen
}

/// 独立播放控制器：浮窗/全屏播放正片，与预告片窗口互斥，关闭恢复主面板。
@MainActor
final class MooviePlaybackController: NSObject, NSWindowDelegate {
    static let shared = MooviePlaybackController()

    private var playerWindow: MooviePlayerWindow?
    private var currentMode: MooviePlaybackMode?
    private var previousPresentationOptions: NSApplication.PresentationOptions?
    private var isSwitchingOrClosing = false

    /// 当前独立播放窗口所用播放器（用于空格/左右方向键快捷键）。
    private weak var keyboardPlayer: AVPlayer?
    /// 最近注册的内嵌播放器（主面板详情页内联播放）。
    private weak var inlinePlayer: AVPlayer?

    func registerKeyboardPlayer(_ player: AVPlayer) {
        keyboardPlayer = player
    }

    func registerInlinePlayer(_ player: AVPlayer) {
        inlinePlayer = player
    }

    func clearInlinePlayer() {
        inlinePlayer = nil
    }

    /// 主面板是否存在活动的内嵌播放器（决定是否拦截空格/方向键）。
    var hasInlinePlayer: Bool {
        (inlinePlayer?.currentItem) != nil
    }

    /// 播放快捷键：空格播放/暂停、左右快退/快进 15 秒。
    /// 优先作用于最近的内嵌播放器，其次独立播放窗口播放器。
    func handleKey(from event: NSEvent) {
        let players = [inlinePlayer, keyboardPlayer]
            .compactMap { $0 }
            .filter { $0.currentItem != nil }
        guard let player = players.first else { return }
        switch event.keyCode {
        case 49: // 空格
            if player.rate != 0 {
                player.pause()
            } else {
                player.play()
            }
        case 123: // 左方向键：快退 15 秒
            seek(delta: -15, on: player)
        case 124: // 右方向键：快进 15 秒
            seek(delta: 15, on: player)
        default:
            break
        }
    }

    private func seek(delta: Double, on player: AVPlayer) {
        let current = player.currentTime().seconds
        guard current.isFinite else { return }
        let target = CMTime(seconds: max(0, current + delta), preferredTimescale: 600)
        player.seek(to: target)
    }

    func show(
        url: URL,
        title: String,
        danmaku: [DanmakuItem],
        mode: MooviePlaybackMode,
        isLive: Bool = false,
        resumeFrom: Double = 0,
        onDuration: ((Double) -> Void)? = nil
    ) {
        close()
        NotificationCenter.default.post(
            name: .cineBarMediaPlaybackDidChange,
            object: true
        )
        NotificationCenter.default.post(
            name: .cineBarPanelWillHide,
            object: nil
        )
        NSApplication.shared.windows
            .first { $0 is CineBarPanel }?
            .orderOut(nil)

        let pointer = NSEvent.mouseLocation
        let screen = NSScreen.screens.first {
            NSMouseInRect(pointer, $0.frame, false)
        } ?? NSScreen.main
        guard let screen else { return }

        let window: MooviePlayerWindow
        switch mode {
        case .floating:
            let width = min(960, screen.visibleFrame.width * 0.82)
            let height = width * 9 / 16
            let frame = NSRect(
                x: screen.visibleFrame.midX - width / 2,
                y: screen.visibleFrame.midY - height / 2,
                width: width,
                height: height
            )
            window = MooviePlayerWindow(
                contentRect: frame,
                styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.minSize = NSSize(width: 540, height: 304)
            window.level = .floating
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
        case .fullScreen:
            window = MooviePlayerWindow(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            // 先清残留再保存：防止重复进入全屏时 previous 被污染，
            // 导致退出全屏后 Dock/菜单栏不恢复（2026-08-18 反馈的 Dock 隐藏 bug）。
            restorePresentationOptions()
            previousPresentationOptions = NSApplication.shared.presentationOptions
            NSApplication.shared.presentationOptions = [
                .autoHideDock,
                .autoHideMenuBar
            ]
            window.level = .mainMenu
            window.collectionBehavior = [
                .canJoinAllSpaces,
                .fullScreenAuxiliary
            ]
        }

        window.backgroundColor = .black
        window.isOpaque = true
        // 程序化创建的窗口必须交给 ARC 全权管理，
        // 否则 close() 时系统按旧式内存管理再 release 一次，
        // 与 ARC 双重释放导致崩溃（ESC 退出全屏时必现）。
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(
            rootView: MooviePlayerWindowView(
                url: url,
                title: title,
                danmaku: danmaku,
                mode: mode,
                isLive: isLive,
                resumeFrom: resumeFrom,
                onDuration: onDuration
            )
        )
        playerWindow = window
        currentMode = mode
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func close() {
        guard let window = playerWindow else { return }
        isSwitchingOrClosing = true
        playerWindow = nil
        currentMode = nil
        window.delegate = nil
        window.orderOut(nil)
        window.close()
        restorePresentationOptions()
        NotificationCenter.default.post(
            name: .cineBarMediaPlaybackDidChange,
            object: false
        )
        isSwitchingOrClosing = false
    }

    func closeAndRestoreMainPanel() {
        close()
        NotificationCenter.default.post(
            name: .cineBarShowMainPanel,
            object: nil
        )
    }

    func windowWillClose(_ notification: Notification) {
        guard !isSwitchingOrClosing else { return }
        playerWindow = nil
        currentMode = nil
        restorePresentationOptions()
        NotificationCenter.default.post(
            name: .cineBarMediaPlaybackDidChange,
            object: false
        )
        NotificationCenter.default.post(
            name: .cineBarShowMainPanel,
            object: nil
        )
    }

    private func restorePresentationOptions() {
        if let previousPresentationOptions {
            NSApplication.shared.presentationOptions = previousPresentationOptions
            self.previousPresentationOptions = nil
        }
    }
}

/// 独立窗口播放内容：黑底 + 播放器 + 顶部标题/切换/关闭。
struct MooviePlayerWindowView: View {
    let url: URL
    let title: String
    let danmaku: [DanmakuItem]
    let mode: MooviePlaybackMode
    var isLive: Bool = false
    var resumeFrom: Double = 0
    var onDuration: ((Double) -> Void)? = nil

    @State private var currentTime: Double = 0
    @State private var playbackRate: Double = 1
    @State private var danmakuVisible: Bool = true

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()
            MooviePlayerView(
                url: url,
                danmaku: danmaku,
                currentTime: $currentTime,
                playbackRate: $playbackRate,
                danmakuVisible: $danmakuVisible,
                registerPlayer: true,
                isLive: isLive,
                resumeFrom: resumeFrom,
                onDuration: onDuration
            )

            HStack(spacing: 10) {
                Text(title)
                    .font(.callout.bold())
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Spacer()
                if !danmaku.isEmpty {
                    Toggle(isOn: $danmakuVisible) {
                        Label("弹幕", systemImage: "captions.bubble")
                    }
                    .toggleStyle(.button)
                    .controlSize(.small)
                }
                Menu {
                    ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { rate in
                        Button("\(rateText(rate))") {
                            playbackRate = rate
                        }
                    }
                } label: {
                    Label("倍速 \(rateText(playbackRate))", systemImage: "speedometer")
                }
                .menuStyle(.borderlessButton)
                .controlSize(.small)
                if mode == .fullScreen {
                    Button {
                        MooviePlaybackController.shared.show(
                            url: url,
                            title: title,
                            danmaku: danmaku,
                            mode: .floating
                        )
                    } label: {
                        Label("切换浮窗", systemImage: "pip.exit")
                    }
                } else {
                    Button {
                        MooviePlaybackController.shared.show(
                            url: url,
                            title: title,
                            danmaku: danmaku,
                            mode: .fullScreen,
                            isLive: isLive
                        )
                    } label: {
                        Label("全屏", systemImage: "arrow.up.left.and.arrow.down.right")
                    }
                }
                // 浮窗与全屏都提供显式返回按钮：此前只有全屏有，
                // 直播浮窗（isLive 无控制条）无返回入口，用户被困在播放界面。
                Button {
                    MooviePlaybackController.shared
                        .closeAndRestoreMainPanel()
                } label: {
                    Label("关闭播放", systemImage: "xmark.circle.fill")
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .padding(10)
            .background(
                LinearGradient(
                    colors: [.black.opacity(0.78), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
    }

    private func rateText(_ rate: Double) -> String {
        rate == 1 ? "1x" : "\(rate) x".replacingOccurrences(of: ".0 ", with: " ")
    }
}
