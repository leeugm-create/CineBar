import Foundation

/// 多维媒体分类决策。
///
/// 方案C：文件名强特征优先；文件名无法判定时，才用物理特征（时长、大小）兜底。
enum LocalLibraryMediaDecision: Hashable {
    case movie
    case television
    case other
}

/// 判定等级：用于决定是否值得为某个文件读取时长。
enum LocalLibraryFilenameConfidence {
    case decisive   // 文件名已给出明确结论，无需读时长
    case ambiguous  // 文件名无法判定，需要物理特征兜底
}

/// 视频物理特征。duration 为 nil 表示未知（读取失败/尚未读取）。
struct LocalLibraryPhysicalSignal: Hashable {
    var byteCount: Int64
    var durationSeconds: Double?
}

enum LocalLibraryClassifier {

    /// 影片兜底底线：时长（秒）。
    static let filmMinimumDurationSeconds: Double = 3600

    // MARK: - 对外入口

    /// 依据文件名 + 物理特征给出最终分类。
    static func classify(
        fileName: String,
        physical: LocalLibraryPhysicalSignal
    ) -> LocalLibraryMediaDecision {
        let parsed = LocalLibraryFilenameParser.parse(fileName)
        let fromFilename = classify(fromFilename: parsed, stem: filenameStem(fileName))
        switch fromFilename {
        case let .decision(decision, decisive: true):
            return decision
        default:
            // 文件名无法判定 → 物理兜底
            guard let duration = physical.durationSeconds else {
                return .other // 无时长信息，宁可归 other 也不猜影片
            }
            return physicalDecision(duration: duration)
        }
    }

    /// 仅依据文件名判断。空串/占位返回 .other。
    static func classify(fromFilename: String) -> LocalLibraryMediaDecision {
        guard !fromFilename.isEmpty else { return .other }
        let parsed = LocalLibraryFilenameParser.parse(fromFilename)
        let stem = filenameStem(fromFilename)
        if case let .decision(decision, decisive: true) = classify(fromFilename: parsed, stem: stem) {
            return decision
        }
        return .other
    }

    /// 该文件名是否需要读取时长来做物理兜底。
    static func confidence(fromFilename: String) -> LocalLibraryFilenameConfidence {
        let parsed = LocalLibraryFilenameParser.parse(fromFilename)
        let stem = filenameStem(fromFilename)
        if case .decision(_, decisive: true) = classify(fromFilename: parsed, stem: stem) {
            return .decisive
        }
        return .ambiguous
    }

    // MARK: - 决策实现

    private enum FilenameSignal {
        case decision(LocalLibraryMediaDecision, decisive: Bool)
        case uncertain
    }

    private static func classify(
        fromFilename parsed: LocalLibraryParsedFilename,
        stem: String
    ) -> FilenameSignal {
        let lower = stem.lowercased()

        // 1. 强电视剧标记
        if hasStrongTelevisionSignal(lower) {
            return .decision(.television, decisive: true)
        }

        // 2. 强个人/平台/设备/随机串特征 → other
        if hasStrongPersonalSignal(lower) {
            return .decision(.other, decisive: true)
        }

        // 3. 强电影发行标记 → movie
        if hasStrongMovieSignal(lower, parsed: parsed) {
            return .decision(.movie, decisive: true)
        }

        // 4. 纯数字标题（时间戳/日期/随机数字）→ other
        if isNumericOnlyTitle(lower) {
            return .decision(.other, decisive: true)
        }

        // 5. 占位/截屏通用名 → other
        if isPlaceholderTitle(lower) {
            return .decision(.other, decisive: true)
        }

        // 6. 中文占比高的内容标题（用户生成、无明显发行标记）→ other
        if isLikelyUserGeneratedChineseTitle(lower) {
            return .decision(.other, decisive: true)
        }

        // 7. 明文可信标题兜底（仅限拉丁文字，避免把中文昵称/通用名误当影片）
        if isReadableFilmTitle(lower) {
            let decision: LocalLibraryMediaDecision = parsed.category == .television
                ? .television
                : .movie
            return .decision(decision, decisive: true)
        }

        return .uncertain
    }

    /// 物理特征兜底：时长 ≥1 小时归影片（统一归电影），否则 other。
    private static func physicalDecision(duration: Double) -> LocalLibraryMediaDecision {
        guard duration >= filmMinimumDurationSeconds else { return .other }
        return .movie
    }

    // MARK: - 强信号判断

    private static func hasStrongTelevisionSignal(_ stem: String) -> Bool {
        if reMatch(stem, "(?i)(?:s[0-9]{1,2}\\s*e[0-9]{1,3}(?:\\s*e[0-9]{1,3})?|season[ .]*[0-9]{1,2}|完成季.*(?:season|季)|全集)") {
            return true
        }
        // 连播多集标记 S01E01-E10
        return reMatch(stem, "(?i)(?:s[0-9]{1,2}e[0-9]{1,3}-\\s*e[0-9]{1,3})")
    }

    private static func hasStrongMovieSignal(_ stem: String, parsed: LocalLibraryParsedFilename) -> Bool {
        // 分辨率 + 发行编码（"1080p.BluRay"、"2160p.WEB-DL"、"BD中英双字"）
        if reMatch(stem, "(?i)(?:2160p|1080p|720p|4k|8k)(?:\\s*[. _-]+\\s*(?:blu[ ._-]?ray|web[ ._-]?dl|web[ ._-]?rip|bdrip|bd|hdrip|x264|x265|h\\.?26[45]|hevc|remux))") {
            return true
        }
        // 编码器 + 剧组标记
        if reMatch(stem, "(?i)(?:x264|h\\.?264|x265|h\\.?265|hevc|blu[ ._-]?ray|remux)(?:[ ._-]??)(?:dts|dd5|ffgt|sparks|rarbg|frame)") {
            return true
        }
        // 中文发行特征：xx.1080p.BD中英双字 / [最新电影 www.xxx.com]
        if parsed.year != nil,
           reMatch(stem, "(?i)(?:\\[最新电影|www\\.|中英双字|蓝光|bluray)") {
            return true
        }
        return false
    }

    private static func hasStrongPersonalSignal(_ stem: String) -> Bool {
        // 设备/软件导出前缀
        if reMatch(stem, "(?i)^(?:img[ _-]?[0-9]*|dji[ _-]?fly|dj[i]?[ _-]?mavic|psx_|pcm_|rp[ _-]?replay|screen[ _-]?rec|ffmpeg|whatsapp|telegram|wechat|weixin|微信|抖音|douyin|快手|kuaishou|小红书|剪映|视频号|vid_|vsc_|cam[0-9]|meta[0-9])") {
            return true
        }
        // 日期/时间开头的拍摄文件（如 2024_06_28_20_32_IMG）
        if reMatch(stem, "^[0-9]{4}[_-][0-9]{2}[_-][0-9]{2}[ _-][0-9]{2}[_-][0-9]{2}") {
            return true
        }
        // 相机/手机文件后缀标记出现在中后段（IMG/VID/PXL/MVI + 数字）
        if reMatch(stem, "(?i)(?:^|[_-])(?:img|vid|pxl|mvi|cam)[ _-]?[0-9]{3,}") {
            return true
        }
        // 中文网络平台 / 电商来源标记
        if reMatch(stem, "(?i)(?:爱给网|aigei[ _-]?com|_taobao|淘宝|京东|拼多多|jd\\.com|tmall|kling[ _-]?[0-9]|可灵|即梦|runway|sora|pika[ _-]?draft|liblib)") {
            return true
        }
        // 中文昵称/字幕/平台水印内容
        if isLikelyUserGeneratedChinese(stem) { return true }
        // 长随机 hash 或上传宿主专属串
        if reMatch(stem, "^(?:[0-9a-z]+[-_])?[0-9a-f]{16,}$") { return true }
        // v0/0bc 等上传宿主专属串开头
        if reMatch(stem, "(?i)^(?:v0[0-9]+|v[0-9]{3,}[A-Za-z]*|0bc[0-9a-z]+)[^ ]{8,}$") { return true }
        // 含义不明的短小写串（如 v036p）
        return isMeaninglessShortLower(stem)
    }

    private static func isLikelyUserGeneratedChinese(_ stem: String) -> Bool {
        let chineseCount = stem.reduce(0) { $0 + ($1.isCJK ? 1 : 0) }
        let total = stem.count
        guard total > 0, Double(chineseCount) / Double(total) >= 0.2 else { return false }
        // 含发行/剧集标记的不在此处判断
        if reMatch(stem, "(?i)(?:bluray|1080p|2160p|x264|x265|web[ ._-]?dl|中英双字|s[0-9]{1,2}e)") {
            return false
        }
        return true
    }

    private static func isMeaninglessShortLower(_ stem: String) -> Bool {
        guard stem.hasPrefix("v"), stem.count >= 2 else { return false }
        return reMatch(stem, "^v[0-9a-z]{1,6}$")
    }

    private static func isNumericOnlyTitle(_ stem: String) -> Bool {
        let trimmed = stem.trimmingCharacters(in: .whitespacesAndNewlines)
        if reMatch(trimmed, "^(?:[0-9]+(?:[_ -][0-9]+)*)?$") || reMatch(trimmed, "^[0-9]{8,}$") {
            return true
        }
        // 长串数字为主且无字母（如 20220927_4ee... 纯天数）
        return false
    }

    private static func isPlaceholderTitle(_ stem: String) -> Bool {
        if reMatch(stem, "(?i)^(?:未命名|无标题|新建文件夹|新建视频|新视频|untitled|new[ ._-]*(folder|video)|video|vlc[ ._-]*record|app[ ._-]*screen[ ._-]*record)") {
            return true
        }
        return reMatch(stem, "(?i)^video(?:[ (][0-9]+[ )])?$")
    }

    /// 中文占主体的内容标题（昵称、字幕、章节）→ 视为用户生成。
    private static func isLikelyUserGeneratedChineseTitle(_ stem: String) -> Bool {
        let cjk = stem.reduce(0) { $0 + ($1.isCJK ? 1 : 0) }
        let total = stem.count
        guard total > 0, Double(cjk) / Double(total) >= 0.5 else { return false }
        if reMatch(stem, "(?i)(?:1080p|2160p|x264|x265|bluray|web[ ._-]?dl|中英双字)") {
            return false
        }
        return true
    }

    /// 明文可信标题兜底：仅限拉丁文字、含独立年份或多词，才视为影片。
    private static func isReadableFilmTitle(_ lower: String) -> Bool {
        // 独立年份 token（非嵌入长数字，如 "Interstellar.2014"、"Pirate Radio 2009"）
        if reMatch(lower, "(?i)(^|[._ -])(?:19[0-9]{2}|20[0-9]{2})([._ -]|$)") {
            let wordCount = lower.split(whereSeparator: { !$0.isNumber && !$0.isLetter })
                .filter { $0.rangeOfCharacter(from: .letters) != nil }
                .filter { $0.count >= 2 }.count
            return wordCount >= 1
        }
        // 无年份：至少 3 个可读英文词才视为影片
        let words = lower.split(whereSeparator: { !$0.isLetter && $0 != " " && $0 != "-" })
            .filter { $0.count >= 2 }
        return words.count >= 3
    }

    /// 正则匹配辅助：统一走 regularExpression，避免遗漏 options 导致按字面量匹配。
    private static func reMatch(_ value: String, _ pattern: String) -> Bool {
        value.range(of: pattern, options: .regularExpression) != nil
    }

    private static func filenameStem(_ fileName: String) -> String {
        let url = URL(fileURLWithPath: fileName)
        return url.deletingPathExtension().lastPathComponent
    }
}

private extension Character {
    var isCJK: Bool {
        let scalar = unicodeScalars.first?.value ?? 0
        return (0x4E00...0x9FFF).contains(scalar)
            || (0x3400...0x4DBF).contains(scalar)
            || (0x3000...0x303F).contains(scalar)
            || (0xFF00...0xFFEF).contains(scalar)
            || (0x1F600...0x1F64F).contains(scalar)
            || (0x2600...0x27BF).contains(scalar)
    }
}
