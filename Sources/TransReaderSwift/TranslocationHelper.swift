import Foundation
import AppKit

/// Detects macOS App Translocation and provides install-to-Applications logic.
///
/// When users open an ad-hoc signed app directly from Downloads (or other
/// quarantined locations), macOS Gatekeeper mounts it at a random read-only
/// path under `/private/var/folders/.../AppTranslocation/<UUID>/d/`. This
/// prevents in-place updates and limits bundle modifications.
enum TranslocationHelper {

    /// Whether the current bundle is running from an App Translocation path.
    static var isTranslocated: Bool {
        guard Updater.isBundle else { return false }
        return Bundle.main.bundlePath.contains("/AppTranslocation/")
    }

    /// The correct install path: `/Applications/<app>` when translocated,
    /// otherwise the current bundle path.
    static func installPath() -> String {
        if isTranslocated {
            let appName = (Bundle.main.bundlePath as NSString).lastPathComponent
            return "/Applications/\(appName)"
        }
        return Bundle.main.bundlePath
    }

    /// Copy the current bundle to `/Applications/` and relaunch from there.
    ///
    /// Flow: ditto copy → clear quarantine xattr → launch from new path → exit.
    static func installToApplicationsAndRelaunch() async throws {
        let sourcePath = Bundle.main.bundlePath
        let targetPath = installPath()
        let targetURL = URL(fileURLWithPath: targetPath)
        let backupPath = targetPath + ".bak"
        let backupURL = URL(fileURLWithPath: backupPath)

        appLog("[Translocation] Installing from \(sourcePath) to \(targetPath)")

        // Remove stale backup if any
        try? FileManager.default.removeItem(at: backupURL)

        do {
            // Backup existing app at target (if any)
            if FileManager.default.fileExists(atPath: targetPath) {
                try FileManager.default.moveItem(at: targetURL, to: backupURL)
            }

            // ditto preserves code signature, symlinks, and xattrs
            try runProcess("/usr/bin/ditto", arguments: [sourcePath, targetPath])

            // Clear quarantine xattr so the installed copy won't be translocated
            QuarantineHelper.removeQuarantine(at: targetPath)

            // Remove backup on success
            try? FileManager.default.removeItem(at: backupURL)

            appLog("[Translocation] Install complete, relaunching from \(targetPath)")

        } catch {
            // Rollback: restore backup if install failed
            appLog("[Translocation] Install failed, rolling back: \(error.localizedDescription)")
            if FileManager.default.fileExists(atPath: backupPath) {
                try? FileManager.default.removeItem(atPath: targetPath)
                try? FileManager.default.moveItem(atPath: backupPath, toPath: targetPath)
            }
            throw TranslocationError.installFailed(error.localizedDescription)
        }

        // Relaunch from the new location
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        do {
            try await NSWorkspace.shared.openApplication(at: targetURL, configuration: config)
        } catch {
            throw TranslocationError.relaunchFailed(error.localizedDescription)
        }
        exit(0)
    }

    // MARK: - Helpers

    @discardableResult
    private static func runProcess(_ path: String, arguments: [String]) throws -> String {
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
            throw TranslocationError.processFailed(path, process.terminationStatus, output)
        }
        return output
    }
}

// MARK: - Errors

enum TranslocationError: LocalizedError {
    case installFailed(String)
    case relaunchFailed(String)
    case processFailed(String, Int32, String)

    var errorDescription: String? {
        switch self {
        case .installFailed(let reason):
            return "安装失败: \(reason)"
        case .relaunchFailed(let reason):
            return "重启失败: \(reason)。请手动打开 /Applications/ 中的 TransReader。"
        case .processFailed(let cmd, let code, let output):
            return "命令执行失败: \(cmd) (code \(code)): \(output.prefix(200))"
        }
    }
}
