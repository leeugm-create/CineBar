import AVKit
import AppKit
import SwiftUI

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

    var body: some View {
        ZStack {
            Color.black
            MoovieVideoView(
                url: url,
                rate: $playbackRate,
                paused: paused,
                onTick: { currentTime = $0 }
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
    let onTick: (Double) -> Void

    final class VideoNSView: NSView {
        let playerView = AVPlayerView()
        let player = AVPlayer()
        private var loadedURL: URL?
        private var observer: Any?
        private var onTick: ((Double) -> Void)?
        private var lastTick: Double = -1

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
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
                if abs(seconds - (self?.lastTick ?? -1)) > 0.15 {
                    self?.lastTick = seconds
                    self?.onTick?(seconds)
                }
            }
        }

        required init?(coder: NSCoder) {
            nil
        }

        func setOnTick(_ closure: @escaping (Double) -> Void) {
            onTick = closure
        }

        func play(_ url: URL, rate: Double, paused: Bool) {
            if loadedURL != url {
                loadedURL = url
                player.pause()
                player.replaceCurrentItem(with: AVPlayerItem(url: url))
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
        let view = VideoNSView()
        view.setOnTick(onTick)
        view.play(url, rate: rate, paused: paused)
        return view
    }

    func updateNSView(_ nsView: VideoNSView, context: Context) {
        nsView.setOnTick(onTick)
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

    func show(
        url: URL,
        title: String,
        danmaku: [DanmakuItem],
        mode: MooviePlaybackMode
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
                mode: mode
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
                danmakuVisible: $danmakuVisible
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
                    Button {
                        MooviePlaybackController.shared
                            .closeAndRestoreMainPanel()
                    } label: {
                        Label("关闭播放", systemImage: "xmark.circle.fill")
                    }
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
