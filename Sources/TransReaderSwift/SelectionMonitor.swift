import Foundation
import ApplicationServices
import AppKit
import CoreGraphics

actor SelectionMonitor {
    private let callback: @Sendable (String, Bool, String, String) -> Void  // text, isWord, sourceApp, sourceUrl
    private let onSuppress: @Sendable (String) -> Void  // cancel translation for this text
    private var pollTask: Task<Void, Never>?
    private var isRunning = false

    private var pollInterval: TimeInterval
    private var includedApps: [String]
    private var excludedUrls: [String]

    private var firedText = ""
    private var lastFocusedApp = ""
    private var previousMouseDown = false
    private var appJustSwitched = false

    // Gesture-based mouse tracking (drag distance + double-click)
    private let dragDistanceThreshold: CGFloat = 5.0
    private let doubleClickThreshold: TimeInterval = 0.5

    // Cmd+C suppression: if user copies (Cmd+C) the same text that was just
    // selected and fired for translation, cancel the translation. No time window
    // — suppression stays active until (a) user copies that text, (b) a new
    // selection fires, or (c) a different clipboard change occurs.
    private var pendingText: String?
    private var pendingClipboardCount = 0
    // Extra guard: text that was just Cmd+C-suppressed. Blocks re-fire even if
    // firedText is bypassed by AX whitespace jitter. Cleared on next gesture.
    private var suppressedText: String?

    // Word vs sentence pattern
    private let wordPattern = try! NSRegularExpression(pattern: "^[a-zA-Z][a-zA-Z'-]{0,38}$")

    init(
        callback: @escaping @Sendable (String, Bool, String, String) -> Void,
        onSuppress: @escaping @Sendable (String) -> Void = { _ in },
        pollInterval: TimeInterval = 1.0,
        includedApps: [String] = [],
        excludedUrls: [String] = []
    ) {
        self.callback = callback
        self.onSuppress = onSuppress
        self.pollInterval = pollInterval
        self.includedApps = includedApps
        self.excludedUrls = excludedUrls
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        appLog("[Monitor] Started (interval: \(pollInterval)s, apps: \(includedApps.count), urls: \(excludedUrls.count))")

        startMouseWatcher()

        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self = self else { break }
                guard await self.isRunning else { break }

                await self.poll()

                try? await Task.sleep(nanoseconds: UInt64(await self.pollInterval * 1_000_000_000))
            }
        }
    }

    func stop() {
        isRunning = false
        pollTask?.cancel()
        pollTask = nil
        mouseWatcherTask?.cancel()
        mouseWatcherTask = nil
    }

    func updateInterval(_ interval: TimeInterval) {
        self.pollInterval = max(0.05, min(interval, 10.0))
    }

    func updateIncludedApps(_ apps: [String]) {
        self.includedApps = apps
    }

    func updateExcludedUrls(_ urls: [String]) {
        self.excludedUrls = urls
    }

    // MARK: - Fast Mouse Watcher (20ms, like Python)

    private var mouseWatcherTask: Task<Void, Never>?
    private var gestureMouseReleased = false  // set by fast watcher, consumed by poll

    private func startMouseWatcher() {
        mouseWatcherTask = Task { [weak self] in
            var prevDown = false
            var downLocation: CGPoint = .zero
            var lastRelease: TimeInterval = 0
            let dragDistance: CGFloat = 5.0
            let dblClickThreshold: TimeInterval = 0.5

            while !Task.isCancelled {
                guard let self = self, await self.isRunning else { break }

                // Fast-tick suppression check so Cmd+C cancellation is near-instant
                // (rather than waiting for the slow poll loop, which is up to 1s).
                await self.checkPendingSuppression()

                let down = CGEventSource.buttonState(.combinedSessionState, button: .left)

                if down && !prevDown {
                    // Capture mouse location at press time
                    downLocation = CGEvent(source: nil)?.location ?? .zero
                }
                if prevDown && !down {
                    let now = ProcessInfo.processInfo.systemUptime
                    let upLocation = CGEvent(source: nil)?.location ?? .zero
                    let dx = upLocation.x - downLocation.x
                    let dy = upLocation.y - downLocation.y
                    let distance = sqrt(dx * dx + dy * dy)
                    let isDrag = distance >= dragDistance
                    let isDoubleClick = (now - lastRelease) <= dblClickThreshold
                    // Only count as a "selection gesture" if user actually dragged
                    // (picked text) or double-clicked (selected word). A mere
                    // long-press on a button is not a selection.
                    if isDrag || isDoubleClick {
                        await self.setGestureMouseReleased()
                    }
                    lastRelease = now
                }
                prevDown = down
                try? await Task.sleep(nanoseconds: 20_000_000) // 20ms
            }
        }
    }

    private func setGestureMouseReleased() {
        gestureMouseReleased = true
        firedText = ""
        suppressedText = nil
    }

    private func consumeGestureMouseReleased() -> Bool {
        if gestureMouseReleased {
            gestureMouseReleased = false
            return true
        }
        return false
    }

    private func poll() {
        // Check pending Cmd+C suppression window
        checkPendingSuppression()

        // Don't read while mouse is held (user still selecting)
        guard !isMouseDown() else { return }

        // Consume gesture flag from fast mouse watcher
        let mouseJustReleased = consumeGestureMouseReleased()

        if let (text, sourceApp, sourceUrl) = getSelectedText(mouseJustReleased: mouseJustReleased) {
            handleText(text, sourceApp: sourceApp, sourceUrl: sourceUrl)
        }
    }

    private func isMouseDown() -> Bool {
        return CGEventSource.buttonState(.combinedSessionState, button: .left)
    }

    // MARK: - Cmd+C Suppression

    private func checkPendingSuppression() {
        guard let pending = pendingText else { return }

        let currentCount = NSPasteboard.general.changeCount
        guard currentCount != pendingClipboardCount else { return }

        let clipText = NSPasteboard.general.string(forType: .string) ?? ""
        appLog("[Monitor] Suppression: clipboard changed \(pendingClipboardCount)→\(currentCount), pending=\(appLogTextSummary(pending)), clip=\(appLogTextSummary(clipText))")

        suppressedText = pending
        onSuppress(pending)

        pendingText = nil
        pendingClipboardCount = currentCount
    }

    private func handleText(_ text: String, sourceApp: String, sourceUrl: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Skip empty, too short, already fired, or just suppressed by Cmd+C
        guard !trimmed.isEmpty,
              trimmed.count >= 2,
              trimmed != firedText,
              trimmed != suppressedText else {
            return
        }

        // Still selecting — skip
        guard !isMouseDown() else {
            return
        }

        // Skip URLs
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") ||
           trimmed.hasPrefix("ftp://") || trimmed.hasPrefix("www.") {
            return
        }

        // English detection: >50% ASCII letters
        let asciiLetters = trimmed.filter { $0.isASCII && $0.isLetter }.count
        let ratio = Double(asciiLetters) / Double(max(trimmed.count, 1))
        guard ratio > 0.5 else {
            return
        }

        // Determine if it's a single word
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        let isWord = wordPattern.firstMatch(in: trimmed, range: range) != nil

        // Mark as fired immediately (Python does this)
        firedText = trimmed

        // Fire callback immediately, then arm Cmd+C suppression:
        // if user later copies this exact text, cancel the translation.
        appLog("[Monitor] Firing: \(isWord ? "word" : "text") (\(appLogTextSummary(trimmed))) from \(sourceApp)")
        callback(trimmed, isWord, sourceApp, sourceUrl)

        pendingText = trimmed
        pendingClipboardCount = NSPasteboard.general.changeCount
        appLog("[Monitor] Suppression armed: clipCount=\(pendingClipboardCount), text=\(appLogTextSummary(trimmed))")
    }

    private func getSelectedText(mouseJustReleased: Bool) -> (String, String, String)? {
        let system = AXUIElementCreateSystemWide()

        // Get focused application — try AX first, fallback to NSWorkspace
        var focusedAppEl: AXUIElement
        var appName = ""
        var appNameAlt = ""  // localizedName from NSWorkspace as second source

        var focusedAppRef: CFTypeRef?
        let focusedAppErr = AXUIElementCopyAttributeValue(
            system,
            kAXFocusedApplicationAttribute as CFString,
            &focusedAppRef
        )

        if focusedAppErr == .success, let focusedApp = focusedAppRef {
            focusedAppEl = focusedApp as! AXUIElement

            // Get app name from AXTitle
            var appTitleRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(focusedAppEl, "AXTitle" as CFString, &appTitleRef) == .success,
               let title = appTitleRef as? String {
                appName = title
            }

            // Also get localizedName via NSWorkspace for reliable matching
            if let frontApp = NSWorkspace.shared.frontmostApplication {
                appNameAlt = frontApp.localizedName ?? ""
            }
        } else {
            // Fallback: NSWorkspace.frontmostApplication → AXUIElementCreateApplication(pid)
            guard let frontApp = NSWorkspace.shared.frontmostApplication else {
                if lastFocusedApp != "__ax_err__" {
                    appLog("[Monitor] Cannot get focused app via AX or NSWorkspace")
                    lastFocusedApp = "__ax_err__"
                }
                return nil
            }
            let pid = frontApp.processIdentifier
            focusedAppEl = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(focusedAppEl, 3.0)
            appName = frontApp.localizedName ?? ""
            appNameAlt = appName
            if lastFocusedApp == "__ax_err__" {
                appLog("[Monitor] Using NSWorkspace fallback for '\(appName)' (pid=\(pid))")
            }
        }

        // Use alt name if primary is empty
        if appName.isEmpty && !appNameAlt.isEmpty {
            appName = appNameAlt
        }

        // Filter: whitelist with dual-name matching (like Python)
        if !includedApps.isEmpty {
            let namesToCheck = [appName, appNameAlt].filter { !$0.isEmpty }
            let isIncluded = includedApps.contains { keyword in
                namesToCheck.contains { name in
                    if keyword.count < 6 {
                        return name.localizedCaseInsensitiveCompare(keyword) == .orderedSame
                    } else {
                        return name.localizedCaseInsensitiveContains(keyword)
                    }
                }
            }
            if !isIncluded {
                if appName != lastFocusedApp {
                    appLog("[Monitor] App '\(appName)' (alt: '\(appNameAlt)') not in whitelist, skipping")
                    lastFocusedApp = appName
                    appJustSwitched = true
                    // Refresh suppression baseline — clipboard may change during app switch
                    // (e.g., TransReader window appearing), don't let that consume pending.
                    if pendingText != nil {
                        pendingClipboardCount = NSPasteboard.general.changeCount
                    }
                }
                return nil
            }
        }

        // App switch detection — skip stale selections
        if appName != lastFocusedApp {
            appLog("[Monitor] App switched to '\(appName)' (included: ✓)")
            lastFocusedApp = appName
            appJustSwitched = true
            // Refresh suppression baseline — clipboard may change during app switch
            if pendingText != nil {
                pendingClipboardCount = NSPasteboard.general.changeCount
            }
            return nil
        }

        // After app switch: snapshot current selection as baseline so we don't
        // translate text that was already selected before the switch
        if appJustSwitched {
            appJustSwitched = false
            // Refresh suppression baseline after switch settles
            if pendingText != nil {
                pendingClipboardCount = NSPasteboard.general.changeCount
            }
            // Read current selection and store as firedText (baseline)
            if let sel = getAXSelectedText(from: focusedAppEl) {
                let trimmed = sel.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    firedText = trimmed
                    appLog("[Monitor] Baseline selection on app switch: \(appLogTextSummary(trimmed))")
                }
            }
            return nil
        }

        // Detect browser type
        let browserType = detectBrowserType(appName)

        // Get browser URL for source tracking and filtering
        var sourceUrl = ""
        if let browser = browserType {
            if let url = getBrowserURL(appName: appName, browserType: browser) {
                sourceUrl = url
                // Filter excluded URLs
                if !excludedUrls.isEmpty {
                    if let host = URL(string: url)?.host {
                        for pattern in excludedUrls {
                            if host.contains(pattern) {
                                return nil
                            }
                        }
                    }
                }
            }
        }

        // Wait for modifier keys to release (important for Hyper Key users)
        let modifierFlags = CGEventSource.flagsState(.combinedSessionState)
        let activeModifiers: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift]
        if modifierFlags.intersection(activeModifiers) != [] {
            return nil
        }

        // Get focused UI element
        var focusedElRef: CFTypeRef?
        let focusedElErr = AXUIElementCopyAttributeValue(
            focusedAppEl,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElRef
        )

        guard focusedElErr == .success,
              let focusedEl = focusedElRef else {
            // Cannot get focused element (Chrome often returns -25212)
            // For non-Safari browsers, try Cmd+C fallback
            let useCmdC = browserType != nil && browserType != "safari"

            // Try app-level AXSelectedText first
            if let text = getAXSelectedText(from: focusedAppEl), !text.isEmpty {
                return (text, appName, sourceUrl)
            }

            // Cmd+C fallback on mouse release
            if mouseJustReleased && useCmdC {
                if let text = simulateCmdCAndGetText() {
                    appLog("[Monitor] Got text via Cmd+C fallback (no focused element)")
                    return (text, appName, sourceUrl)
                }
            }
            return nil
        }

        let focusedElement = focusedEl as! AXUIElement

        // Get element role
        var roleRef: CFTypeRef?
        let roleErr = AXUIElementCopyAttributeValue(
            focusedElement,
            "AXRole" as CFString,
            &roleRef
        )

        let role = (roleErr == .success && roleRef != nil) ? (roleRef as! String) : "unknown"

        // Skip non-text UI elements
        let skipRoles: Set<String> = [
            "AXButton", "AXPopUpButton",
            "AXMenuItem", "AXMenu",
            "AXMenuBar", "AXMenuBarItem",
            "AXToolbar",
            "AXCheckBox", "AXRadioButton",
            "AXSlider", "AXIncrementor",
            "AXTabGroup", "AXTab",
            "AXTextField", "AXComboBox",
            "AXTextArea", "AXSearchField",
        ]
        if skipRoles.contains(role) {
            return nil
        }

        // Tier 1: Focused element AXSelectedText
        if let text = getAXSelectedText(from: focusedElement), !text.isEmpty {
            return (text, appName, sourceUrl)
        }

        // Tier 2: Application-level AXSelectedText
        if let text = getAXSelectedText(from: focusedAppEl), !text.isEmpty {
            return (text, appName, sourceUrl)
        }

        // Tier 3: WebArea inner element (Electron/WebView apps)
        if role == "AXWebArea" || role == "AXGroup" || role == "AXScrollArea" {
            // Try focused child element
            var innerElRef: CFTypeRef?
            let innerElErr = AXUIElementCopyAttributeValue(
                focusedElement,
                kAXFocusedUIElementAttribute as CFString,
                &innerElRef
            )

            if innerElErr == .success, let innerEl = innerElRef {
                let innerElement = innerEl as! AXUIElement

                // Tier 4: Inner element AXSelectedText
                if let text = getAXSelectedText(from: innerElement), !text.isEmpty {
                    return (text, appName, sourceUrl)
                }

                // Tier 5: Inner element AXValue
                if let text = getAXValue(from: innerElement), !text.isEmpty {
                    return (text, appName, sourceUrl)
                }
            }

            // Tier 6: Simulate Cmd+C on mouse release
            if mouseJustReleased {
                if let text = simulateCmdCAndGetText() {
                    return (text, appName, sourceUrl)
                }
            }
        }

        return nil
    }

    // MARK: - AX Helpers

    private func getAXSelectedText(from element: AXUIElement) -> String? {
        var ref: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &ref)
        guard err == .success, let text = ref as? String else { return nil }
        return text
    }

    private func getAXValue(from element: AXUIElement) -> String? {
        var ref: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &ref)
        guard err == .success, let text = ref as? String else { return nil }
        return text
    }

    private func detectBrowserType(_ appName: String) -> String? {
        let safariKeywords = ["Safari"]
        let chromiumKeywords = ["Chrome", "Chromium", "Arc", "Edge", "Brave", "Opera", "Vivaldi"]
        let firefoxKeywords = ["Firefox", "Nightly"]

        for keyword in safariKeywords {
            if appName.contains(keyword) { return "safari" }
        }
        for keyword in chromiumKeywords {
            if appName.contains(keyword) { return "chromium" }
        }
        for keyword in firefoxKeywords {
            if appName.contains(keyword) { return "firefox" }
        }
        return nil
    }

    private func getBrowserURL(appName: String, browserType: String) -> String? {
        // Firefox doesn't expose tabs via AppleScript
        if browserType == "firefox" {
            return ""
        }

        let escaped = appName.replacingOccurrences(of: "\"", with: "\\\"")
        let script: String

        if browserType == "safari" {
            script = "tell application \"\(escaped)\" to get URL of current tab of front window"
        } else {
            script = "tell application \"\(escaped)\" to get URL of active tab of front window"
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else { return nil }

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }

    private func simulateCmdCAndGetText() -> String? {
        let beforeCount = NSPasteboard.general.changeCount
        let beforeText = NSPasteboard.general.string(forType: .string)
        simulateCmdC()
        Thread.sleep(forTimeInterval: 0.1)  // 100ms wait like Python
        let afterCount = NSPasteboard.general.changeCount

        // Always update the pending baseline so our own simulation doesn't
        // false-trigger checkPendingSuppression on the next mouseWatcher tick.
        if afterCount != beforeCount {
            pendingClipboardCount = afterCount
        }

        // No clipboard write at all → nothing was selected
        guard afterCount != beforeCount else {
            return nil
        }

        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else {
            return nil
        }

        // Second safety: if Cmd+C "wrote" the same content that was already there,
        // the app had nothing new to copy — treat as no selection. This catches
        // Chrome's no-op writes on button clicks that still bump changeCount.
        if text == beforeText {
            return nil
        }

        return text
    }

    private func simulateCmdC() {
        let keyCode: CGKeyCode = 8

        guard let eventDown = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true),
              let eventUp = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false) else {
            return
        }

        eventDown.flags = .maskCommand
        eventUp.flags = .maskCommand

        eventDown.post(tap: .cghidEventTap)
        eventUp.post(tap: .cghidEventTap)
    }

    // MARK: - Writing Assistance: Read selected text from focused input field

    static func getSelectedTextFromFocusedField() -> (text: String, isFullValue: Bool)? {
        let system = AXUIElementCreateSystemWide()

        var focusedAppRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedApplicationAttribute as CFString, &focusedAppRef) == .success,
              let focusedApp = focusedAppRef else {
            return nil
        }

        let focusedAppEl = focusedApp as! AXUIElement

        var focusedElRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(focusedAppEl, kAXFocusedUIElementAttribute as CFString, &focusedElRef) == .success,
              let focusedEl = focusedElRef else {
            return nil
        }

        let element = focusedEl as! AXUIElement

        // Wait for modifier keys to release (up to 2 seconds)
        for _ in 0..<40 {
            let flags = CGEventSource.flagsState(.combinedSessionState)
            let active: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift]
            if flags.intersection(active) == [] { break }
            Thread.sleep(forTimeInterval: 0.05)
        }

        // Try selected text first (3 attempts with retry)
        for _ in 0..<3 {
            var selectedRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selectedRef) == .success,
               let selected = selectedRef as? String, !selected.isEmpty {
                return (selected, false)
            }
            Thread.sleep(forTimeInterval: 0.05)
        }

        // Try full value
        var valueRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef) == .success,
           let value = valueRef as? String, !value.isEmpty {
            return (value, true)
        }

        // Try app-level selected text
        var appSelRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(focusedAppEl, kAXSelectedTextAttribute as CFString, &appSelRef) == .success,
           let appSel = appSelRef as? String, !appSel.isEmpty {
            return (appSel, false)
        }

        // Fallback: Cmd+C
        let beforeCount = NSPasteboard.general.changeCount

        let keyCode: CGKeyCode = 8
        if let eventDown = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true),
           let eventUp = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false) {
            eventDown.flags = .maskCommand
            eventUp.flags = .maskCommand
            eventDown.post(tap: .cghidEventTap)
            eventUp.post(tap: .cghidEventTap)
        }

        Thread.sleep(forTimeInterval: 0.1)

        if NSPasteboard.general.changeCount != beforeCount,
           let text = NSPasteboard.general.string(forType: .string), !text.isEmpty {
            return (text, false)
        }

        return nil
    }

    // MARK: - Writing Assistance: Type text into focused field

    /// Type text via CGEvent with Character-boundary safe chunking.
    /// Splits on newlines and simulates Return key for each `\n`.
    static func typeText(_ text: String, delayPerChunk: TimeInterval = 0.01) {
        // Split on newlines — type text segments, simulate Return for \n
        let segments = text.components(separatedBy: "\n")
        for (i, segment) in segments.enumerated() {
            if !segment.isEmpty {
                typeTextSegment(segment, delay: delayPerChunk)
            }
            // Simulate Return key for newlines (except after last segment)
            if i < segments.count - 1 {
                simulateReturnKey()
                Thread.sleep(forTimeInterval: delayPerChunk)
            }
        }
    }

    /// Type a segment (no newlines) using Character-boundary safe UTF-16 chunking.
    private static func typeTextSegment(_ text: String, delay: TimeInterval) {
        let maxUTF16PerChunk = 20  // CGEvent API limit
        var chunk: [UniChar] = []
        chunk.reserveCapacity(maxUTF16PerChunk)

        for char in text {
            let charUTF16 = Array(char.utf16)
            // If adding this character would exceed the limit, flush current chunk first
            if chunk.count + charUTF16.count > maxUTF16PerChunk && !chunk.isEmpty {
                postUnicodeChunk(chunk)
                Thread.sleep(forTimeInterval: delay)
                chunk.removeAll(keepingCapacity: true)
            }
            chunk.append(contentsOf: charUTF16)
        }

        // Flush remaining
        if !chunk.isEmpty {
            postUnicodeChunk(chunk)
            Thread.sleep(forTimeInterval: delay)
        }
    }

    private static func postUnicodeChunk(_ chars: [UniChar]) {
        guard let eventDown = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true),
              let eventUp = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false) else {
            return
        }

        chars.withUnsafeBufferPointer { buffer in
            eventDown.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: buffer.baseAddress!)
            eventUp.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: buffer.baseAddress!)
        }

        eventDown.post(tap: .cghidEventTap)
        eventUp.post(tap: .cghidEventTap)
    }

    private static func simulateReturnKey() {
        let keyCode: CGKeyCode = 36 // Return key
        guard let eventDown = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true),
              let eventUp = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false) else {
            return
        }
        eventDown.post(tap: .cghidEventTap)
        eventUp.post(tap: .cghidEventTap)
    }

    // MARK: - Writing Assistance: Paste text via Cmd+V (with clipboard save/restore)

    static func pasteText(_ text: String) {
        let pasteboard = NSPasteboard.general

        // Save current clipboard content
        let savedString = pasteboard.string(forType: .string)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        let keyCode: CGKeyCode = 9 // V key
        guard let eventDown = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true),
              let eventUp = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false) else {
            return
        }

        eventDown.flags = .maskCommand
        eventUp.flags = .maskCommand

        eventDown.post(tap: .cghidEventTap)
        eventUp.post(tap: .cghidEventTap)

        // Restore clipboard after a delay to let paste complete
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            pasteboard.clearContents()
            if let saved = savedString {
                pasteboard.setString(saved, forType: .string)
            }
        }
    }
}
