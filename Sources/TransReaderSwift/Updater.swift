import Foundation
import AppKit
import CryptoKit

// MARK: - Update Types

struct UpdateInfo: Sendable {
    let version: String
    let downloadURL: URL
    let checksumURL: URL
}

enum UpdateStage: Sendable, Equatable {
    case checking
    case downloading(progress: Double)
    case extracting
    case installing
    case relaunching
}

// GitHub Release API response (only fields we need)
private struct GitHubRelease: Decodable {
    let tagName: String
    let assets: [Asset]

    struct Asset: Decodable {
        let name: String
        let browserDownloadUrl: String
        let size: Int64?

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadUrl = "browser_download_url"
            case size
        }
    }

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case assets
    }
}

// MARK: - Updater Actor

actor Updater {
    private static let githubRepo = "SongRunqi/transreader-releases"
    private static let releasesURL = URL(string: "https://api.github.com/repos/\(githubRepo)/releases/latest")!

    /// Whether the app is running as a .app bundle (vs `swift run` or `make run-debug`)
    static var isBundle: Bool {
        Bundle.main.bundlePath.hasSuffix(".app")
    }

    /// Current version from Info.plist, or "dev" if not in bundle
    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }

    // MARK: - Check for Update

    func checkForUpdate() async throws -> UpdateInfo? {
        guard Updater.isBundle else {
            appLog("[Update] Not running as .app bundle, skipping update check")
            return nil
        }

        let currentVersion = Updater.currentVersion
        appLog("[Update] Checking for updates... current version: \(currentVersion)")

        var request = URLRequest(url: Updater.releasesURL, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            appLog("[Update] GitHub API returned non-2xx status")
            return nil
        }

        let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
        let latestVersion = release.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))

        guard compareVersions(latestVersion, isNewerThan: currentVersion) else {
            appLog("[Update] Already up to date (latest: \(latestVersion))")
            return nil
        }

        // Find .zip asset and its SHA-256 sidecar
        guard let zipAsset = release.assets.first(where: { $0.name.hasSuffix(".zip") }),
              let downloadURL = URL(string: zipAsset.browserDownloadUrl) else {
            appLog("[Update] No .zip asset found in release \(release.tagName)")
            return nil
        }

        let checksumNames = [
            "\(zipAsset.name).sha256",
            "\(zipAsset.name).sha256sum",
            "\(zipAsset.name).sha256.txt",
            zipAsset.name.replacingOccurrences(of: ".zip", with: ".sha256")
        ]
        guard let checksumAsset = release.assets.first(where: { checksumNames.contains($0.name) }),
              let checksumURL = URL(string: checksumAsset.browserDownloadUrl) else {
            throw UpdateError.missingChecksum
        }

        appLog("[Update] New version available: \(latestVersion)")
        return UpdateInfo(version: latestVersion, downloadURL: downloadURL, checksumURL: checksumURL)
    }

    // MARK: - Download and Install

    func downloadAndInstall(_ info: UpdateInfo, onProgress: @Sendable (UpdateStage) -> Void) async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("transreader-update-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        // 1. Determine install path (handle App Translocation)
        let installPath = resolveInstallPath()
        appLog("[Update] Install target: \(installPath)")

        // 2. Download ZIP
        onProgress(.downloading(progress: 0))
        let zipPath = tempDir.appendingPathComponent("update.zip")
        let expectedSHA256 = try await downloadChecksum(from: info.checksumURL)
        let actualSHA256 = try await downloadFile(from: info.downloadURL, to: zipPath, onProgress: onProgress)
        guard actualSHA256.caseInsensitiveCompare(expectedSHA256) == .orderedSame else {
            throw UpdateError.checksumMismatch
        }
        appLog("[Update] Checksum verified")

        // 3. Extract with ditto (preserves signatures, symlinks, xattrs)
        onProgress(.extracting)
        let extractDir = tempDir.appendingPathComponent("extracted")
        try FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)
        try runProcess("/usr/bin/ditto", arguments: ["-xk", zipPath.path, extractDir.path])
        appLog("[Update] Extracted ZIP")

        // 4. Find .app in extracted directory
        let contents = try FileManager.default.contentsOfDirectory(atPath: extractDir.path)
        guard let appName = contents.first(where: { $0.hasSuffix(".app") }) else {
            throw UpdateError.noAppInZip
        }
        let newAppPath = extractDir.appendingPathComponent(appName)
        try verifyBundle(at: newAppPath.path, expectedVersion: info.version)

        // 5. Atomic replace: rename current → backup, ditto new → install, restore on failure
        onProgress(.installing)
        let installURL = URL(fileURLWithPath: installPath)
        let backupPath = installPath + ".bak"
        let backupURL = URL(fileURLWithPath: backupPath)

        // Remove stale backup if exists
        try? FileManager.default.removeItem(at: backupURL)

        do {
            // Backup current app
            if FileManager.default.fileExists(atPath: installPath) {
                try FileManager.default.moveItem(at: installURL, to: backupURL)
            }

            // Copy new app to install location using ditto (preserves code signature)
            try runProcess("/usr/bin/ditto", arguments: [newAppPath.path, installPath])
            try verifyBundle(at: installPath, expectedVersion: info.version)
            appLog("[Update] Installed new version to \(installPath)")

            // Clear quarantine xattr (non-fatal if it fails)
            QuarantineHelper.removeQuarantine(at: installPath)

            // Remove backup
            try? FileManager.default.removeItem(at: backupURL)

        } catch {
            // Rollback: restore from backup
            appLog("[Update] Install failed, rolling back: \(error.localizedDescription)")
            if FileManager.default.fileExists(atPath: backupPath) {
                try? FileManager.default.removeItem(atPath: installPath)
                try? FileManager.default.moveItem(atPath: backupPath, toPath: installPath)
            }
            throw UpdateError.installFailed(error.localizedDescription)
        }

        // 6. Relaunch from install path
        onProgress(.relaunching)
        appLog("[Update] Relaunching from \(installPath)...")
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        try await NSWorkspace.shared.openApplication(at: installURL, configuration: config)

        // Hard exit to avoid race conditions during graceful shutdown
        exit(0)
    }

    // MARK: - Helpers

    /// Compare semantic versions: returns true if `a` is newer than `b`
    private func compareVersions(_ a: String, isNewerThan b: String) -> Bool {
        let partsA = versionTuple(a)
        let partsB = versionTuple(b)
        for i in 0..<max(partsA.count, partsB.count) {
            let va = i < partsA.count ? partsA[i] : 0
            let vb = i < partsB.count ? partsB[i] : 0
            if va > vb { return true }
            if va < vb { return false }
        }
        return false
    }

    /// Parse version string into array of integers: "1.2.3" → [1, 2, 3]
    private func versionTuple(_ version: String) -> [Int] {
        version.split(separator: ".").compactMap { Int($0.filter { $0.isNumber }) }
    }

    /// Determine where to install: delegates to TranslocationHelper for
    /// automatic App Translocation handling.
    private func resolveInstallPath() -> String {
        TranslocationHelper.installPath()
    }

    /// Download file with progress reporting
    /// Returns the SHA-256 digest of the downloaded file.
    private func downloadFile(from url: URL, to destination: URL,
                              onProgress: @Sendable (UpdateStage) -> Void) async throws -> String {
        let (asyncBytes, response) = try await URLSession.shared.bytes(for: URLRequest(url: url))

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw UpdateError.downloadFailed
        }

        let totalBytes = httpResponse.expectedContentLength
        let maxBytes: Int64 = 250 * 1024 * 1024
        if totalBytes > maxBytes {
            throw UpdateError.downloadTooLarge
        }
        var downloadedBytes: Int64 = 0
        FileManager.default.createFile(atPath: destination.path, contents: nil)
        guard let file = try? FileHandle(forWritingTo: destination) else {
            throw UpdateError.downloadFailed
        }
        defer { try? file.close() }

        var hasher = SHA256()
        var buffer = Data()
        buffer.reserveCapacity(64 * 1024)

        for try await byte in asyncBytes {
            try Task.checkCancellation()
            buffer.append(byte)
            downloadedBytes += 1
            if downloadedBytes > maxBytes {
                throw UpdateError.downloadTooLarge
            }

            if buffer.count >= 64 * 1024 {
                try file.write(contentsOf: buffer)
                hasher.update(data: buffer)
                buffer.removeAll(keepingCapacity: true)
            }

            // Report progress every 64KB
            if downloadedBytes % (64 * 1024) == 0 {
                let progress = totalBytes > 0 ? Double(downloadedBytes) / Double(totalBytes) : -1
                onProgress(.downloading(progress: progress))
            }
        }

        if !buffer.isEmpty {
            try file.write(contentsOf: buffer)
            hasher.update(data: buffer)
        }
        onProgress(.downloading(progress: 1.0))
        appLog("[Update] Downloaded \(downloadedBytes) bytes")
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func downloadChecksum(from url: URL) async throws -> String {
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode),
              data.count < 4096,
              let text = String(data: data, encoding: .utf8) else {
            throw UpdateError.checksumDownloadFailed
        }
        guard let checksum = text
            .split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" })
            .first(where: { $0.count == 64 && $0.allSatisfy(\.isHexDigit) }) else {
            throw UpdateError.invalidChecksum
        }
        return String(checksum)
    }

    private func verifyBundle(at appPath: String, expectedVersion: String) throws {
        guard QuarantineHelper.verifySignature(at: appPath) else {
            throw UpdateError.signatureVerificationFailed
        }
        let infoURL = URL(fileURLWithPath: appPath)
            .appendingPathComponent("Contents")
            .appendingPathComponent("Info.plist")
        guard let info = NSDictionary(contentsOf: infoURL) as? [String: Any],
              info["CFBundleIdentifier"] as? String == Bundle.main.bundleIdentifier,
              info["CFBundleExecutable"] as? String == Bundle.main.infoDictionary?["CFBundleExecutable"] as? String,
              info["CFBundleShortVersionString"] as? String == expectedVersion else {
            throw UpdateError.bundleVerificationFailed
        }

        let expectedTeam = QuarantineHelper.teamIdentifier(at: Bundle.main.bundlePath)
        let actualTeam = QuarantineHelper.teamIdentifier(at: appPath)
        if let expectedTeam, expectedTeam != actualTeam {
            throw UpdateError.bundleVerificationFailed
        }
    }

    /// Run an external process and throw on failure
    @discardableResult
    private func runProcess(_ path: String, arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

        if process.terminationStatus != 0 {
            throw UpdateError.processFailed(path, process.terminationStatus, output)
        }
        return output
    }
}

// MARK: - Errors

enum UpdateError: LocalizedError {
    case noAppInZip
    case downloadFailed
    case downloadTooLarge
    case missingChecksum
    case checksumDownloadFailed
    case invalidChecksum
    case checksumMismatch
    case signatureVerificationFailed
    case bundleVerificationFailed
    case installFailed(String)
    case processFailed(String, Int32, String)

    var errorDescription: String? {
        switch self {
        case .noAppInZip:
            return "更新包中未找到 .app 文件"
        case .downloadFailed:
            return "下载更新失败"
        case .downloadTooLarge:
            return "更新包过大，已中止"
        case .missingChecksum:
            return "更新缺少 SHA-256 校验文件"
        case .checksumDownloadFailed:
            return "下载更新校验文件失败"
        case .invalidChecksum:
            return "更新校验文件格式无效"
        case .checksumMismatch:
            return "更新包 SHA-256 校验失败"
        case .signatureVerificationFailed:
            return "更新包签名校验失败"
        case .bundleVerificationFailed:
            return "更新包应用信息校验失败"
        case .installFailed(let reason):
            return "安装更新失败: \(reason)"
        case .processFailed(let cmd, let code, let output):
            return "命令执行失败: \(cmd) (code \(code)): \(output.prefix(200))"
        }
    }
}
