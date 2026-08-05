import Foundation

/// WebDAV 客户端：基于 URLSession 的 PROPFIND 目录枚举 + GET 下载到临时文件。
/// 绿联 NAS 的 WebDAV 通常为 https://<host>:5006（启用 TLS）。
struct WebDAVClient {
    var session: URLSession = .shared

    private func baseURL(for source: LocalLibraryRemoteSource) -> URL {
        var components = URLComponents()
        components.scheme = source.usesTLS ? "https" : "http"
        components.host = source.host
        if let port = source.port {
            components.port = port
        }
        return components.url!
    }

    private func authHeader(for source: LocalLibraryRemoteSource) -> String? {
        guard let password = LocalLibraryKeychainCredential.load(
            service: source.keychainService,
            account: source.keychainAccount
        ) else { return nil }
        let credentials = "\(source.username):\(password)"
        let data = Data(credentials.utf8).base64EncodedString()
        return "Basic \(data)"
    }

    private func url(
        for source: LocalLibraryRemoteSource,
        relativePath: String
    ) -> URL {
        baseURL(for: source)
            .appendingPathComponent(source.rootPath.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
            .appendingPathComponent(relativePath)
    }

    private func request(
        source: LocalLibraryRemoteSource,
        relativePath: String,
        method: String,
        depth: String? = nil
    ) -> URLRequest {
        var request = URLRequest(url: url(for: source, relativePath: relativePath))
        request.httpMethod = method
        if let auth = authHeader(for: source) {
            request.setValue(auth, forHTTPHeaderField: "Authorization")
        }
        if let depth {
            request.setValue(depth, forHTTPHeaderField: "Depth")
        }
        request.setValue("application/xml", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30
        return request
    }

    /// 用 PROPFIND 列出目录的直接子项。
    func list(
        source: LocalLibraryRemoteSource,
        relativePath: String
    ) async throws -> [LocalLibraryRemoteItem] {
        var request = request(
            source: source,
            relativePath: relativePath,
            method: "PROPFIND",
            depth: "1"
        )
        request.httpBody = """
        <?xml version="1.0" encoding="utf-8"?>
        <d:propfind xmlns:d="DAV:"><d:prop><d:displayname/><d:getcontentlength/><d:resourcetype/></d:prop></d:propfind>
        """.data(using: .utf8)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw LocalLibraryRemoteError.invalidResponse
        }
        guard http.statusCode / 100 == 2 else {
            throw LocalLibraryRemoteError.httpStatus(http.statusCode)
        }
        return Self.parsePROPFIND(
            data,
            base: relativePath
        )
    }

    /// 将远程文件下载到本地临时目录返回 URL。
    func materialize(
        source: LocalLibraryRemoteSource,
        relativePath: String
    ) async throws -> URL? {
        let request = request(
            source: source,
            relativePath: relativePath,
            method: "GET"
        )
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode / 100 == 2 else {
            return nil
        }
        let name = relativePath.components(separatedBy: "/").last ?? "download"
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("cinebar-remote-\(UUID().uuidString)-\(name)")
        try data.write(to: dest)
        return dest
    }

    /// 解析 PROPFIND 的 multistatus 响应。
    private static func parsePROPFIND(
        _ data: Data,
        base: String
    ) -> [LocalLibraryRemoteItem] {
        let xml = String(data: data, encoding: .utf8) ?? ""
        // 简化的 href / getcontentlength / resourcetype 解析
        var items: [LocalLibraryRemoteItem] = []
        // 用正则拆分 <response>…</response>
        let responsePattern = #"<d:response>.*?</d:response>|<response>.*?</response>"#
        guard let regex = try? NSRegularExpression(
            pattern: responsePattern,
            options: [.dotMatchesLineSeparators]
        ) else { return [] }
        let nsRange = NSRange(xml.startIndex..<xml.endIndex, in: xml)
        let matches = regex.matches(in: xml, options: [], range: nsRange)
        for match in matches {
            guard let range = Range(match.range, in: xml) else { continue }
            let block = String(xml[range])
            guard let parsed = Self.parseResponseBlock(block) else { continue }
            items.append(parsed)
        }
        // 去掉对目录本身（与 base 同名）的引用
        let baseLast = base.components(separatedBy: "/").last
        return items.filter {
            if $0.relativePath == base || $0.relativePath == baseLast {
                return false
            }
            return true
        }
    }

    private static func parseResponseBlock(_ block: String) -> LocalLibraryRemoteItem? {
        guard let href = extract(tag: "href", from: block) else { return nil }
        let lengthText = extract(tag: "getcontentlength", from: block) ?? "0"
        let isDirectory = block.contains("collection")
        let bytes = isDirectory ? 0 : (Int64(lengthText) ?? 0)
        let path = href.components(separatedBy: "://").last.map {
            String($0.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: true).last ?? "")
        } ?? href
        let decodedPath = path.removingPercentEncoding ?? path
        let name = decodedPath.components(separatedBy: "/").last ?? ""
        return LocalLibraryRemoteItem(
            name: name,
            isDirectory: isDirectory,
            byteCount: isDirectory ? 0 : bytes,
            relativePath: decodedPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        )
    }

    private static func extract(tag: String, from block: String) -> String? {
        let patterns = [
            "d:\(tag)>(.*?)</d:\(tag)>",
            "\(tag)>(.*?)</\(tag)>"
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(
                pattern: pattern,
                options: [.dotMatchesLineSeparators]
            ) {
                let nsRange = NSRange(block.startIndex..<block.endIndex, in: block)
                if let match = regex.firstMatch(in: block, options: [], range: nsRange),
                   let range = Range(match.range(at: 1), in: block) {
                    return String(block[range])
                }
            }
        }
        return nil
    }
}

enum LocalLibraryRemoteError: LocalizedError {
    case invalidResponse
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "远程服务器响应无效。"
        case .httpStatus(let code):
            return "远程服务器返回 \(code)。"
        }
    }
}
