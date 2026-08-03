import Foundation

struct CineBarTelemetryPayload: Codable, Equatable {
    let installID: String
    let appVersion: String
    let build: Int
    let platform: String
    let osMajor: Int
    let architecture: String
    let language: String
    let occurredAt: String

    enum CodingKeys: String, CodingKey {
        case installID = "install_id"
        case appVersion = "app_version"
        case build
        case platform
        case osMajor = "os_major"
        case architecture
        case language
        case occurredAt = "occurred_at"
    }
}

struct CineBarTelemetryClient {
    static let endpoint: URL = {
        if let configured = Bundle.main.object(
            forInfoDictionaryKey: "CineBarTelemetryURL"
        ) as? String, let url = URL(string: configured) {
            return url
        }
        return URL(string: "https://telemetry.cinebar.cc/v1/telemetry/install")!
    }()
    static let installIDDefaultsKey = "cineBarAnonymousInstallID"
    static let lastReportDateDefaultsKey = "cineBarTelemetryLastReportDate"

    private let endpoint: URL
    private let defaults: UserDefaults
    private let now: () -> Date
    private let send: (URLRequest) async throws -> Void
    private let encoder: JSONEncoder

    init(
        endpoint: URL = CineBarTelemetryClient.endpoint,
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = Date.init,
        send: @escaping (URLRequest) async throws -> Void = { request in
            _ = try await URLSession.shared.data(for: request)
        }
    ) {
        self.endpoint = endpoint
        self.defaults = defaults
        self.now = now
        self.send = send
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder
    }

    func reportIfNeeded(
        appVersion: String = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "0.8.3",
        build: Int = Int(
            Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        ) ?? 0,
        language: String
    ) async {
        let currentDate = now()
        guard shouldReport(on: currentDate) else { return }

        let payload = CineBarTelemetryPayload(
            installID: installID(),
            appVersion: appVersion,
            build: build,
            platform: "macOS",
            osMajor: ProcessInfo.processInfo.operatingSystemVersion.majorVersion,
            architecture: Self.architecture,
            language: Self.normalizedLanguage(language),
            occurredAt: Self.iso8601String(currentDate)
        )

        guard let body = try? encoder.encode(payload) else { return }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 8
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("CineBar/\(appVersion)", forHTTPHeaderField: "User-Agent")

        do {
            try await send(request)
            defaults.set(currentDate, forKey: Self.lastReportDateDefaultsKey)
        } catch {
            // Telemetry must never delay startup or show an error to the user.
        }
    }

    func installID() -> String {
        if let saved = defaults.string(forKey: Self.installIDDefaultsKey),
           UUID(uuidString: saved) != nil {
            return saved.lowercased()
        }
        let generated = UUID().uuidString.lowercased()
        defaults.set(generated, forKey: Self.installIDDefaultsKey)
        return generated
    }

    func shouldReport(on date: Date) -> Bool {
        guard let lastReport = defaults.object(
            forKey: Self.lastReportDateDefaultsKey
        ) as? Date else {
            return true
        }
        return !Calendar.autoupdatingCurrent.isDate(
            lastReport,
            inSameDayAs: date
        )
    }

    static func normalizedLanguage(_ language: String) -> String {
        switch language {
        case "zh-Hans", "zh-Hant", "en", "ja", "ko": return language
        case "zh-CN", "zhCN": return "zh-Hans"
        case "zh-HK", "zh-TW", "zh-Hant-HK", "zh-Hant-TW", "zhHK", "zhTW":
            return "zh-Hant"
        case "en-US", "enUS": return "en"
        case "ja-JP", "jaJP": return "ja"
        case "ko-KR", "koKR": return "ko"
        default: return "zh-Hans"
        }
    }

    private static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static func iso8601String(_ date: Date) -> String {
        iso8601Formatter.string(from: date)
    }

    private static var architecture: String {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "x86_64"
        #else
        return "x86_64"
        #endif
    }
}
