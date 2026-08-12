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
                searchSeries: { query in
                    await selfRef.cineAISearchSeries(query)
                },
                recommendMovies: {
                    await selfRef.cineAIRecommendMovies()
                },
                recommendSeries: {
                    await selfRef.cineAIRecommendSeries()
                },
                spoilerContext: {
                    await selfRef.cineAISpoilerContext()
                }
            )
        )
    }

    /// 找连续剧：按检索词查 TMDB 剧集，返回候选文本。
    private func cineAISearchSeries(_ query: String) async -> String {
        guard hasToken else { return "" }
        let client = TMDBClient(token: token, language: appLanguage.apiCode)
        do {
            let shows = try await client.searchTV(query)
            let lines = shows.prefix(8).map { s -> String in
                var line = "《\(s.name)》(\(s.year))"
                if s.voteAverage > 0 { line += " 评分 \(String(format: "%.1f", s.voteAverage))" }
                if !s.overview.isEmpty { line += " 简介：\(s.overview.prefix(120))" }
                return line
            }
            return lines.joined(separator: "\n")
        } catch {
            return ""
        }
    }

    /// 推荐连续剧：按用户电影类型偏好取 TDMB 剧集高分候选。
    private func cineAIRecommendSeries() async -> String {
        guard hasToken else { return "" }
        let client = TMDBClient(token: token, language: appLanguage.apiCode)
        do {
            let result = try await client.discoverTV(
                startYear: nil,
                endYear: nil,
                genreID: preferredMovieGenreIDs.first,
                originCountry: nil,
                sortMode: .rating,
                page: 1
            )
            let ms = Array(result.shows.sorted { $0.voteAverage > $1.voteAverage }.prefix(10))
            let lines = ms.map { s -> String in
                var line = "《\(s.name)》(\(s.year))"
                if s.voteAverage > 0 { line += " 评分 \(String(format: "%.1f", s.voteAverage))" }
                if !s.overview.isEmpty { line += " 简介：\(s.overview.prefix(90))" }
                return line
            }
            return lines.joined(separator: "\n")
        } catch {
            return ""
        }
    }

    /// 推荐候选：按用户电影偏好取高分片，且只保留磁力库里有资源的（否则不推荐空影片）。
    private func cineAIRecommendMovies() async -> String {
        guard hasToken else { return "" }
        let client = TMDBClient(token: token, language: appLanguage.apiCode)
        do {
            let page = try await client.discover(
                startYear: nil,
                endYear: nil,
                genreIDs: Array(preferredMovieGenreIDs),
                keywordQueries: [],
                originCountry: nil,
                sortMode: .rating,
                page: 1
            )
            // 推荐候选 = TMDB 高分全集（范围大），磁力库可下载的排前面（优先可下载），
            // 磁力库没有的也保留（可在线播放 Moovie），避免"只搜片库资源太少"。
            let magnet = Hao6vMagnetStore.shared
            let playable = page.movies
                .map { (movie: $0, hasMagnet: magnet.contains(title: $0.title)) }
                .sorted {
                    if $0.hasMagnet != $1.hasMagnet { return $0.hasMagnet }
                    return $0.movie.voteAverage > $1.movie.voteAverage
                }
                .prefix(12)
            let lines = playable.map { e in
                var line = "《\(e.movie.title)》(\(e.movie.year))"
                if e.movie.voteAverage > 0 { line += " 评分 \(String(format: "%.1f", e.movie.voteAverage))" }
                if !e.movie.overview.isEmpty { line += " 简介：\(e.movie.overview.prefix(90))" }
                if !e.hasMagnet { line += "（可在线播放）" }
                return line
            }
            return lines.joined(separator: "\n")
        } catch {
            return ""
        }
    }

    /// 当前"进行中的剧"：优先用户正在查看的剧；否则取观影进度里最近看过的剧。
    /// 用于防剧透的上下文与硬拦截，不依赖用户恰好停在某剧详情页。
    private func cineAICurrentProgress() -> (showID: Int, name: String?, progress: ShownProgress)? {
        if let show = selectedTVShow,
           let p = cineAIProgress.progress(for: show.id) {
            return (show.id, show.name, p)
        }
        // 回退：进度记录里最近更新的剧
        let recent = cineAIProgress.allProgressSortedByRecent().first
        if let recent {
            return (recent.seriesID, nil, recent.progress)
        }
        return nil
    }

    /// 防剧透上下文：当前进行中剧的进度 + 已看集的标题资料。
    /// 只取"进度以内"的集资料，之后的集不进上下文（防剧透核心）。
    private func cineAISpoilerContext() async -> String {
        guard let current = cineAICurrentProgress() else { return "" }
        let showName = current.name ?? "这部剧"
        let progress = current.progress
        var lines = [
            "剧名：《\(showName)》，你已看到 \(progress.code)（第\(progress.seasonNumber)季第\(progress.episodeNumber)集）。"
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

    // MARK: - 点击片名进详情

    /// 按片名查找 TMDB 并进入详情页（CineAI 回答里可点击的片名调用）。
    func selectMovieByTitle(_ title: String) {
        let query = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        guard hasToken else { return }
        Task {
            do {
                let results = try await TMDBClient(
                    token: token,
                    language: appLanguage.apiCode
                ).search(query)
                let normalized = DoubanRatingClient.normalize(query)
                let match = results.first {
                    let t = DoubanRatingClient.normalize($0.title)
                    return t == normalized || t.contains(normalized) || normalized.contains(t)
                } ?? results.first
                guard let movie = match else {
                    await MainActor.run { message = "未找到《\(title)》" }
                    return
                }
                await MainActor.run { select(movie) }
            } catch {
                await MainActor.run { message = "查找《\(title)》失败" }
            }
        }
    }

    /// 防剧透问题的本地硬拦截：结局类问题 + 该剧未看完 → 本地直接挡回（不进模型、不耗 token）。
    /// 返回非 nil 表示要拦截（文案给用户）；nil 放行交给 RAG。
    func spoilerShield(for question: String) -> String? {
        guard appLanguage.isChinese else { return nil }
        guard let current = cineAICurrentProgress() else { return nil }
        let progress = current.progress
        // 仅当"进行中的剧"恰好是当前查看的剧时用 tvDetails 判断；回退剧未知季数则保守未看完。
        var hasSeenFinal = false
        if current.showID == selectedTVShow?.id {
            let lastSeason = tvDetails?.numberOfSeasons ?? 0
            let lastSeasonEpisodes = tvDetails?.seasons
                .first(where: { $0.seasonNumber == lastSeason })?.episodeCount ?? 0
            hasSeenFinal =
                progress.seasonNumber > lastSeason ||
                (progress.seasonNumber == lastSeason &&
                 progress.episodeNumber >= lastSeasonEpisodes)
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
