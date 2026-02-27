import Foundation
import ApplicationServices
import AppKit
import CoreGraphics

actor SelectionMonitor {
    private let callback: @Sendable (String, Bool) -> Void  // text, isWord
    private var pollTask: Task<Void, Never>?
    private var isRunning = false
    
    private var pollInterval: TimeInterval
    private var excludedApps: [String]
    private var excludedUrls: [String]
    private var clipboardTranslateEnabled: Bool
    
    private var firedText = ""
    private var lastFocusedApp = ""
    private var lastClipboardChangeCount = 0
    private var previousMouseDown = false
    
    // Word vs sentence pattern: single word with optional hyphens/apostrophes
    private let wordPattern = try! NSRegularExpression(pattern: "^[a-zA-Z][a-zA-Z'-]{0,38}$")
    
    init(
        callback: @escaping @Sendable (String, Bool) -> Void,
        pollInterval: TimeInterval = 1.0,
        excludedApps: [String] = [],
        excludedUrls: [String] = [],
        clipboardTranslateEnabled: Bool = false
    ) {
        self.callback = callback
        self.pollInterval = pollInterval
        self.excludedApps = excludedApps
        self.excludedUrls = excludedUrls
        self.clipboardTranslateEnabled = clipboardTranslateEnabled
        self.lastClipboardChangeCount = NSPasteboard.general.changeCount
    }
    
    func start() {
        guard !isRunning else { return }
        isRunning = true
        
        pollTask = Task { [weak self] in
            while true {
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
    }
    
    func updateInterval(_ interval: TimeInterval) {
        self.pollInterval = max(0.05, min(interval, 10.0))
    }
    
    func updateExcludedApps(_ apps: [String]) {
        self.excludedApps = apps
    }
    
    func updateExcludedUrls(_ urls: [String]) {
        self.excludedUrls = urls
    }
    
    func updateClipboardTranslate(_ enabled: Bool) {
        self.clipboardTranslateEnabled = enabled
    }
    
    private func poll() {
        // Detect mouse release
        let mouseDown = isMouseDown()
        let mouseJustReleased = previousMouseDown && !mouseDown
        previousMouseDown = mouseDown
        
        if let text = getSelectedText(mouseJustReleased: mouseJustReleased) {
            handleText(text)
        }
    }
    
    private func isMouseDown() -> Bool {
        return CGEventSource.buttonState(.combinedSessionState, button: .left)
    }
    
    private func handleText(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Skip empty, too short, or already fired
        guard !trimmed.isEmpty,
              trimmed.count >= 2,
              trimmed != firedText else {
            return
        }
        
        // Still selecting — skip
        guard !isMouseDown() else {
            return
        }
        
        // English detection: >50% ASCII letters
        let asciiLetters = trimmed.filter { $0.isASCII && $0.isLetter }.count
        let ratio = Double(asciiLetters) / Double(max(trimmed.count, 1))
        guard ratio > 0.5 else {
            return
        }
        
        firedText = trimmed
        
        // Determine if it's a single word
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        let isWord = wordPattern.firstMatch(in: trimmed, range: range) != nil
        
        callback(trimmed, isWord)
    }
    
    private func getSelectedText(mouseJustReleased: Bool) -> String? {
        let system = AXUIElementCreateSystemWide()
        
        // Get focused application
        var focusedAppRef: CFTypeRef?
        let focusedAppErr = AXUIElementCopyAttributeValue(
            system,
            kAXFocusedApplicationAttribute as CFString,
            &focusedAppRef
        )
        
        guard focusedAppErr == .success,
              let focusedApp = focusedAppRef else {
            return nil
        }
        
        let focusedAppEl = focusedApp as! AXUIElement
        
        // Get app name
        var appTitleRef: CFTypeRef?
        let appTitleErr = AXUIElementCopyAttributeValue(
            focusedAppEl,
            "AXTitle" as CFString,
            &appTitleRef
        )
        
        let appName = (appTitleErr == .success && appTitleRef != nil) ? (appTitleRef as! String) : ""
        
        // Filter excluded apps
        for excluded in excludedApps {
            if appName.contains(excluded) {
                if appName != lastFocusedApp {
                    lastFocusedApp = appName
                    lastClipboardChangeCount = NSPasteboard.general.changeCount
                }
                return nil
            }
        }
        
        // When app changes, reset clipboard baseline
        if appName != lastFocusedApp {
            lastFocusedApp = appName
            lastClipboardChangeCount = NSPasteboard.general.changeCount
            return nil
        }
        
        // Detect browser type
        let browserType = detectBrowserType(appName)
        
        // Filter excluded URLs (for browsers)
        if !excludedUrls.isEmpty, let browser = browserType {
            if let url = getBrowserURL(appName: appName, browserType: browser) {
                if let host = URL(string: url)?.host {
                    for pattern in excludedUrls {
                        if host.contains(pattern) {
                            return nil
                        }
                    }
                }
            }
        }
        
        // Clipboard translate mode
        if clipboardTranslateEnabled {
            if let clipText = getClipboardIfChanged() {
                return clipText
            }
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
        
        // Skip single-line input fields
        if role == "AXTextField" || role == "AXComboBox" {
            return nil
        }
        
        // Get selected text
        var selectedRef: CFTypeRef?
        let selectedErr = AXUIElementCopyAttributeValue(
            focusedElement,
            kAXSelectedTextAttribute as CFString,
            &selectedRef
        )
        
        if selectedErr == .success, let selected = selectedRef as? String, !selected.isEmpty {
            return selected
        }
        
        // WebArea fallback (Electron/WebView apps)
        if role == "AXWebArea" {
            // 1. Try application-level selected text
            var appSelRef: CFTypeRef?
            let appSelErr = AXUIElementCopyAttributeValue(
                focusedAppEl,
                kAXSelectedTextAttribute as CFString,
                &appSelRef
            )
            
            if appSelErr == .success, let appSel = appSelRef as? String, !appSel.isEmpty {
                return appSel
            }
            
            // 2. Try focused child element
            var innerElRef: CFTypeRef?
            let innerElErr = AXUIElementCopyAttributeValue(
                focusedElement,
                kAXFocusedUIElementAttribute as CFString,
                &innerElRef
            )
            
            if innerElErr == .success, let innerEl = innerElRef {
                let innerElement = innerEl as! AXUIElement
                var innerSelRef: CFTypeRef?
                let innerSelErr = AXUIElementCopyAttributeValue(
                    innerElement,
                    kAXSelectedTextAttribute as CFString,
                    &innerSelRef
                )
                
                if innerSelErr == .success, let innerSel = innerSelRef as? String, !innerSel.isEmpty {
                    return innerSel
                }
            }
            
            // 3. Simulate Cmd+C on mouse release
            if mouseJustReleased {
                let beforeCount = NSPasteboard.general.changeCount
                simulateCmdC()
                Thread.sleep(forTimeInterval: 0.05)
                let afterCount = NSPasteboard.general.changeCount
                
                if afterCount != beforeCount {
                    lastClipboardChangeCount = afterCount
                    if let text = NSPasteboard.general.string(forType: .string), !text.isEmpty {
                        return text
                    }
                }
            }
        }
        
        return nil
    }
    
    private func getClipboardIfChanged() -> String? {
        let currentCount = NSPasteboard.general.changeCount
        guard currentCount != lastClipboardChangeCount else {
            return nil
        }
        
        lastClipboardChangeCount = currentCount
        return NSPasteboard.general.string(forType: .string)
    }
    
    private func detectBrowserType(_ appName: String) -> String? {
        let safariKeywords = ["Safari"]
        let chromiumKeywords = ["Chrome", "Chromium", "Arc", "Edge", "Brave", "Opera", "Vivaldi"]
        
        for keyword in safariKeywords {
            if appName.contains(keyword) {
                return "safari"
            }
        }
        
        for keyword in chromiumKeywords {
            if appName.contains(keyword) {
                return "chromium"
            }
        }
        
        return nil
    }
    
    private func getBrowserURL(appName: String, browserType: String) -> String? {
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
        
        do {
            try process.run()
            process.waitUntilExit()
            
            guard process.terminationStatus == 0 else {
                return nil
            }
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }
    
    private func simulateCmdC() {
        // Virtual key code for 'C' = 8
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
}
