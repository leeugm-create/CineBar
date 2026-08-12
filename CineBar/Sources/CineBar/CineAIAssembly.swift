import Foundation

/// CineAI 装配：把 `CineAIRAG` 的 DataSource 接到 MovieStore 真实的
/// TMDB 检索 / 观影进度 / 当前片库上。业务层只依赖这里的装配结果。
extension MovieStore {

    /// 生产一个已接入真实数据的 CineAIRAG。
    /// - Parameter provider: 具体模型 Provider（生产用 DeepSeek，测试用 Stub）。
    func makeCineAIRAG(provider: AIProvider) -> CineAIRAG {
        let selfRef = self
        return CineAIRAG(
            provider: provider,
            data: CineAIRAG.DataSource(
                fetchFacts: { query in
                    await selfRef.cineAIFetchFacts(query)
                },
                searchMovies: { query in
                    await selfRef.cineAISearchMovies(query)
                },
                spoilerContext: {
                    await selfRef.cineAISpoilerContext()
                }
            )
        )
    }

    /// 防剧透上下文：当前剧的进度 + 已看集的标题资料。
    /// 只取"进度以内"的集资料，之后的集不进上下文（防剧透核心）。
    private func cineAISpoilerContext() async -> String {
        guard let show = selectedTVShow,
              let progress = cineAIProgress.progress(for: show.id) else {
            return ""
        }
        var lines = [
            "剧名：《\(show.name)》，你已看到 \(progress.code)（第\(progress.seasonNumber)季第\(progress.episodeNumber)集）。"
        ]
        // 已加载的季/集：收集进度以内的集标题。
        for (season, episodes) in seasonEpisodes.sorted(by: { $0.key < $1.key }) {
            guard season < progress.seasonNumber ||
                    (season == progress.seasonNumber) else { break }
            let seen = episodes
                .filter { $0.episodeNumber <= (season == progress.seasonNumber ? progress.episodeNumber : 999_999) }
                .sorted { $0.episodeNumber < $1.episodeNumber }
            if !seen.isEmpty {
                let titles = seen.map { "S\(String(format: "%02d", season))E\(String(format: "%02d", $0.episodeNumber)) \($0.name)" }
                lines.append(titles.joined(separator: "\n"))
            }
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - 数据源实现

    /// 找片：用整句作检索词查 TMDB，取前若干返回标题+年份+评分+简介文本块。
    private func cineAISearchMovies(_ query: String) async -> String {
        guard hasToken else { return "" }
        let client = TMDBClient(token: token, language: appLanguage.apiCode)
        do {
            let results = try await client.search(query)
            let titles = results.prefix(8).map { m -> String in
                var line = "《\(m.title)》(\(m.year))"
                if m.voteAverage > 0 {
                    line += " 评分 \(String(format: "%.1f", m.voteAverage))"
                }
                if !m.overview.isEmpty {
                    line += " 简介：\(m.overview.prefix(120))"
                }
                return line
            }
            return titles.joined(separator: "\n")
        } catch {
            return ""
        }
    }

    /// 影视问答/推荐：查 TMDB 标题/剧集，返回其元数据文本块。
    private func cineAIFetchFacts(_ query: String) async -> String {
        guard hasToken else { return "" }
        let client = TMDBClient(token: token, language: appLanguage.apiCode)
        var lines: [String] = []
        if let movie = (try? await client.search(query))?.first {
            lines.append("电影《\(movie.title)》(\(movie.year))")
            if movie.voteAverage > 0 {
                lines.append("评分 \(String(format: "%.1f", movie.voteAverage)) / \(movie.voteCount)人")
            }
            if !movie.overview.isEmpty {
                lines.append("简介：\(movie.overview)")
            }
        }
        if let show = (try? await client.searchTV(query))?.first {
            lines.append("剧集《\(show.name)》(\(show.year))")
            if show.voteAverage > 0 {
                lines.append("评分 \(String(format: "%.1f", show.voteAverage))")
            }
            if !show.overview.isEmpty {
                lines.append("简介：\(show.overview)")
            }
        }
        return lines.joined(separator: "\n\n")
    }
}
