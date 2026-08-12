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

    // MARK: - spoilerSafe 本地硬拦截

    /// 防剧透问题的本地硬拦截：结局类问题 + 该剧未看完 → 本地直接挡回（不进模型、不耗 token）。
    /// 返回非 nil 表示要拦截（文案给用户）；nil 放行交给 RAG。
    func spoilerShield(for question: String) -> String? {
        guard appLanguage.isChinese else { return nil }
        guard selectedTVShow != nil else { return nil }
        let lastSeason = tvDetails?.numberOfSeasons ?? 0
        let lastSeasonEpisodes = tvDetails?.seasons
            .first(where: { $0.seasonNumber == lastSeason })?.episodeCount ?? 0
        let progress = cineAIProgress.progress(for: selectedTVShow!.id)
        let hasSeenFinal: Bool
        if let progress {
            hasSeenFinal =
                progress.seasonNumber > lastSeason ||
                (progress.seasonNumber == lastSeason &&
                 progress.episodeNumber >= lastSeasonEpisodes)
        } else {
            // 没有进度记录：视为没看完，结局类问题保守拦截。
            hasSeenFinal = false
        }
        return CineAISpoilerShield.blockReason(
            question: question,
            hasSeenFinal: hasSeenFinal
        )
    }

    /// 找片：先把自然语言拆成结构化查询（类型/年份/评分/关键词），
    /// 能拆出结构化条件就走 TMDB discover；拆不出就回退整句标题搜索。
    private func cineAISearchMovies(_ query: String) async -> String {
        guard hasToken else { return "" }
        let client = TMDBClient(token: token, language: appLanguage.apiCode)
        let parsed = CineMovieQueryParser.parse(query)
        do {
            var ms: [Movie]
            if !parsed.genreIDs.isEmpty || parsed.keyword != nil {
                let page = try await client.discover(
                    startYear: parsed.year.map { $0 - 2 },
                    endYear: parsed.year,
                    genreIDs: parsed.genreIDs,
                    keywordQueries: parsed.keyword.map { [$0] } ?? [],
                    originCountry: nil,
                    sortMode: parsed.wantObscure ? .rating : .popularity,
                    page: 1
                )
                ms = page.movies
                if let mv = parsed.minVote {
                    ms = ms.filter { $0.voteAverage >= mv }
                }
                if parsed.wantObscure {
                    ms = ms.sorted { $0.voteAverage > $1.voteAverage }
                }
                ms = Array(ms.prefix(8))
            } else {
                ms = try await client.search(query)
            }
            let lines = ms.prefix(8).map { m -> String in
                var line = "《\(m.title)》(\(m.year))"
                if m.voteAverage > 0 {
                    line += " 评分 \(String(format: "%.1f", m.voteAverage))"
                }
                if !m.overview.isEmpty {
                    line += " 简介：\(m.overview.prefix(120))"
                }
                return line
            }
            return lines.joined(separator: "\n")
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
