import Foundation

/// Handles macOS quarantine xattr removal and code signature verification
/// after app installation (update or translocation install).
///
/// Design decision: **never re-sign by default**. `ditto` preserves the
/// original ad-hoc signature. Re-signing changes the signature hash, causing
/// macOS to revoke Accessibility permissions — the user would need to
/// re-authorize in System Settings.
enum QuarantineHelper {

    /// Recursively clear `com.apple.quarantine` xattr from an app bundle.
    /// Failure is non-fatal: logged but does not throw.
    static func removeQuarantine(at appPath: String) {
        do {
            try runProcess("/usr/bin/xattr", arguments: ["-cr", appPath])
            appLog("[Quarantine] Cleared quarantine xattr: \(appPath)")
        } catch {
            // Non-fatal — quarantine absence doesn't block already-installed apps
            appLog("[Quarantine] xattr clear failed (non-fatal): \(error.localizedDescription)")
        }
    }

    /// Verify the app's code signature integrity.
    /// Returns `true` if the signature is valid or the app is unsigned.
    static func verifySignature(at appPath: String) -> Bool {
        do {
            try runProcess("/usr/bin/codesign",
                           arguments: ["--verify", "--deep", "--strict", appPath])
            appLog("[Quarantine] Signature valid: \(appPath)")
            return true
        } catch {
            appLog("[Quarantine] Signature verification failed: \(error.localizedDescription)")
            return false
        }
    }

    /// Re-sign with ad-hoc signature only if the existing signature is corrupted.
    /// Under normal circumstances (ditto copy), this should NOT be called —
    /// re-signing invalidates the AX permission hash.
    static func resignIfNeeded(at appPath: String, entitlements: String? = nil) {
        guard !verifySignature(at: appPath) else { return }

        appLog("[Quarantine] Signature corrupted, performing ad-hoc re-sign (AX permissions will be lost)")

        var args = ["--force", "--deep", "--sign", "-"]
        if let entitlements {
            args += ["--entitlements", entitlements]
        }
        args.append(appPath)

        do {
            try runProcess("/usr/bin/codesign", arguments: args)
            appLog("[Quarantine] Re-signed successfully: \(appPath)")
        } catch {
            appLog("[Quarantine] Re-sign failed: \(error.localizedDescription)")
        }
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
            throw QuarantineError.processFailed(path, process.terminationStatus, output)
        }
        return output
    }
}

enum QuarantineError: LocalizedError {
    case processFailed(String, Int32, String)

    var errorDescription: String? {
        switch self {
        case .processFailed(let cmd, let code, let output):
            return "\(cmd) failed (code \(code)): \(output.prefix(200))"
        }
    }
}
