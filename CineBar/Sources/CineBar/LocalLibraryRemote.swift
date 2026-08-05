import Foundation

/// 远程媒体源（NAS）的连接描述。`bookmarkData` 对本地卷使用；对远程源为 nil，
/// 改为通过 `remote` 描述连接方式与凭据引用（凭据本身存 Keychain，不落盘到快照）。
struct LocalLibraryRemoteSource: Codable, Hashable {
    enum Kind: String, Codable {
        case webDAV
        case sftp
    }

    var kind: Kind

    /// 主机地址（不带协议与路径）。如 "nas.local"、"192.168.1.10"。
    var host: String

    /// 端口。nil 时用协议默认端口（WebDAV 默认 443）。绿联 WebDAV 常为 5006。
    var port: Int?

    /// 是否使用 TLS/HTTPS（对 WebDAV 为 https，对 SFTP 为 SSH 天然加密）。
    var usesTLS: Bool

    /// 远程根路径，如 "/" 或 "/dav"。同一样常存储库内相对路径由此展开。
    var rootPath: String

    /// 用户名。
    var username: String

    /// Keychain 中保存密码的服务与账号标识。真实密码只在 Keychain，快照存引用。
    var keychainService: String
    var keychainAccount: String

    /// 连接基础地址元信息（不用于实际鉴权）。
    var displayName: String
}

enum LocalLibraryKeychainCredential {
    static func store(
        service: String,
        account: String,
        password: String
    ) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let passwordData = Data(password.utf8)
        let attributes: [String: Any] = [
            kSecValueData as String: passwordData
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var add = query
            add[kSecValueData as String] = passwordData
            let addStatus = SecItemAdd(add as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw LocalLibraryKeychainError.storeFailed(status: addStatus)
            }
        } else if status != errSecSuccess {
            throw LocalLibraryKeychainError.storeFailed(status: status)
        }
    }

    static func load(service: String, account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let password = String(data: data, encoding: .utf8)
        else { return nil }
        return password
    }
}

enum LocalLibraryKeychainError: LocalizedError {
    case storeFailed(status: OSStatus)

    var errorDescription: String? {
        switch self {
        case .storeFailed:
            return "无法保存到钥匙串。"
        }
    }
}

/// 远程目录中的一个条目。
struct LocalLibraryRemoteItem: Hashable {
    let name: String
    let isDirectory: Bool
    let byteCount: Int64
    let relativePath: String
}

/// 远程源同步枚举能力：列出子目录、解析出可读的播放数据或本地临时文件。
enum LocalLibraryRemoteBackend {
    /// 枚举 remote 源根下的一个目录，返回直接子项。
    @MainActor
    static func list(
        source: LocalLibraryRemoteSource,
        relativePath: String
    ) async throws -> [LocalLibraryRemoteItem] {
        switch source.kind {
        case .webDAV:
            return try await WebDAVClient().list(source: source, relativePath: relativePath)
        case .sftp:
            return try await SFTPClient().list(source: source, relativePath: relativePath)
        }
    }

    /// 将远程文件下载/解析成本地可播放临时文件。返回本地 URL 或 nil。
    static func materialize(
        source: LocalLibraryRemoteSource,
        relativePath: String
    ) async throws -> URL? {
        switch source.kind {
        case .webDAV:
            return try await WebDAVClient().materialize(source: source, relativePath: relativePath)
        case .sftp:
            return try await SFTPClient().materialize(source: source, relativePath: relativePath)
        }
    }
}
