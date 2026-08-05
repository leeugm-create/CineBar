import Foundation

/// SFTP 客户端：封装系统 `/usr/bin/sftp` 的批处理模式。
/// 使用 SSH_ASKPASS 提供非交互密码，避免需要交互式终端。
struct SFTPClient {
    private var available: Bool {
        FileManager.default.isExecutableFile(atPath: "/usr/bin/sftp")
    }

    private var homeDirectory: String {
        NSHomeDirectory()
    }

    /// 生成一个脚本：输出一次密码给 ssh-askpass。
    private func askPassScript(source: LocalLibraryRemoteSource) -> String {
        let password = LocalLibraryKeychainCredential.load(
            service: source.keychainService,
            account: source.keychainAccount
        ) ?? ""
        let script = """
        #!/bin/sh
        echo "\(password)"
        """
        return script
    }

    private func target(_ source: LocalLibraryRemoteSource) -> String {
        // host:port
        let hostPort = source.port.map { "\(source.host):\($0)" } ?? source.host
        return "\(source.username)@\(hostPort)"
    }

    /// 在临时脚本中封装一次 sftp 批处理。错误抛出到调用方。
    private func runBatch(
        source: LocalLibraryRemoteSource,
        commands: [String],
        timeout: TimeInterval = 60
    ) throws -> String {
        guard available else { throw LocalLibraryRemoteError.invalidResponse }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cinebar-sftp-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        // 1. askpass 脚本
        let askpassURL = tempDir.appendingPathComponent("askpass.sh")
        try askPassScript(source: source).write(to: askpassURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: askpassURL.path)

        // 2. 批处理文件
        let batchURL = tempDir.appendingPathComponent("batch.txt")
        let batchContent = commands.joined(separator: "\n") + "\nquit\n"
        try batchContent.write(to: batchURL, atomically: true, encoding: .utf8)

        // 3. 用 ssh-askpass 方式运行 sftp
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sftp")
        process.arguments = [
            "-q",
            "-b", batchURL.path,
            "-o", "BatchMode=no",
            "-o", "StrictHostKeyChecking=no",
            "-o", "UserKnownHostsFile=/dev/null",
            "-o", "ConnectTimeout=15",
            target(source)
        ]
        var environment = ProcessInfo.processInfo.environment
        environment["SSH_ASKPASS"] = askpassURL.path
        environment["SSH_ASKPASS_REQUIRE"] = "force"
        environment["DISPLAY"] = ":0"
        process.environment = environment

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice

        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()

        try? FileManager.default.removeItem(at: tempDir)

        guard process.terminationStatus == 0 else {
            return String(data: data, encoding: .utf8) ?? ""
        }
        return String(data: data, encoding: .utf8) ?? ""
    }

    /// 列出目录（相对 remote 根的路径）。
    func list(
        source: LocalLibraryRemoteSource,
        relativePath: String
    ) async throws -> [LocalLibraryRemoteItem] {
        let remoteDir = buildRemotePath(source, relativePath: relativePath)
        let output = try runBatch(
            source: source,
            commands: ["ls -la \"\(remoteDir)\""]
        )
        return parseLSLong(output)
    }

    /// 将远程文件下载到本地临时文件。
    func materialize(
        source: LocalLibraryRemoteSource,
        relativePath: String
    ) async throws -> URL? {
        let remoteSrc = buildRemotePath(source, relativePath: relativePath)
        let name = relativePath.components(separatedBy: "/").last ?? "download"
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("cinebar-remote-\(UUID().uuidString)-\(name)")
        _ = try runBatch(
            source: source,
            commands: ["get \"\(remoteSrc)\" \"\(dest.path)\""]
        )
        return FileManager.default.fileExists(atPath: dest.path) ? dest : nil
    }

    private func buildRemotePath(
        _ source: LocalLibraryRemoteSource,
        relativePath: String
    ) -> String {
        let root = source.rootPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let parts = [root, relativePath].filter { !$0.isEmpty }
        return "/" + parts.joined(separator: "/")
    }

    /// 解析 `ls -la` 长格式输出。
    private func parseLSLong(_ output: String) -> [LocalLibraryRemoteItem] {
        var items: [LocalLibraryRemoteItem] = []
        let lines = output.components(separatedBy: "\n")
        for line in lines {
            // 形如：-rw-r--r-- 1 user group 1234 Aug 1 12:00 file.mkv
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 9 else { continue }
            let perms = String(parts[0])
            guard perms.hasPrefix("-") || perms.hasPrefix("d") || perms.hasPrefix("l") else { continue }
            guard parts[0].first == "-" || parts[0].first == "d" else { continue }
            if parts[0].first == "d" { continue } // 目录交给上层递归时处理，这里只返回文件/链接
            let byteCount = Int64(parts[4]) ?? 0
            // 名字是第 9+ 个（可能含空格，取最后一个到末尾）
            let nameRange = parts[8...]
            let name = nameRange.joined(separator: " ")
            let isDirectory = perms.hasPrefix("d")
            guard !name.isEmpty else { continue }
            items.append(LocalLibraryRemoteItem(
                name: name,
                isDirectory: isDirectory,
                byteCount: byteCount,
                relativePath: name
            ))
        }
        return items
    }
}
