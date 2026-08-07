import Foundation
import AVFoundation
import SwiftUI
import AppKit

/// 豆瓣预告片条目（来自 m.douban.com 移动版详情页的 trailer 卡表）。
struct DoubanTrailerItem: Identifiable, Hashable {
    let id: Int
    let title: String
    let thumbnailURL: URL?
    let durationText: String
}

/// 豆瓣预告片客户端：从 m.douban.com/movie/subject/{id}/ 解析预告片卡表，
/// 从 m.douban.com/movie/trailer/{id}/ 解析 mp4 播放直链。非官方、静默降级。
struct DoubanTrailerClient {
    var session: URLSession = .shared

    private static let userAgent =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) "
        + "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 "
        + "Mobile/15E148 Safari/604.1"

    private func fetchPage(_ url: URL) async throws -> String {
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse,
              http.statusCode == 200 else {
            throw CineBarError.server("豆瓣返回异常状态码")
        }
        return String(data: data, encoding: .utf8) ?? ""
    }

    /// 抓取某部影视（豆瓣 subjectID）的预告片列表；无预告返回空数组。
    func trailers(subjectID: Int) async throws -> [DoubanTrailerItem] {
        guard subjectID > 0,
              let url = URL(
                  string: "https://m.douban.com/movie/subject/\(subjectID)/"
              ) else { return [] }
        let html = try await fetchPage(url)

        // 移动版详情页中预告片区块：
        //   <li ...>
        //     <a href="/other/videoTN4" ...>  // 示例结构
        //   </li>
        // 实际结构（已验证）：
        //   <li class="video video-trailer" data-src="...封面...">
        //     <a href="/movie/trailer/318533"><span><img ... alt="标题..."></span></a>
        //     <div class="time">01:33</div>
        var items: [DoubanTrailerItem] = []
        var cursor = html.startIndex
        while let blockStart = html.range(
            of: "class=\"video video-trailer\"",
            range: cursor..<html.endIndex
        ) {
            let tailStart = blockStart.upperBound
            let blockEnd = html.range(
                of: "</li>",
                range: tailStart..<html.endIndex
            )?.lowerBound ?? html.endIndex
            let block = String(html[tailStart..<blockEnd])
            if let item = Self.parseTrailerBlock(block) {
                items.append(item)
            }
            cursor = blockEnd < html.endIndex
                ? html.index(blockEnd, offsetBy: 4)
                : html.endIndex
        }
        return items
    }

    /// 解析影片预告片播放页，得到 mp4 直链。
    func playbackURL(trailerID: Int) async throws -> URL? {
        guard trailerID > 0,
              let url = URL(
                  string: "https://m.douban.com/movie/trailer/\(trailerID)/"
              ) else { return nil }
        let html = try await fetchPage(url)
        let marker = "<source src=\""
        guard let start = html.range(of: marker) else { return nil }
        guard let end = html.range(
            of: "\"",
            range: start.upperBound..<html.endIndex
        ) else { return nil }
        let raw = String(html[start.upperBound..<end.lowerBound])
        guard raw.hasPrefix("https://"), !raw.isEmpty else { return nil }
        return URL(string: raw)
    }

    private static func parseTrailerBlock(_ block: String) -> DoubanTrailerItem? {
        // 预告片 ID：href="/movie/trailer/数字"
        var id = 0
        if let hrefRange = block.range(of: "/movie/trailer/") {
            var digits = ""
            for ch in block[hrefRange.upperBound...] {
                guard ch.isNumber else { break }
                digits.append(ch)
            }
            id = Int(digits) ?? 0
        }
        guard id > 0 else { return nil }

        // 封面：data-src="https://img1.doubanio.com/img/trailer/medium/..."
        let thumbnail: URL?
        if let dataSrc = extractQuoted(before: "data-src=\"", in: block),
           dataSrc.hasPrefix("https://") {
            thumbnail = URL(string: dataSrc)
        } else {
            thumbnail = nil
        }

        // 标题：alt="..."
        let title = extractQuoted(before: "alt=\"", in: block) ?? "预告片"

        // 时长：class="time">00:33</div>
        let duration = extractQuoted(
            before: "class=\"time\">",
            after: "<",
            in: block
        ) ?? ""

        return DoubanTrailerItem(
            id: id,
            title: title,
            thumbnailURL: thumbnail,
            durationText: duration
        )
    }

    private static func extractQuoted(
        before marker: String,
        in text: String
    ) -> String? {
        guard let start = text.range(of: marker) else { return nil }
        guard let end = text.range(
            of: "\"",
            range: start.upperBound..<text.endIndex
        ) else { return nil }
        let value = String(text[start.upperBound..<end.lowerBound])
        return value.isEmpty ? nil : value
    }

    private static func extractQuoted(
        before marker: String,
        after terminator: Character,
        in text: String
    ) -> String? {
        guard let start = text.range(of: marker) else { return nil }
        var value = ""
        for ch in text[start.upperBound...] {
            if ch == terminator { break }
            value.append(ch)
        }
        return value.isEmpty ? nil : value
    }
}

/// 在 SwiftUI 里用 AVPlayer 播放豆瓣 mp4 直链。
struct DoubanTrailerPlayerView: NSViewRepresentable {
    let url: URL

    final class PlayerNSView: NSView {
        private let player = AVPlayer()
        private var playerLayer: AVPlayerLayer?

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            configurLayer()
        }

        required init?(coder: NSCoder) {
            super.init(coder: coder)
            configurLayer()
        }

        private func configurLayer() {
            wantsLayer = true
            let layer = AVPlayerLayer(player: player)
            layer.videoGravity = .resizeAspect
            layer.frame = bounds
            layer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
            self.layer = layer
            playerLayer = layer
        }

        func play(_ url: URL) {
            player.pause()
            player.replaceCurrentItem(with: AVPlayerItem(url: url))
            player.rate = 1
        }

        override func layout() {
            super.layout()
            playerLayer?.frame = bounds
        }
    }

    func makeNSView(context: Context) -> PlayerNSView {
        let view = PlayerNSView()
        view.play(url)
        return view
    }

    func updateNSView(_ nsView: PlayerNSView, context: Context) {
        nsView.play(url)
    }
}