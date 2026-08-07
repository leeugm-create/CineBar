import Foundation
import AVFoundation
import AVKit
import SwiftUI
import AppKit

/// 豆瓣预告片条目（来自豆瓣 rexxar JSON 接口，含 mp4 直链）。
struct DoubanTrailerItem: Identifiable, Hashable {
    let id: Int
    let title: String
    let thumbnailURL: URL?
    let durationText: String
    let playbackURL: URL?
}

/// 豆瓣预告片客户端：从 m.douban.com 的 rexxar JSON 接口读取预告片列表，
/// 每项自带可直连播放的 mp4 地址（vtN.doubanio.com，国内可正常播放）。
/// 非官方、静默降级。
struct DoubanTrailerClient {
    var session: URLSession = .shared

    private static let userAgent =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) "
        + "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 "
        + "Mobile/15E148 Safari/604.1"

    private func fetchData(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(
            "https://m.douban.com/movie/subject/",
            forHTTPHeaderField: "Referer"
        )
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse,
              http.statusCode == 200 else {
            throw CineBarError.server("豆瓣返回异常状态码")
        }
        return data
    }

    /// 抓取某部影视（豆瓣 subjectID）的预告片列表；无预告返回空数组。
    func trailers(subjectID: Int) async throws -> [DoubanTrailerItem] {
        guard subjectID > 0,
              let url = URL(
                  string: "https://m.douban.com/rexxar/api/v2/movie/"
                      + "\(subjectID)?for_mobile=1"
              ) else { return [] }
        let data = try await fetchData(url)
        guard let json = try? JSONSerialization.jsonObject(with: data)
                as? [String: Any],
              let list = json["trailers"] as? [[String: Any]] else {
            return []
        }
        return list.compactMap { Self.parseTrailer($0) }
    }

    private static func parseTrailer(_ dict: [String: Any])
        -> DoubanTrailerItem? {
        guard let idText = dict["id"] as? String,
              let id = Int(idText), id > 0 else { return nil }

        let title = dict["title"] as? String
            ?? (dict["desc"] as? String)
            ?? "预告片"

        let thumbnailURL: URL?
        if let cover = dict["cover_url"] as? String,
           cover.hasPrefix("https://") {
            thumbnailURL = URL(string: cover)
        } else {
            thumbnailURL = nil
        }

        let duration = dict["runtime"] as? String ?? ""

        let playbackURL: URL?
        if let raw = dict["video_url"] as? String,
           raw.hasPrefix("https://"),
           let url = URL(string: raw) {
            playbackURL = url
        } else {
            playbackURL = nil
        }

        return DoubanTrailerItem(
            id: id,
            title: title,
            thumbnailURL: thumbnailURL,
            durationText: duration,
            playbackURL: playbackURL
        )
    }
}

/// 在 SwiftUI 里用 AVPlayerView 播放豆瓣 mp4 直链，自带播放/暂停、
/// 音量、进度、全屏控制条。
struct DoubanTrailerPlayerView: NSViewRepresentable {
    let url: URL

    final class PlayerNSView: NSView {
        let playerView = AVPlayerView()
        let player = AVPlayer()
        private var loadedURL: URL?

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
        }

        required init?(coder: NSCoder) {
            nil
        }

        func play(_ url: URL) {
            guard loadedURL != url else { return }
            loadedURL = url
            player.pause()
            player.replaceCurrentItem(with: AVPlayerItem(url: url))
            player.play()
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