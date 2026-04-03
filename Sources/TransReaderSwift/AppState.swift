import Foundation
import SwiftUI
import ApplicationServices

// Global logger — writes to ~/.transreader/app.log + stderr
func appLog(_ msg: String) {
    let line = "[\(DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium))] \(msg)\n"
    let data = Data(line.utf8)
    // stderr (visible when running from terminal)
    FileHandle.standardError.write(data)
    // log file (always works)
    let logPath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".transreader").appendingPathComponent("app.log")
    if !FileManager.default.fileExists(atPath: logPath.path) {
        FileManager.default.createFile(atPath: logPath.path, contents: nil)
    }
    if let fh = FileHandle(forWritingAtPath: logPath.path) {
        fh.seekToEndOfFile()
        fh.write(data)
        fh.closeFile()
    }
}

@Observable
@MainActor
final class AppState {
    let configStore: ConfigStore
    let vocabStore: VocabStore
    let translator: Translator
    let ocrEngine: OCREngine
    let dictionaryService: DictionaryService
    let translationStore: TranslationStore
    let updater: Updater
    let notificationService: NotificationService

    private var selectionMonitor: SelectionMonitor?
    private var globalHotkeys: GlobalHotkeys?
    var monitorEnabled = false

    var translationHistory: [TranslationResult] = []
    var currentTranslation: TranslationResult?
    var isTranslating = false
    var translationQueue: [QueuedTask] = []
    var error: String?

    // Concurrent task management
    private var runningTasks: [UUID: Task<Void, Never>] = [:]
    private var recentDedupKeys: [String: Date] = [:]
    private let dedupWindow: TimeInterval = 5.0

    var windowPinned = false

    // Translocation state
    var isTranslocated: Bool = TranslocationHelper.isTranslocated
    var showTranslocationAlert = false

    // Update state
    var updateStage: UpdateStage?
    var pendingUpdate: UpdateInfo?
    var updateError: String?
    var relaunchCountdown: Int?
    private var relaunchTimer: Timer?
    private var updateTask: Task<Void, Never>?

    // Latency testing
    var latencyResults: [String: LatencyResult] = [:]
    var isTestingLatency = false

    // Writing assistance state
    var isEnhancing = false
    var enhanceProgress: String = ""
    private var enhanceTask: Task<Void, Never>?

    // Word lookup state
    var currentWordLookup: DictionaryEntry?
    var isLookingUpWord = false
    var showWordPopover = false

    // Long text confirmation
    var pendingLongText: String?
    var pendingLongTextSource: TranslationSource?
    var pendingLongTextSourceApp: String = ""
    var pendingLongTextSourceUrl: String = ""
    var showLongTextConfirm = false

    // Callbacks for hotkeys (set by view)
    var onCaptureTranslate: (() -> Void)?
    var onToggleWindow: (() -> Void)?
    var onTogglePin: (() -> Void)?
    var onEnhanceTranslate: (() -> Void)?
    var onPasteTranslate: (() -> Void)?
    var onShowWindowNoActivate: (() -> Void)?

    // MARK: - Window Management

    /// Show the main window without stealing focus from the current app.
    /// Uses NSApplication directly so it works from anywhere (not just SwiftUI views).
    func showWindowWithoutActivation() {
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "main" }) {
            window.orderFrontRegardless()
        } else {
            // Window not yet created — use the callback which has access to openWindow
            onShowWindowNoActivate?()
        }
    }

    init() {
        self.configStore = ConfigStore()
        self.vocabStore = VocabStore(path: configStore.config.vocabFile)
        self.translator = Translator(configStore: configStore)
        self.ocrEngine = OCREngine()
        self.dictionaryService = DictionaryService(configStore: configStore)
        self.translationStore = TranslationStore()
        self.updater = Updater()
        self.notificationService = NotificationService(configStore: configStore)

        // Initialize monitor with source-tracking callback
        let callback: @Sendable (String, Bool, String, String) -> Void = { [weak self] text, isWord, sourceApp, sourceUrl in
            Task { @MainActor in
                guard let self = self else { return }
                if isWord {
                    self.lookupWord(text)
                } else {
                    self.translateWithSource(text, source: .selection, sourceApp: sourceApp, sourceUrl: sourceUrl)
                }
                // Show window without stealing focus from the app being read
                self.showWindowWithoutActivation()
            }
        }

        self.selectionMonitor = SelectionMonitor(
            callback: callback,
            pollInterval: Double(configStore.config.monitorInterval) / 1000.0,
            includedApps: configStore.config.includedApps,
            excludedUrls: configStore.config.excludedUrls,
            clipboardTranslateEnabled: configStore.config.clipboardTranslateEnabled
        )

        // Check accessibility permission
        checkAccessibilityPermission()

        // Start if configured
        if configStore.config.monitorEnabled {
            Task {
                await startMonitor()
            }
        }

        // Background update check (bundle mode only)
        if Updater.isBundle {
            Task {
                await startupUpdateCheck()
            }
        }
    }

    // MARK: - Accessibility

    @discardableResult
    func checkAccessibilityPermission() -> Bool {
        let trusted = AXIsProcessTrusted()
        if !trusted {
            // Prompt user
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            AXIsProcessTrustedWithOptions(options)
            appLog("[AX] Accessibility: NOT granted — prompting user")
        } else {
            appLog("[AX] Accessibility: granted ✓")
        }
        return trusted
    }

    /// Call once from onAppear. Polls until permission granted, then restarts.
    func waitForAccessibilityAndRestart() {
        guard !AXIsProcessTrusted() else { return }
        Task { @MainActor in
            while !AXIsProcessTrusted() {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
            appLog("[AX] Permission granted! Restarting app...")
            let url = Bundle.main.bundleURL
            let config = NSWorkspace.OpenConfiguration()
            config.createsNewApplicationInstance = true
            try? await NSWorkspace.shared.openApplication(at: url, configuration: config)
            NSApp.terminate(nil)
        }
    }

    // MARK: - Hotkeys

    func setupHotkeys() {
        let callbacks: [HotkeyAction: () -> Void] = [
            .captureTranslate: { [weak self] in
                Task { @MainActor in self?.onCaptureTranslate?() }
            },
            .toggleWindow: { [weak self] in
                Task { @MainActor in self?.onToggleWindow?() }
            },
            .togglePin: { [weak self] in
                Task { @MainActor in self?.onTogglePin?() }
            },
            .toggleMonitor: { [weak self] in
                Task { @MainActor in self?.toggleMonitor() }
            },
            .enhanceTranslate: { [weak self] in
                Task { @MainActor in self?.onEnhanceTranslate?() }
            },
            .pasteTranslate: { [weak self] in
                Task { @MainActor in self?.onPasteTranslate?() }
            }
        ]

        self.globalHotkeys = GlobalHotkeys(
            shortcuts: configStore.config.shortcuts,
            callbacks: callbacks
        )

        Task {
            await globalHotkeys?.register()
        }
    }

    func updateHotkeys() {
        Task {
            await globalHotkeys?.updateShortcuts(configStore.config.shortcuts)
        }
    }

    // MARK: - Monitor

    func startMonitor() async {
        guard checkAccessibilityPermission() else {
            error = "请在系统设置中授予辅助功能权限，然后重试"
            return
        }
        guard let monitor = selectionMonitor else { return }
        await monitor.start()
        monitorEnabled = true
    }

    func stopMonitor() async {
        guard let monitor = selectionMonitor else { return }
        await monitor.stop()
        monitorEnabled = false
    }

    func toggleMonitor() {
        Task {
            if monitorEnabled {
                await stopMonitor()
                configStore.setMonitorEnabled(false)
            } else {
                await startMonitor()
                configStore.setMonitorEnabled(true)
            }
        }
    }

    func updateMonitorSettings() {
        Task {
            guard let monitor = selectionMonitor else { return }
            await monitor.updateInterval(Double(configStore.config.monitorInterval) / 1000.0)
            await monitor.updateIncludedApps(configStore.config.includedApps)
            await monitor.updateExcludedUrls(configStore.config.excludedUrls)
            await monitor.updateClipboardTranslate(configStore.config.clipboardTranslateEnabled)
        }
    }

    // MARK: - Translocation

    func handleTranslocationIfNeeded() {
        guard isTranslocated else { return }
        appLog("[Translocation] App is running from translocated path: \(Bundle.main.bundlePath)")
        showTranslocationAlert = true
    }

    func installToApplications() {
        Task {
            do {
                try await TranslocationHelper.installToApplicationsAndRelaunch()
            } catch {
                self.error = error.localizedDescription
                appLog("[Translocation] Failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Auto-Update

    private func startupUpdateCheck() async {
        do {
            let info = try await updater.checkForUpdate()
            if let info {
                pendingUpdate = info
                appLog("[Update] Update available: v\(info.version)")
            }
        } catch {
            // Silent failure on startup — don't bother the user
            appLog("[Update] Startup check failed: \(error.localizedDescription)")
        }
    }

    func checkForUpdate() {
        guard updateStage == nil else {
            appLog("[Update] Check already in progress, skipping")
            return
        }
        Task {
            updateStage = .checking
            do {
                let info = try await updater.checkForUpdate()
                pendingUpdate = info
                updateStage = nil
                if info == nil {
                    // Briefly show "already up to date" via error field (cleared by UI)
                    appLog("[Update] Already up to date")
                }
            } catch {
                updateStage = nil
                self.error = "检查更新失败: \(error.localizedDescription)"
                appLog("[Update] Check failed: \(error.localizedDescription)")
            }
        }
    }

    func performUpdate() {
        guard let info = pendingUpdate else { return }
        guard updateStage == nil else { return }
        updateError = nil

        updateTask = Task {
            do {
                try await updater.downloadAndInstall(info) { [weak self] stage in
                    Task { @MainActor in
                        self?.updateStage = stage
                    }
                }
                // downloadAndInstall calls exit(0) on success, so we only get here on error
            } catch is CancellationError {
                updateStage = nil
                appLog("[Update] Cancelled by user")
            } catch {
                updateStage = nil
                updateError = error.localizedDescription
                appLog("[Update] Failed: \(error.localizedDescription)")
            }
        }
    }

    func cancelUpdate() {
        updateTask?.cancel()
        updateTask = nil
        updateStage = nil
        updateError = nil
        relaunchTimer?.invalidate()
        relaunchTimer = nil
        relaunchCountdown = nil
        appLog("[Update] Cancelled")
    }

    func relaunchNow() {
        relaunchTimer?.invalidate()
        relaunchTimer = nil
        relaunchCountdown = nil

        let bundlePath = Bundle.main.bundlePath
        let url = URL(fileURLWithPath: bundlePath)
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in }
        exit(0)
    }

    func startRelaunchCountdown() {
        relaunchCountdown = 3
        relaunchTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            Task { @MainActor in
                guard let self else { timer.invalidate(); return }
                if let c = self.relaunchCountdown, c > 0 {
                    self.relaunchCountdown = c - 1
                } else {
                    timer.invalidate()
                    self.relaunchNow()
                }
            }
        }
    }

    // MARK: - Display Mode

    func toggleDisplayMode() {
        let newMode: DisplayMode = configStore.config.displayMode == .analyze ? .read : .analyze
        configStore.setDisplayMode(newMode)
        appLog("[Mode] Switched to \(newMode.rawValue)")
    }

    // MARK: - Provider Latency Testing

    func testProviderLatency() {
        guard !isTestingLatency else { return }
        isTestingLatency = true
        latencyResults = [:]

        Task {
            await withTaskGroup(of: LatencyResult.self) { group in
                for (id, provider) in Providers.all {
                    guard let apiKey = configStore.config.apiKeys[id], !apiKey.isEmpty else {
                        continue
                    }
                    let model = configStore.modelForProvider(id)
                    group.addTask {
                        await Self.measureLatency(providerId: id, provider: provider, apiKey: apiKey, model: model)
                    }
                }

                for await result in group {
                    latencyResults[result.providerId] = result
                }
            }
            isTestingLatency = false
            appLog("[Latency] Test complete: \(latencyResults.count) providers tested")
        }
    }

    private static func measureLatency(providerId: String, provider: Provider, apiKey: String, model: String) async -> LatencyResult {
        let url = URL(string: "\(provider.baseURL)/chat/completions")!
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = [
            "model": model,
            "stream": false,
            "max_tokens": 1,
            "messages": [["role": "user", "content": "Hi"]]
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        let start = Date()
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let elapsed = Int(Date().timeIntervalSince(start) * 1000)

            guard let httpResponse = response as? HTTPURLResponse else {
                return LatencyResult(providerId: providerId, latencyMs: nil, error: "无效响应", testedAt: Date())
            }

            if (200...299).contains(httpResponse.statusCode) {
                return LatencyResult(providerId: providerId, latencyMs: elapsed, error: nil, testedAt: Date())
            } else if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                return LatencyResult(providerId: providerId, latencyMs: nil, error: "Key 无效", testedAt: Date())
            } else {
                return LatencyResult(providerId: providerId, latencyMs: nil, error: "HTTP \(httpResponse.statusCode)", testedAt: Date())
            }
        } catch let error as URLError where error.code == .timedOut {
            return LatencyResult(providerId: providerId, latencyMs: nil, error: "超时", testedAt: Date())
        } catch {
            return LatencyResult(providerId: providerId, latencyMs: nil, error: "网络错误", testedAt: Date())
        }
    }

    // MARK: - Translation

    func translate(_ text: String, source: TranslationSource) {
        translateWithSource(text, source: source, sourceApp: "", sourceUrl: "")
    }

    func translateWithSource(_ text: String, source: TranslationSource, sourceApp: String, sourceUrl: String) {
        // Long text threshold check
        let threshold = configStore.config.longTextThreshold
        if text.count > threshold && source != .retranslate {
            pendingLongText = text
            pendingLongTextSource = source
            pendingLongTextSourceApp = sourceApp
            pendingLongTextSourceUrl = sourceUrl
            showLongTextConfirm = true
            return
        }

        enqueueTranslation(text, source: source, sourceApp: sourceApp, sourceUrl: sourceUrl)
    }

    func confirmLongTextTranslation() {
        if let text = pendingLongText, let source = pendingLongTextSource {
            enqueueTranslation(text, source: source,
                             sourceApp: pendingLongTextSourceApp,
                             sourceUrl: pendingLongTextSourceUrl)
        }
        pendingLongText = nil
        pendingLongTextSource = nil
        pendingLongTextSourceApp = ""
        pendingLongTextSourceUrl = ""
        showLongTextConfirm = false
    }

    func cancelLongTextTranslation() {
        pendingLongText = nil
        pendingLongTextSource = nil
        pendingLongTextSourceApp = ""
        pendingLongTextSourceUrl = ""
        showLongTextConfirm = false
    }

    private func enqueueTranslation(_ text: String, source: TranslationSource,
                                     sourceApp: String = "", sourceUrl: String = "") {
        var task = QueuedTask(text: text, source: source, sourceApp: sourceApp, sourceUrl: sourceUrl)

        // Dedup: retranslate bypasses dedup
        if source != .retranslate {
            let key = task.dedupKey

            // Check queue for same key already queued or running
            if translationQueue.contains(where: { ($0.status == .queued || $0.status == .running) && $0.dedupKey == key }) {
                appLog("[Translate] Dedup: skipping duplicate (already in queue)")
                return
            }

            // Check recently completed within dedup window
            if let completedAt = recentDedupKeys[key],
               Date().timeIntervalSince(completedAt) < dedupWindow {
                appLog("[Translate] Dedup: skipping duplicate (completed \(String(format: "%.1f", Date().timeIntervalSince(completedAt)))s ago)")
                return
            }
        }

        task.status = .queued
        translationQueue.append(task)
        processQueue()
    }

    func retranslate(_ text: String) {
        enqueueTranslation(text, source: .retranslate)
    }

    func pasteTranslate() {
        guard let text = NSPasteboard.general.string(forType: .string),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            error = "剪贴板为空"
            return
        }

        // Dedup: skip if same as current translation
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let current = currentTranslation, current.sourceText == trimmed {
            appLog("[Translate] pasteTranslate dedup: same as current translation")
            onToggleWindow?()
            return
        }

        translate(text, source: .clipboard)

        // Show window
        onToggleWindow?()
    }

    // MARK: - Task Cancellation

    func cancelTask(id: UUID) {
        if let idx = translationQueue.firstIndex(where: { $0.id == id }) {
            if translationQueue[idx].status == .queued {
                translationQueue[idx].status = .cancelled
                translationQueue.remove(at: idx)
                appLog("[Translate] Cancelled queued task: \(id.uuidString.prefix(8))")
            } else if translationQueue[idx].status == .running {
                runningTasks[id]?.cancel()
                runningTasks.removeValue(forKey: id)
                translationQueue[idx].status = .cancelled
                translationQueue.removeAll { $0.id == id }
                appLog("[Translate] Cancelled running task: \(id.uuidString.prefix(8))")
                updateIsTranslating()
                processQueue()
            }
        }
    }

    func cancelAllTasks() {
        for (id, swiftTask) in runningTasks {
            swiftTask.cancel()
            appLog("[Translate] Cancelled running task: \(id.uuidString.prefix(8))")
        }
        runningTasks.removeAll()
        translationQueue.removeAll()
        updateIsTranslating()
    }

    /// Legacy compat — called from header cancel button
    func cancelCurrentTranslation() {
        cancelAllTasks()
    }

    private func updateIsTranslating() {
        isTranslating = !runningTasks.isEmpty
    }

    // MARK: - Concurrent Queue Processing

    private func processQueue() {
        let maxConcurrent = configStore.config.maxConcurrentTranslations
        while runningTasks.count < maxConcurrent,
              let idx = translationQueue.firstIndex(where: { $0.status == .queued }) {
            translationQueue[idx].status = .running
            let task = translationQueue[idx]
            let swiftTask = Task { [weak self] in
                guard let self else { return }
                await self.executeTranslation(task)
            }
            runningTasks[task.id] = swiftTask
        }
        updateIsTranslating()
    }

    private func executeTranslation(_ task: QueuedTask) async {
        error = nil
        appLog("[Translate] Starting: \(task.text.prefix(60))...")

        let startTime = Date()
        var sentences: [Sentence] = []
        var pendingSentences: [Sentence] = []
        var lastUIUpdate = Date.distantPast
        let uiUpdateInterval: TimeInterval = 0.1

        do {
            sentences = try await translator.translateStream(text: task.text) { [weak self] sentence in
                await MainActor.run {
                    guard let self = self else { return }

                    if let idx = pendingSentences.firstIndex(where: { $0.index == sentence.index }) {
                        pendingSentences[idx] = sentence
                    } else {
                        pendingSentences.append(sentence)
                    }

                    let now = Date()
                    guard !sentence.isPartial || now.timeIntervalSince(lastUIUpdate) >= uiUpdateInterval else {
                        return
                    }
                    lastUIUpdate = now

                    let elapsed = Int(now.timeIntervalSince(startTime) * 1000)
                    self.currentTranslation = TranslationResult(
                        timestamp: startTime,
                        sourceText: task.text,
                        sentences: pendingSentences,
                        source: task.source,
                        elapsedMs: elapsed,
                        sourceApp: task.sourceApp,
                        sourceUrl: task.sourceUrl
                    )
                }
            }

            let elapsed = Int(Date().timeIntervalSince(startTime) * 1000)
            let result = TranslationResult(
                timestamp: startTime,
                sourceText: task.text,
                sentences: sentences,
                source: task.source,
                elapsedMs: elapsed,
                sourceApp: task.sourceApp,
                sourceUrl: task.sourceUrl
            )

            currentTranslation = result
            translationHistory.insert(result, at: 0)

            if translationHistory.count > 50 {
                translationHistory = Array(translationHistory.prefix(50))
            }

            appLog("[Translate] Done: \(sentences.count) sentences in \(elapsed)ms")
            translationStore.saveTranslation(result, sourceApp: task.sourceApp, sourceUrl: task.sourceUrl)

            // System notification for background translation completion
            notificationService.send(
                title: "翻译完成",
                body: "\(sentences.count) 句，耗时 \(String(format: "%.1f", Double(elapsed) / 1000.0))s",
                category: .translationDone
            )

            // Record dedup key with completion time
            recentDedupKeys[task.dedupKey] = Date()
            cleanupDedupKeys()

        } catch {
            let isCancellation = error is CancellationError || "\(error)".contains("cancelled")
            if isCancellation {
                appLog("[Translate] Cancelled with \(pendingSentences.count) partial sentences: \(task.text.prefix(40))...")
                // Preserve partial results on cancel — don't persist to history/SQLite
                if !pendingSentences.isEmpty {
                    let elapsed = Int(Date().timeIntervalSince(startTime) * 1000)
                    currentTranslation = TranslationResult(
                        timestamp: startTime,
                        sourceText: task.text,
                        sentences: pendingSentences,
                        source: task.source,
                        elapsedMs: elapsed,
                        sourceApp: task.sourceApp,
                        sourceUrl: task.sourceUrl,
                        wasCancelled: true
                    )
                }
            } else {
                appLog("[Translate] Error: \(error.localizedDescription)")
                self.error = error.localizedDescription
                notificationService.send(
                    title: "翻译失败",
                    body: error.localizedDescription,
                    category: .error
                )
            }
        }

        // Mark task completed and clean up
        if let idx = translationQueue.firstIndex(where: { $0.id == task.id }) {
            translationQueue[idx].status = .completed
            translationQueue.removeAll { $0.id == task.id }
        }
        runningTasks.removeValue(forKey: task.id)
        updateIsTranslating()

        // Trigger next queued tasks
        processQueue()
    }

    private func cleanupDedupKeys() {
        let now = Date()
        recentDedupKeys = recentDedupKeys.filter { now.timeIntervalSince($0.value) < dedupWindow }
    }

    // MARK: - Word Lookup

    func lookupWord(_ word: String) {
        isLookingUpWord = true
        showWordPopover = true

        Task {
            do {
                let entry = try await dictionaryService.lookupWord(word)
                currentWordLookup = entry
                translationStore.saveWordLookup(word: word, result: entry)
            } catch {
                self.error = "查词失败: \(error.localizedDescription)"
            }
            isLookingUpWord = false
        }
    }

    func addWordToVocab(_ entry: DictionaryEntry) {
        let vocabEntry = VocabEntry(
            word: entry.word,
            phonetic: entry.phonetic,
            meanings: entry.meanings,
            examples: entry.examples,
            synonyms: entry.synonyms,
            addedAt: ISO8601DateFormatter().string(from: Date())
        )
        _ = vocabStore.addWord(vocabEntry)
    }

    // MARK: - Writing Assistance

    func enhanceTranslate() {
        // Toggle: if already enhancing, cancel
        if isEnhancing {
            cancelEnhance()
            return
        }

        isEnhancing = true
        enhanceProgress = "正在获取文本..."

        enhanceTask = Task.detached { [weak self] in
            defer {
                Task { @MainActor in
                    self?.isEnhancing = false
                }
            }

            guard let result = SelectionMonitor.getSelectedTextFromFocusedField() else {
                await MainActor.run {
                    self?.error = "无法获取选中文本"
                    self?.enhanceProgress = ""
                }
                return
            }

            let text = result.text

            // Detect language: >50% CJK → Chinese-to-English, else grammar fix
            let cjkCount = text.unicodeScalars.filter { scalar in
                (0x4E00...0x9FFF).contains(scalar.value) ||
                (0x3400...0x4DBF).contains(scalar.value) ||
                (0xF900...0xFAFF).contains(scalar.value)
            }.count
            let isChinese = Double(cjkCount) / Double(max(text.count, 1)) > 0.5

            guard let self = self else { return }
            let configStore = await MainActor.run { self.configStore }

            guard let apiKey = configStore.apiKey else {
                await MainActor.run { self.error = "未配置 API Key"; self.enhanceProgress = "" }
                return
            }

            await MainActor.run { self.enhanceProgress = "正在生成..." }

            let provider = Providers.all[configStore.provider]!
            let url = URL(string: "\(provider.baseURL)/chat/completions")!

            var request = URLRequest(url: url, timeoutInterval: configStore.requestTimeout)
            request.httpMethod = "POST"
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            let systemPrompt = isChinese ? Constants.zhEnSystemPrompt : Constants.grammarFixSystemPrompt
            let model = configStore.modelForProvider(configStore.provider)
            let payload: [String: Any] = [
                "model": model,
                "temperature": 0.3,
                "stream": true,
                "messages": [
                    ["role": "system", "content": systemPrompt],
                    ["role": "user", "content": text]
                ]
            ]
            request.httpBody = try? JSONSerialization.data(withJSONObject: payload)

            do {
                let (asyncBytes, response) = try await URLSession.shared.bytes(for: request)

                guard let httpResponse = response as? HTTPURLResponse,
                      (200...299).contains(httpResponse.statusCode) else {
                    await MainActor.run { self.error = "写作辅助请求失败"; self.enhanceProgress = "" }
                    return
                }

                var accumulated = ""
                var lastLength = 0
                var firstChunk = true

                for try await line in asyncBytes.lines {
                    // Check cancellation
                    guard !Task.isCancelled else {
                        await MainActor.run { self.enhanceProgress = "已取消" }
                        appLog("[Enhance] Cancelled by user")
                        return
                    }

                    guard line.hasPrefix("data: ") else { continue }
                    let dataStr = line.dropFirst(6).trimmingCharacters(in: .whitespaces)
                    if dataStr == "[DONE]" { break }

                    guard let data = dataStr.data(using: .utf8),
                          let chunk = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let choices = chunk["choices"] as? [[String: Any]],
                          let delta = choices.first?["delta"] as? [String: Any],
                          let content = delta["content"] as? String else {
                        continue
                    }

                    accumulated += content

                    // Type the delta into the field
                    let deltaText = String(accumulated.dropFirst(lastLength))
                    if !deltaText.isEmpty {
                        await MainActor.run { self.enhanceProgress = "正在输入..." }

                        if firstChunk && !result.isFullValue {
                            // First keystroke replaces selection (macOS native behavior)
                            // Use longer initial delay for target app to process selection replacement
                            SelectionMonitor.typeText(deltaText, delayPerChunk: 0.05)
                            firstChunk = false
                        } else if result.isFullValue && firstChunk {
                            // For full value fields, paste the first chunk (with clipboard restore)
                            if !accumulated.isEmpty {
                                SelectionMonitor.pasteText(deltaText)
                            }
                            firstChunk = false
                        } else {
                            SelectionMonitor.typeText(deltaText)
                        }
                        lastLength = accumulated.count
                    }
                }

                await MainActor.run { self.enhanceProgress = "" }
                appLog("[Enhance] Done: \(accumulated.count) chars typed")

            } catch is CancellationError {
                await MainActor.run { self.enhanceProgress = "已取消" }
            } catch {
                await MainActor.run {
                    self.error = "写作辅助失败: \(error.localizedDescription)（可 ⌘Z 撤销已输入内容）"
                    self.enhanceProgress = ""
                }
            }
        }
    }

    func cancelEnhance() {
        enhanceTask?.cancel()
        enhanceTask = nil
        isEnhancing = false
        enhanceProgress = ""
        appLog("[Enhance] Cancelled")
    }
}

enum TaskStatus: String {
    case queued, running, completed, cancelled
}

struct QueuedTask: Identifiable {
    let id = UUID()
    let text: String
    let source: TranslationSource
    let sourceApp: String
    let sourceUrl: String
    var status: TaskStatus = .queued

    /// Dedup key: normalized text + sourceApp + sourceUrl
    var dedupKey: String {
        let normalized = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return "\(normalized)|\(sourceApp)|\(sourceUrl)"
    }

    init(text: String, source: TranslationSource, sourceApp: String = "", sourceUrl: String = "") {
        self.text = text
        self.source = source
        self.sourceApp = sourceApp
        self.sourceUrl = sourceUrl
    }
}
