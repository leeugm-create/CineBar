import Foundation

struct ServiceEndpointSet {
    let urls: [URL]

    init(primary: String?, backups: [String]) {
        let candidates = [primary ?? ""] + backups
        var seen = Set<String>()

        urls = candidates.compactMap {
            DataProxyConfiguration.normalizedBaseURL($0)
        }
        .filter { seen.insert($0).inserted }
        .compactMap(URL.init(string:))
    }
}

enum ServiceBundleConfiguration {
    static func stringArray(
        forInfoDictionaryKey key: String,
        bundle: Bundle = .main
    ) -> [String] {
        bundle.object(forInfoDictionaryKey: key) as? [String] ?? []
    }
}

enum ServiceFailureCategory: String, Hashable {
    case dns
    case tls
    case connection
    case timeout
    case server
    case client
    case other

    static func classify(_ error: Error) -> ServiceFailureCategory {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .cannotFindHost, .dnsLookupFailed:
                return .dns
            case .secureConnectionFailed,
                 .serverCertificateHasBadDate,
                 .serverCertificateUntrusted,
                 .serverCertificateHasUnknownRoot,
                 .serverCertificateNotYetValid:
                return .tls
            case .cannotConnectToHost, .networkConnectionLost:
                return .connection
            case .timedOut:
                return .timeout
            default:
                return .other
            }
        }
        if case ServiceHTTPError.statusCode(
            let statusCode,
            _
        ) = error {
            return (500...599).contains(statusCode) ? .server : .client
        }
        return .other
    }

    func displayName(language: AppLanguage) -> String {
        let simplified: String
        switch self {
        case .dns: simplified = "域名解析错误"
        case .tls: simplified = "安全连接错误"
        case .connection: simplified = "网络连接错误"
        case .timeout: simplified = "请求超时"
        case .server: simplified = "服务器暂时不可用"
        case .client: simplified = "请求被服务拒绝"
        case .other: simplified = "未知网络错误"
        }
        switch language {
        case .zhCN:
            return simplified
        case .zhHK, .zhTW:
            return [
                .dns: "網域解析錯誤",
                .tls: "安全連線錯誤",
                .connection: "網絡連線錯誤",
                .timeout: "請求逾時",
                .server: "伺服器暫時無法使用",
                .client: "服務拒絕了請求",
                .other: "未知網絡錯誤",
            ][self]!
        case .enUS:
            return [
                .dns: "DNS lookup failed",
                .tls: "Secure connection failed",
                .connection: "Network connection failed",
                .timeout: "Request timed out",
                .server: "Server temporarily unavailable",
                .client: "Request rejected by service",
                .other: "Unknown network error",
            ][self]!
        case .jaJP:
            return [
                .dns: "DNS解決エラー",
                .tls: "安全な接続エラー",
                .connection: "ネットワーク接続エラー",
                .timeout: "リクエストがタイムアウトしました",
                .server: "サーバーを一時的に利用できません",
                .client: "サービスがリクエストを拒否しました",
                .other: "不明なネットワークエラー",
            ][self]!
        case .koKR:
            return [
                .dns: "DNS 조회 실패",
                .tls: "보안 연결 실패",
                .connection: "네트워크 연결 실패",
                .timeout: "요청 시간 초과",
                .server: "서버를 일시적으로 사용할 수 없음",
                .client: "서비스에서 요청을 거부함",
                .other: "알 수 없는 네트워크 오류",
            ][self]!
        }
    }
}

enum ServiceRequestPolicy {
    static let attemptsPerEndpoint = 2

    static func isRetryable(error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }
        return [
            .cannotFindHost,
            .dnsLookupFailed,
            .secureConnectionFailed,
            .serverCertificateHasBadDate,
            .serverCertificateUntrusted,
            .serverCertificateHasUnknownRoot,
            .serverCertificateNotYetValid,
            .cannotConnectToHost,
            .networkConnectionLost,
            .timedOut,
        ].contains(urlError.code)
    }

    static func isRetryable(statusCode: Int) -> Bool {
        (500...599).contains(statusCode)
    }
}

struct ServiceDiagnostic {
    let service: String
    let category: ServiceFailureCategory
    let timestamp: Date
    let appVersion: String
    let requestURL: URL

    var redactedText: String {
        let origin = [
            requestURL.scheme,
            requestURL.host,
        ]
        .compactMap { $0 }
        .joined(separator: "://")

        return [
            "CineBar \(appVersion)",
            "UTC: \(ISO8601DateFormatter().string(from: timestamp))",
            "Service: \(service)",
            "Category: \(category.rawValue)",
            "Endpoint: \(origin)",
        ]
        .joined(separator: "\n")
    }
}

protocol ServiceDataLoading {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: ServiceDataLoading {}

enum ServiceHTTPError: Error {
    case invalidResponse
    case statusCode(Int, Data)
}

struct ResilientHTTPClient {
    let loader: ServiceDataLoading

    init(loader: ServiceDataLoading = URLSession.shared) {
        self.loader = loader
    }

    func data(
        endpointSet: ServiceEndpointSet,
        buildRequest: (URL) throws -> URLRequest
    ) async throws -> (Data, HTTPURLResponse) {
        var lastRetryableError: Error?

        for endpoint in endpointSet.urls {
            for _ in 0..<ServiceRequestPolicy.attemptsPerEndpoint {
                do {
                    let request = try buildRequest(endpoint)
                    let (data, response) = try await loader.data(for: request)
                    guard let http = response as? HTTPURLResponse else {
                        throw ServiceHTTPError.invalidResponse
                    }
                    if (200...299).contains(http.statusCode) {
                        return (data, http)
                    }
                    guard ServiceRequestPolicy.isRetryable(
                        statusCode: http.statusCode
                    ) else {
                        throw ServiceHTTPError.statusCode(
                            http.statusCode,
                            data
                        )
                    }
                    lastRetryableError = ServiceHTTPError.statusCode(
                        http.statusCode,
                        data
                    )
                } catch {
                    guard ServiceRequestPolicy.isRetryable(error: error) else {
                        throw error
                    }
                    lastRetryableError = error
                }
            }
        }

        throw lastRetryableError ?? URLError(.badURL)
    }
}

struct LastSuccessfulBrowseCache {
    private let movieKey = "lastSuccessfulMovies"
    private let televisionKey = "lastSuccessfulTelevision"
    let defaults: UserDefaults

    func saveMovies(_ movies: [Movie]) {
        save(movies, forKey: movieKey)
    }

    func loadMovies() -> [Movie]? {
        load([Movie].self, forKey: movieKey)
    }

    func saveTelevision(_ shows: [TVShow]) {
        save(shows, forKey: televisionKey)
    }

    func loadTelevision() -> [TVShow]? {
        load([TVShow].self, forKey: televisionKey)
    }

    private func save<Value: Encodable>(
        _ value: [Value],
        forKey key: String
    ) {
        guard !value.isEmpty, let data = try? JSONEncoder().encode(value) else {
            return
        }
        defaults.set(data, forKey: key)
    }

    private func load<Value: Decodable>(
        _ type: [Value].Type,
        forKey key: String
    ) -> [Value]? {
        guard let data = defaults.data(forKey: key) else { return nil }
        guard let value = try? JSONDecoder().decode(type, from: data) else {
            defaults.removeObject(forKey: key)
            return nil
        }
        return value.isEmpty ? nil : value
    }
}

enum ServiceErrorPresentation {
    static func message(
        language: AppLanguage,
        hasCachedContent: Bool
    ) -> String {
        if hasCachedContent {
            switch language {
            case .zhCN:
                return "网络不稳定，正在显示上次更新内容"
            case .zhHK, .zhTW:
                return "網絡不穩定，正在顯示上次更新內容"
            case .enUS:
                return "Network is unstable. Showing the last updated content."
            case .jaJP:
                return "ネットワークが不安定なため、前回の更新内容を表示しています"
            case .koKR:
                return "네트워크가 불안정하여 마지막 업데이트 내용을 표시합니다"
            }
        }

        switch language {
        case .zhCN:
            return "服务暂时不可用，请稍后重试"
        case .zhHK, .zhTW:
            return "服務暫時不可用，請稍後再試"
        case .enUS:
            return "The service is temporarily unavailable. Please try again later."
        case .jaJP:
            return "サービスを一時的に利用できません。しばらくしてから再試行してください"
        case .koKR:
            return "서비스를 일시적으로 사용할 수 없습니다. 잠시 후 다시 시도해 주세요"
        }
    }
}
