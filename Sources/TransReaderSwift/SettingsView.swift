import SwiftUI

struct SettingsView: View {
    @Bindable var appState: AppState
    @Binding var showSettings: Bool

    @State private var selectedProvider: String
    @State private var apiKey: String = ""
    @State private var customModel: String = ""
    @State private var requestTimeout: Int
    @State private var monitorInterval: Int
    @State private var includedAppsText: String = ""
    @State private var excludedUrlsText: String = ""
    @State private var customPrompt: String = ""
    @State private var vocabFilePath: String = ""
    @State private var shortcuts: [String: String] = [:]
    @State private var statusMessage: String?
    @State private var displayMode: DisplayMode
    @State private var longTextThreshold: Int
    @State private var showRunningApps = false
    @State private var notificationsEnabled: Bool
    @State private var notifyOnTranslationDone: Bool
    @State private var notifyOnError: Bool
    @State private var notifyOnLongOperation: Bool
    @State private var longOperationThreshold: Int

    init(appState: AppState, showSettings: Binding<Bool>) {
        self._appState = Bindable(appState)
        self._showSettings = showSettings

        let config = appState.configStore.config
        let provider = appState.configStore.provider
        self._selectedProvider = State(initialValue: provider)
        self._requestTimeout = State(initialValue: config.requestTimeout)
        self._monitorInterval = State(initialValue: config.monitorInterval)
        self._includedAppsText = State(initialValue: config.includedApps.joined(separator: "\n"))
        self._excludedUrlsText = State(initialValue: config.excludedUrls.joined(separator: "\n"))
        self._customPrompt = State(initialValue: config.systemPrompt ?? "")
        self._vocabFilePath = State(initialValue: config.vocabFile)
        self._apiKey = State(initialValue: appState.configStore.apiKey(for: provider) ?? "")
        self._customModel = State(initialValue: config.customModels[provider] ?? "")
        self._shortcuts = State(initialValue: config.shortcuts)
        self._displayMode = State(initialValue: config.displayMode)
        self._longTextThreshold = State(initialValue: config.longTextThreshold)
        self._notificationsEnabled = State(initialValue: config.notificationsEnabled)
        self._notifyOnTranslationDone = State(initialValue: config.notifyOnTranslationDone)
        self._notifyOnError = State(initialValue: config.notifyOnError)
        self._notifyOnLongOperation = State(initialValue: config.notifyOnLongOperation)
        self._longOperationThreshold = State(initialValue: config.longOperationThresholdSeconds)
    }

    var body: some View {
        GeometryReader { geo in
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 24) {
                // AI Provider
                settingsSection("AI 服务商") {
                    providerCards

                    VStack(alignment: .leading, spacing: 6) {
                        Text("API Key")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.textSecondary)
                        SecureField("输入 \(currentProviderName) API Key", text: $apiKey)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13, design: .monospaced))
                            .padding(8)
                            .background(Theme.bg)
                            .cornerRadius(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Theme.border, lineWidth: 1)
                            )
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("自定义模型（留空使用默认）")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.textSecondary)
                        TextField("默认: \(Providers.provider(for: selectedProvider).model)", text: $customModel)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13, design: .monospaced))
                            .padding(8)
                            .background(Theme.bg)
                            .cornerRadius(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Theme.border, lineWidth: 1)
                            )
                    }

                    HStack(spacing: 16) {
                        settingsField("请求超时", suffix: "秒") {
                            HStack(spacing: 4) {
                                TextField("", value: $requestTimeout, format: .number)
                                    .textFieldStyle(.plain)
                                    .frame(minWidth: 50, maxWidth: 70)
                                    .padding(6)
                                    .background(Theme.bg)
                                    .cornerRadius(4)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 4)
                                            .stroke(Theme.border, lineWidth: 1)
                                    )
                                Stepper("", value: $requestTimeout, in: 10...600, step: 10)
                                    .labelsHidden()
                            }
                        }
                    }
                }

                // Display settings
                settingsSection("显示设置") {
                    HStack {
                        Text("显示模式")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.textPrimary)
                        Spacer()
                        Picker("", selection: $displayMode) {
                            Text("分析模式").tag(DisplayMode.analyze)
                            Text("阅读模式").tag(DisplayMode.read)
                        }
                        .pickerStyle(.segmented)
                        .fixedSize()
                    }

                    Text(displayMode == .analyze ? "优先显示语法分析" : "优先显示翻译文本")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                }

                // Monitor settings
                settingsSection("监控设置") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("默认触发方式")
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.textPrimary)
                            Spacer()
                            Text("PopClip")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Theme.accent)
                        }

                        Text("选中文本后点击 PopClip 的“译”按钮触发翻译；划词监控是可选的高级模式。")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textSecondary)

                        Text(popClipSnippet)
                            .font(.system(size: 12, design: .monospaced))
                            .textSelection(.enabled)
                            .foregroundStyle(Theme.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(Theme.bg)
                            .cornerRadius(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Theme.border, lineWidth: 1)
                            )
                    }

                    Divider()

                    settingsField("轮询间隔", suffix: "ms") {
                        HStack(spacing: 4) {
                            TextField("", value: $monitorInterval, format: .number)
                                .textFieldStyle(.plain)
                                .frame(width: 60)
                                .padding(6)
                                .background(Theme.bg)
                                .cornerRadius(4)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(Theme.border, lineWidth: 1)
                                )
                            Stepper("", value: $monitorInterval, in: 50...10000, step: 50)
                                .labelsHidden()
                        }
                    }

                    settingsField("长文本阈值", suffix: "字符") {
                        HStack(spacing: 4) {
                            TextField("", value: $longTextThreshold, format: .number)
                                .textFieldStyle(.plain)
                                .frame(width: 60)
                                .padding(6)
                                .background(Theme.bg)
                                .cornerRadius(4)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(Theme.border, lineWidth: 1)
                                )
                            Stepper("", value: $longTextThreshold, in: 100...5000, step: 50)
                                .labelsHidden()
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("监控应用（每行一个，仅监控列表中的应用）")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Theme.textSecondary)
                            Spacer()
                            Button("选择运行中的应用") {
                                showRunningApps = true
                            }
                            .font(.system(size: 11))
                            .buttonStyle(.plain)
                            .foregroundStyle(Theme.accent)
                            .popover(isPresented: $showRunningApps) {
                                RunningAppsPopover(
                                    currentApps: includedAppsText.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) },
                                    onAdd: { name in
                                        if !includedAppsText.isEmpty && !includedAppsText.hasSuffix("\n") {
                                            includedAppsText += "\n"
                                        }
                                        includedAppsText += name
                                    }
                                )
                            }
                            Button("恢复默认") {
                                includedAppsText = AppConfig.defaultIncludedApps.joined(separator: "\n")
                            }
                            .font(.system(size: 11))
                            .buttonStyle(.plain)
                            .foregroundStyle(Theme.accent)
                        }
                        TextEditor(text: $includedAppsText)
                            .font(.system(size: 12, design: .monospaced))
                            .frame(height: 100)
                            .padding(4)
                            .background(Theme.bg)
                            .cornerRadius(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Theme.border, lineWidth: 1)
                            )
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("排除 URL（每行一个域名）")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.textSecondary)
                        TextEditor(text: $excludedUrlsText)
                            .font(.system(size: 12, design: .monospaced))
                            .frame(height: 60)
                            .padding(4)
                            .background(Theme.bg)
                            .cornerRadius(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Theme.border, lineWidth: 1)
                            )
                    }
                }

                // Shortcuts
                settingsSection("快捷键") {
                    VStack(spacing: 8) {
                        ForEach(shortcutKeys, id: \.self) { key in
                            HStack {
                                Text(actionName(key))
                                    .font(.system(size: 13))
                                    .foregroundStyle(Theme.textPrimary)
                                    .frame(minWidth: 60, alignment: .leading)

                                Spacer()

                                ShortcutRecorder(
                                    shortcut: Binding(
                                        get: { shortcuts[key] ?? "" },
                                        set: { shortcuts[key] = $0 }
                                    )
                                )
                                .frame(width: 140)
                            }
                        }
                    }

                    Text("点击按钮后按下快捷键组合进行录制")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                }

                // Prompt
                settingsSection("System Prompt") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("自定义翻译提示词（留空使用默认）")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textSecondary)
                        TextEditor(text: $customPrompt)
                            .font(.system(size: 12, design: .monospaced))
                            .frame(height: 160)
                            .padding(4)
                            .background(Theme.bg)
                            .cornerRadius(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Theme.border, lineWidth: 1)
                            )
                    }
                }

                // Vocab path
                settingsSection("通知") {
                    Toggle("启用系统通知", isOn: $notificationsEnabled)
                        .font(.system(size: 13))

                    if notificationsEnabled {
                        VStack(alignment: .leading, spacing: 8) {
                            Toggle("翻译完成（后台时）", isOn: $notifyOnTranslationDone)
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.textSecondary)
                            Toggle("错误提示", isOn: $notifyOnError)
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.textSecondary)
                            HStack {
                                Toggle("长时间操作", isOn: $notifyOnLongOperation)
                                    .font(.system(size: 12))
                                    .foregroundStyle(Theme.textSecondary)
                                if notifyOnLongOperation {
                                    Stepper("\(longOperationThreshold)s", value: $longOperationThreshold, in: 3...60, step: 1)
                                        .font(.system(size: 12))
                                        .foregroundStyle(Theme.textSecondary)
                                }
                            }
                        }
                        .padding(.leading, 8)
                    }
                }

                settingsSection("生词本") {
                    HStack {
                        Text(vocabFilePath)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(Theme.textSecondary)
                        Spacer()
                    }
                }

                // Save / Cancel
                HStack {
                    Spacer()

                    if let msg = statusMessage {
                        Text(msg)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.accent)
                            .transition(.opacity)
                    }

                    Button("保存") {
                        saveSettings()
                    }
                    .buttonStyle(AccentButtonStyle())
                    .keyboardShortcut(.defaultAction)
                }

                // Version info + check update
                HStack {
                    let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
                    let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
                    if let build {
                        Text("TransReader v\(version) (build \(build))")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textSecondary)
                    } else {
                        Text("TransReader \(version)")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textSecondary)
                    }

                    Spacer()

                    if Updater.isBundle {
                        if let pending = appState.pendingUpdate {
                            Button("更新到 v\(pending.version)") {
                                appState.performUpdate()
                            }
                            .font(.system(size: 11))
                            .buttonStyle(.plain)
                            .foregroundStyle(Theme.accent)
                            .disabled(appState.updateStage != nil)
                        } else {
                            Button("检查更新") {
                                appState.checkForUpdate()
                            }
                            .font(.system(size: 11))
                            .buttonStyle(.plain)
                            .foregroundStyle(Theme.accent)
                            .disabled(appState.updateStage != nil)
                        }
                    }
                }
            }
            .padding(24)
            .frame(width: geo.size.width)
        }
        }
        .background(Theme.bg)
    }

    // MARK: - Provider Cards
    /// Fastest successful latency among all results (for green highlight)
    private var fastestLatencyMs: Int? {
        appState.latencyResults.values
            .compactMap { $0.latencyMs }
            .min()
    }

    private var providerCards: some View {
        FlowLayout(spacing: 8) {
            ForEach(Array(Providers.all.keys.sorted()), id: \.self) { id in
                let provider = Providers.provider(for: id)
                let isSelected = selectedProvider == id
                let hasKey = appState.configStore.hasAPIKey(for: id)

                Button {
                    selectedProvider = id
                    apiKey = appState.configStore.apiKey(for: id) ?? ""
                    customModel = appState.configStore.config.customModels[id] ?? ""
                } label: {
                    HStack(spacing: 6) {
                        Text(provider.name)
                            .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                            .foregroundStyle(isSelected ? Theme.accent : Theme.textPrimary)

                        if isSelected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Theme.accent)
                        }

                        latencyLabel(for: id, hasKey: hasKey)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(isSelected ? Theme.accent.opacity(0.1) : Theme.tertiaryBg)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }

            // Latency test button
            Button {
                appState.testProviderLatency()
            } label: {
                if appState.isTestingLatency {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 20, height: 20)
                } else {
                    Image(systemName: "speedometer")
                        .font(.system(size: 13))
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.textSecondary)
            .help("测速")
            .disabled(appState.isTestingLatency)
        }
    }

    @ViewBuilder
    private func latencyLabel(for providerId: String, hasKey: Bool) -> some View {
        if appState.isTestingLatency {
            ProgressView()
                .controlSize(.mini)
        } else if let result = appState.latencyResults[providerId] {
            if let ms = result.latencyMs {
                let isFastest = ms == fastestLatencyMs
                Text("\(ms)ms")
                    .font(.system(size: 10, weight: isFastest ? .semibold : .regular))
                    .foregroundStyle(isFastest ? .green : Theme.textSecondary)
            } else if let error = result.error {
                Text(error)
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
            }
        } else if !hasKey && !appState.latencyResults.isEmpty {
            Text("未配置")
                .font(.system(size: 10))
                .foregroundStyle(Theme.textSecondary.opacity(0.5))
        }
    }

    // MARK: - Ordered shortcut keys
    private var shortcutKeys: [String] {
        ["capture_translate", "toggle_window", "toggle_pin", "toggle_monitor", "enhance_translate", "paste_translate"]
    }

    // MARK: - Helpers
    private var currentProviderName: String {
        Providers.provider(for: selectedProvider).name
    }

    private var popClipSnippet: String {
        """
        #popclip
        name: TransReader
        icon: 译
        url: transreader://translate?text={popclip text}
        """
    }

    private func settingsSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)

            VStack(alignment: .leading, spacing: 12) {
                content()
            }
            .padding(12)
            .background(Theme.cardBg)
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Theme.border.opacity(0.5), lineWidth: 1)
            )
        }
    }

    private func settingsField<Content: View>(_ label: String, suffix: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(Theme.textPrimary)
            content()
            if let suffix = suffix {
                Text(suffix)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private func actionName(_ key: String) -> String {
        switch key {
        case "capture_translate": return "截取翻译"
        case "toggle_window": return "显示/隐藏窗口"
        case "toggle_pin": return "窗口置顶"
        case "toggle_monitor": return "划词监控"
        case "enhance_translate": return "写作辅助"
        case "paste_translate": return "粘贴翻译"
        default: return key
        }
    }

    private func saveSettings() {
        let selectedProvider = selectedProvider
        let apiKey = apiKey
        let customModel = customModel
        let requestTimeout = requestTimeout
        let monitorInterval = monitorInterval
        let includedApps = includedAppsText.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let excludedUrls = excludedUrlsText.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let customPrompt = customPrompt
        let vocabFilePath = vocabFilePath
        let shortcuts = shortcuts
        let displayMode = displayMode
        let longTextThreshold = longTextThreshold
        let notificationsEnabled = notificationsEnabled
        let notifyOnTranslationDone = notifyOnTranslationDone
        let notifyOnError = notifyOnError
        let notifyOnLongOperation = notifyOnLongOperation
        let longOperationThreshold = longOperationThreshold

        appState.configStore.update { config in
            config.provider = selectedProvider
            config.apiKeys[selectedProvider] = apiKey.isEmpty ? nil : apiKey
            if !customModel.isEmpty {
                config.customModels[selectedProvider] = customModel
            } else {
                config.customModels.removeValue(forKey: selectedProvider)
            }
            config.requestTimeout = requestTimeout
            config.monitorInterval = monitorInterval
            config.includedApps = includedApps
            config.excludedUrls = excludedUrls
            config.systemPrompt = customPrompt.isEmpty ? nil : customPrompt
            config.vocabFile = vocabFilePath
            config.shortcuts = shortcuts
            config.displayMode = displayMode
            config.longTextThreshold = longTextThreshold
            config.notificationsEnabled = notificationsEnabled
            config.notifyOnTranslationDone = notifyOnTranslationDone
            config.notifyOnError = notifyOnError
            config.notifyOnLongOperation = notifyOnLongOperation
            config.longOperationThresholdSeconds = longOperationThreshold
        }

        appState.updateMonitorSettings()
        appState.updateHotkeys(shortcuts)

        withAnimation {
            statusMessage = "已保存"
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                statusMessage = nil
            }
        }
    }
}

// MARK: - Running Apps Popover

private struct RunningAppItem: Identifiable {
    let id: String  // bundleIdentifier or name
    let name: String
    let isAlreadyAdded: Bool
}

struct RunningAppsPopover: View {
    let currentApps: [String]
    let onAdd: (String) -> Void

    private var runningApps: [RunningAppItem] {
        var seen = Set<String>()
        var items: [RunningAppItem] = []

        for app in NSWorkspace.shared.runningApplications {
            let policy = app.activationPolicy
            guard policy == .regular || policy == .accessory else { continue }
            guard let name = app.localizedName, !name.isEmpty else { continue }

            // Exclude TransReader itself
            if let bundleId = app.bundleIdentifier,
               bundleId.lowercased().contains("transreader") {
                continue
            }

            // Dedup by name
            let key = name.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)

            let alreadyAdded = currentApps.contains { $0.localizedCaseInsensitiveCompare(name) == .orderedSame }
            items.append(RunningAppItem(id: app.bundleIdentifier ?? name, name: name, isAlreadyAdded: alreadyAdded))
        }

        return items.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("运行中的应用")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 6)

            Divider()

            let apps = runningApps
            if apps.isEmpty {
                Text("未发现可用应用")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(12)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(apps) { app in
                            Button {
                                if !app.isAlreadyAdded {
                                    onAdd(app.name)
                                }
                            } label: {
                                HStack {
                                    Text(app.name)
                                        .font(.system(size: 12))
                                        .foregroundStyle(app.isAlreadyAdded ? Theme.textSecondary : Theme.textPrimary)
                                    Spacer()
                                    if app.isAlreadyAdded {
                                        Text("已添加")
                                            .font(.system(size: 10))
                                            .foregroundStyle(Theme.textSecondary.opacity(0.6))
                                    }
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .disabled(app.isAlreadyAdded)
                        }
                    }
                }
                .frame(maxHeight: 300)
            }
        }
        .frame(width: 260)
    }
}

// MARK: - Accent Button Style
struct AccentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(configuration.isPressed ? Theme.accent.opacity(0.8) : Theme.accent)
            .cornerRadius(6)
    }
}

// MARK: - Shortcut Recorder (press key combo to record)
struct ShortcutRecorder: NSViewRepresentable {
    @Binding var shortcut: String

    func makeNSView(context: Context) -> ShortcutRecorderNSView {
        let view = ShortcutRecorderNSView()
        view.shortcut = shortcut
        view.onChange = { newValue in
            shortcut = newValue
        }
        return view
    }

    func updateNSView(_ nsView: ShortcutRecorderNSView, context: Context) {
        nsView.shortcut = shortcut
    }
}

class ShortcutRecorderNSView: NSView {
    var shortcut: String = "" { didSet { needsDisplay = true } }
    var onChange: ((String) -> Void)?
    private var isRecording = false { didSet { needsDisplay = true } }

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 4
    }
    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 200, height: 26)
    }

    override func draw(_ dirtyRect: NSRect) {
        let bg: NSColor = isRecording ? .controlAccentColor.withAlphaComponent(0.1) : .controlBackgroundColor
        bg.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 4, yRadius: 4).fill()

        let borderColor: NSColor = isRecording ? .controlAccentColor : .separatorColor
        borderColor.setStroke()
        let border = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 4, yRadius: 4)
        border.lineWidth = 1
        border.stroke()

        let displayText: String
        if isRecording {
            displayText = "按下快捷键..."
        } else if shortcut.isEmpty {
            displayText = "点击录制"
        } else {
            displayText = formatDisplay(shortcut)
        }

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
            .foregroundColor: isRecording ? NSColor.controlAccentColor : (shortcut.isEmpty ? NSColor.secondaryLabelColor : NSColor.labelColor)
        ]
        let str = NSAttributedString(string: displayText, attributes: attrs)
        let size = str.size()
        let point = NSPoint(x: 8, y: (bounds.height - size.height) / 2)
        str.draw(at: point)
    }

    override func mouseDown(with event: NSEvent) {
        if isRecording {
            // Click again to cancel
            isRecording = false
            window?.makeFirstResponder(nil)
        } else {
            isRecording = true
            window?.makeFirstResponder(self)
        }
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else { super.keyDown(with: event); return }

        let mods = event.modifierFlags.intersection([.command, .option, .shift, .control])

        // Escape cancels recording
        if event.keyCode == 0x35 {
            isRecording = false
            window?.makeFirstResponder(nil)
            return
        }

        // Delete/Backspace clears the shortcut
        if event.keyCode == 0x33 {
            shortcut = ""
            onChange?("")
            isRecording = false
            window?.makeFirstResponder(nil)
            return
        }

        // Require at least one modifier
        guard !mods.isEmpty else { return }

        // Build shortcut string
        var parts: [String] = []
        if mods.contains(.control) { parts.append("ctrl") }
        if mods.contains(.option) { parts.append("option") }
        if mods.contains(.shift) { parts.append("shift") }
        if mods.contains(.command) { parts.append("cmd") }

        if let keyName = keyName(for: event.keyCode) {
            parts.append(keyName)
        } else if let chars = event.charactersIgnoringModifiers, !chars.isEmpty {
            parts.append(chars.lowercased())
        } else {
            return
        }

        // Reject system-critical combos (would break copy/paste/quit/etc.)
        // Allow if user adds extra modifiers like option/shift/ctrl.
        let reservedCmdKeys: Set<String> = ["c", "v", "x", "a", "z", "q", "w", "s", "f", "n", "t", "p", "o"]
        if mods == .command, let last = parts.last, reservedCmdKeys.contains(last) {
            NSSound.beep()
            return
        }

        let result = parts.joined(separator: "+")
        shortcut = result
        onChange?(result)
        isRecording = false
        window?.makeFirstResponder(nil)
    }

    override func resignFirstResponder() -> Bool {
        isRecording = false
        return super.resignFirstResponder()
    }

    override func flagsChanged(with event: NSEvent) {
        // Ignore standalone modifier presses
    }

    private func keyName(for keyCode: UInt16) -> String? {
        let map: [UInt16: String] = [
            0x00: "a", 0x01: "s", 0x02: "d", 0x03: "f", 0x04: "h",
            0x05: "g", 0x06: "z", 0x07: "x", 0x08: "c", 0x09: "v",
            0x0B: "b", 0x0C: "q", 0x0D: "w", 0x0E: "e", 0x0F: "r",
            0x10: "y", 0x11: "t", 0x12: "1", 0x13: "2", 0x14: "3",
            0x15: "4", 0x17: "5", 0x16: "6", 0x1A: "7", 0x1C: "8",
            0x19: "9", 0x1D: "0", 0x1F: "o", 0x20: "u", 0x22: "i",
            0x23: "p", 0x25: "l", 0x26: "j", 0x28: "k", 0x2D: "n",
            0x2E: "m",
            0x24: "return", 0x30: "tab", 0x31: "space",
            0x7A: "f1", 0x78: "f2", 0x63: "f3", 0x76: "f4",
            0x60: "f5", 0x61: "f6", 0x62: "f7", 0x64: "f8",
            0x65: "f9", 0x6D: "f10", 0x67: "f11", 0x6F: "f12",
        ]
        return map[keyCode]
    }

    private func formatDisplay(_ shortcut: String) -> String {
        shortcut.components(separatedBy: "+")
            .map { part in
                switch part.lowercased() {
                case "cmd", "command": return "⌘"
                case "option", "opt", "alt": return "⌥"
                case "shift": return "⇧"
                case "ctrl", "control": return "⌃"
                default: return part.uppercased()
                }
            }
            .joined()
    }
}
