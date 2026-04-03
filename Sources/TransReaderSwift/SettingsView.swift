import SwiftUI

struct SettingsView: View {
    @Bindable var appState: AppState
    @Binding var showSettings: Bool

    @State private var selectedProvider: String
    @State private var apiKey: String = ""
    @State private var customModel: String = ""
    @State private var requestTimeout: Int
    @State private var monitorInterval: Int
    @State private var clipboardTranslate: Bool
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
        self._selectedProvider = State(initialValue: config.provider)
        self._requestTimeout = State(initialValue: config.requestTimeout)
        self._monitorInterval = State(initialValue: config.monitorInterval)
        self._clipboardTranslate = State(initialValue: config.clipboardTranslateEnabled)
        self._includedAppsText = State(initialValue: config.includedApps.joined(separator: "\n"))
        self._excludedUrlsText = State(initialValue: config.excludedUrls.joined(separator: "\n"))
        self._customPrompt = State(initialValue: config.systemPrompt ?? "")
        self._vocabFilePath = State(initialValue: config.vocabFile)
        self._apiKey = State(initialValue: config.apiKeys[config.provider] ?? "")
        self._customModel = State(initialValue: config.customModels[config.provider] ?? "")
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
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // AI Provider
                settingsSection("AI 服务商") {
                    HStack {
                        providerCards

                        // Latency test button
                        Button {
                            appState.testProviderLatency()
                        } label: {
                            if appState.isTestingLatency {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "speedometer")
                                    .font(.system(size: 14))
                            }
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.textSecondary)
                        .help("测速")
                        .disabled(appState.isTestingLatency)
                        .frame(width: 30)
                    }

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
                        TextField("默认: \(Providers.all[selectedProvider]?.model ?? "")", text: $customModel)
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
                                    .frame(width: 60)
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
                        .frame(width: 200)
                    }

                    Text(displayMode == .analyze ? "优先显示语法分析" : "优先显示翻译文本")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                }

                // Monitor settings
                settingsSection("监控设置") {
                    HStack {
                        Toggle("剪贴板翻译 (Cmd+C)", isOn: $clipboardTranslate)
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.textPrimary)
                            .toggleStyle(.switch)
                            .tint(Theme.accent)
                    }

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
                                    .frame(width: 120, alignment: .leading)

                                TextField("", text: Binding(
                                    get: { shortcuts[key] ?? "" },
                                    set: { shortcuts[key] = $0 }
                                ))
                                .textFieldStyle(.plain)
                                .font(.system(size: 12, design: .monospaced))
                                .padding(6)
                                .background(Theme.bg)
                                .cornerRadius(4)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(Theme.border, lineWidth: 1)
                                )
                                .frame(maxWidth: 200)
                            }
                        }
                    }

                    Text("格式: option+cmd+字母 (例: option+cmd+t)")
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
        HStack(spacing: 10) {
            ForEach(Array(Providers.all.keys.sorted()), id: \.self) { id in
                let provider = Providers.all[id]!
                let isSelected = selectedProvider == id
                let hasKey = !(appState.configStore.config.apiKeys[id] ?? "").isEmpty

                Button {
                    selectedProvider = id
                    apiKey = appState.configStore.config.apiKeys[id] ?? ""
                    customModel = appState.configStore.config.customModels[id] ?? ""
                } label: {
                    VStack(spacing: 4) {
                        Text(provider.name)
                            .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                            .foregroundStyle(isSelected ? Theme.accent : Theme.textPrimary)

                        if isSelected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Theme.accent)
                        }

                        // Latency result
                        latencyLabel(for: id, hasKey: hasKey)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(isSelected ? Theme.accent.opacity(0.08) : Theme.tertiaryBg)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isSelected ? Theme.accent.opacity(0.5) : Theme.border.opacity(0.5), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
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
        Providers.all[selectedProvider]?.name ?? selectedProvider
    }

    private func settingsSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)

            VStack(alignment: .leading, spacing: 12) {
                content()
            }
            .padding(16)
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
            config.clipboardTranslateEnabled = clipboardTranslate
            config.includedApps = includedAppsText.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            config.excludedUrls = excludedUrlsText.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
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
        appState.updateHotkeys()

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
