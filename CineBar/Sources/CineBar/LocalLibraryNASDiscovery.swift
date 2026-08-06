import Foundation

/// 局域网 NAS 发现结果。
struct LocalLibraryDiscoveredNAS: Hashable, Identifiable {
    var id: String { "\(host):\(String(port))" }
    let host: String
    let port: Int
    let serviceType: String
    let displayName: String
    let brand: NASBrand?
    let smbShareHints: [String]
}

/// 主流 NAS 品牌识别。
enum NASBrand: String, Hashable {
    case synology   // 群晖
    case ugreen     // 绿联
    case qnap       // 威联通
    case asustor
    case terraMaster // 铁威马

    var displayName: String {
        switch self {
        case .synology: return "群晖 (Synology)"
        case .ugreen: return "绿联 (UGREEN)"
        case .qnap: return "威联通 (QNAP)"
        case .asustor: return "华芸 (ASUSTOR)"
        case .terraMaster: return "铁威马 (TerraMaster)"
        }
    }

    /// 品牌通常广播的 mDNS 服务类型与主机名特征（用商标词，不用通用词避免误判）。
    var mDNSHints: [String] {
        switch self {
        case .synology: return ["synology", "diskstation"]
        case .ugreen: return ["ugreen", "ugnas", "dna"]
        case .qnap: return ["qnap", "turbo", "ts-"]
        case .asustor: return ["asustor", "as-"]
        case .terraMaster: return ["terramaster", "f4-", "f2-"]
        }
    }

    /// 常见的 SMB 共享目录名（供预填）。
    var defaultSMBShare: String {
        switch self {
        case .ugreen: return "共享"
        case .synology: return "home"
        case .qnap: return "share"
        default: return "share"
        }
    }
}

/// 局域网 NAS 自动发现 + 一键连接。
enum LocalLibraryNASDiscovery {

    /// 用 dns-sd 枚举局域网里广播的常见 NAS 服务（SMB / HTTP / WebDAV / device-info）。
    /// 返回可能为空的已发现设备列表；网络无 NAS 或不允许发现时返回 []。
    @discardableResult
    static func scan(timeout: TimeInterval = 3) async -> [LocalLibraryDiscoveredNAS] {
        // 用 dns-sd 浏览 SMB 与 HTTP 服务，合并主机、去重。
        let smbHosts = await browse(serviceType: "_smb._tcp", timeout: timeout)
        let httpHosts = await browse(serviceType: "_http._tcp", timeout: timeout)
        let deviceHosts = await browse(serviceType: "_device-info._tcp", timeout: timeout)

        // 合并：Smb 优先（更可能是 NAS），补充 HTTP 发现的设备。
        var merged: [LocalLibraryDiscoveredNAS] = []
        var seenHosts = Set<String>()
        for entry in (smbHosts + httpHosts + deviceHosts) {
            guard !seenHosts.contains(entry.host) else { continue }
            let key = "\(entry.host):\(entry.port)"
            if merged.contains(where: { "\($0.host):\($0.port)" == key }) {
                continue
            }
            seenHosts.insert(entry.host)
            let brand = recognizeBrand(hostname: entry.host, serviceType: entry.serviceType)
            merged.append(LocalLibraryDiscoveredNAS(
                host: entry.host,
                port: entry.port,
                serviceType: entry.serviceType,
                displayName: entry.displayName,
                brand: brand,
                smbShareHints: brand.map { [$0.defaultSMBShare, "media", "Video", "Movies"] } ?? ["share", "media"]
            ))
        }
        return merged
    }

    /// 品牌识别：根据主机名关键词 + 服务类型。
    static func recognizeBrand(hostname: String, serviceType: String) -> NASBrand? {
        let name = hostname.lowercased()
        let brands: [NASBrand] = [.synology, .ugreen, .qnap, .asustor, .terraMaster]
        for brand in brands {
            for hint in brand.mDNSHints {
                if name.contains(hint) {
                    return brand
                }
            }
        }
        return nil
    }

    /// 检测某 SMB 主机是否已被系统挂载成卷（返回 /Volumes 下的路径）。
    static func mountedVolumeURL(host: String, port: Int) -> URL? {
        let keys: Set<URLResourceKey> = [.volumeNameKey, .volumeURLForRemountingKey]
        guard let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: Array(keys),
            options: []
        ) else { return nil }
        for url in urls {
            // 尝试通过 volume URLForRemounting 拿到原始网络路径
            if let remount = try? url.resourceValues(forKeys: keys).volumeURLForRemounting {
                if remount.absoluteString.lowercased().contains(host.lowercased()) {
                    if FileManager.default.fileExists(atPath: url.path) {
                        return url
                    }
                }
            }
            // 兜底：卷名或路径含主机名片段
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
               isDirectory.boolValue,
               url.path.lowercased().contains(host.lowercased()) {
                return url
            }
        }
        return nil
    }

    // MARK: - dns-sd 基础浏览

    private struct DiscoveredEntry: Hashable {
        let host: String
        let port: Int
        let displayName: String
        let serviceType: String
    }

    /// 用 dns-sd 浏览给定服务类型，收集返回的实例。
    private static func browse(serviceType: String, timeout: TimeInterval) async -> [DiscoveredEntry] {
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/dns-sd") else {
            return []
        }
        return await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/dns-sd")
            process.arguments = ["-B", serviceType]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            process.standardInput = FileHandle.nullDevice

            do {
                try process.run()
            } catch {
                continuation.resume(returning: [])
                return
            }

            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                process.terminate()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let text = String(data: data, encoding: .utf8) ?? ""
                continuation.resume(returning: parseBrowseOutput(text))
            }
        }
    }

    /// 解析 dns-sd -B 输出。每行形如：
    /// Add 2 1 mynas._smb._tcp.             mynas.local. 445
    private static func parseBrowseOutput(_ text: String) -> [DiscoveredEntry] {
        var entries: [DiscoveredEntry] = []
        let lines = text.components(separatedBy: "\n")
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("Add") else { continue }
            // 去掉 "Add N I" 前缀
            let parts = trimmed.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 5 else { continue }
            // parts[0]=Add parts[1]=flags parts[2]=if parts[3]=name._type. parts[4]=host:port
            let nameToken = String(parts[3])
            let hostPort = String(parts[4])
            // 解析 host:port
            let components = hostPort.components(separatedBy: ":")
            guard components.count == 2, let port = Int(components[1]) else { continue }
            // 去掉结尾的 _smb._tcp. 得到设备名
            let displayName = nameToken
                .components(separatedBy: ".").first ?? nameToken
            entries.append(DiscoveredEntry(
                host: components[0],
                port: port,
                displayName: displayName,
                serviceType: serviceType(fromNameToken: nameToken)
            ))
        }
        return entries
    }

    private static func serviceType(fromNameToken token: String) -> String {
        // token 形如 "name._smb._tcp."，取中间类型
        let parts = token.components(separatedBy: ".")
        return parts.dropFirst().first ?? ""
    }
}
