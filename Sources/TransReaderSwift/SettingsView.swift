import SwiftUI

struct SettingsView: View {
    @Bindable var appState: AppState
    @Binding var showSettings: Bool
    
    @State private var selectedProvider: String
    @State private var apiKey: String = ""
    @State private var requestTimeout: Int
    @State private var monitorInterval: Int
    @State private var clipboardTranslate: Bool
    @State private var excludedAppsText: String = ""
    @State private var excludedUrlsText: String = ""
    @State private var customPrompt: String = ""
    @State private var vocabFilePath: String = ""
    @State private var shortcuts: [String: String] = [:]
    
    init(appState: AppState, showSettings: Binding<Bool>) {
        self._appState = Bindable(appState)
        self._showSettings = showSettings
        
        let config = appState.configStore.config
        self._selectedProvider = State(initialValue: config.provider)
        self._requestTimeout = State(initialValue: config.requestTimeout)
        self._monitorInterval = State(initialValue: config.monitorInterval)
        self._clipboardTranslate = State(initialValue: config.clipboardTranslateEnabled)
        self._excludedAppsText = State(initialValue: config.excludedApps.joined(separator: "\n"))
        self._excludedUrlsText = State(initialValue: config.excludedUrls.joined(separator: "\n"))
        self._customPrompt = State(initialValue: config.systemPrompt ?? "")
        self._vocabFilePath = State(initialValue: config.vocabFile)
        self._apiKey = State(initialValue: config.apiKeys[config.provider] ?? "")
        self._shortcuts = State(initialValue: config.shortcuts)
    }
    
    var body: some View {
        Form {
            Section("AI 服务商") {
                Picker("服务商", selection: $selectedProvider) {
                    ForEach(Array(Providers.all.keys.sorted()), id: \.self) { id in
                        Text(Providers.all[id]!.name).tag(id)
                    }
                }
                .onChange(of: selectedProvider) { _, newValue in
                    appState.configStore.setProvider(newValue)
                    apiKey = appState.configStore.config.apiKeys[newValue] ?? ""
                }
                
                SecureField("API Key", text: $apiKey, prompt: Text("输入 API Key"))
                    .textFieldStyle(.roundedBorder)
                
                HStack {
                    TextField("请求超时 (秒)", value: $requestTimeout, format: .number)
                        .textFieldStyle(.roundedBorder)
                    
                    Stepper("", value: $requestTimeout, in: 10...600, step: 10)
                }
            }
            
            Section("划词监控") {
                HStack {
                    TextField("轮询间隔 (毫秒)", value: $monitorInterval, format: .number)
                        .textFieldStyle(.roundedBorder)
                    
                    Stepper("", value: $monitorInterval, in: 50...10000, step: 50)
                }
                
                Toggle("剪贴板翻译", isOn: $clipboardTranslate)
                
                VStack(alignment: .leading) {
                    Text("排除应用（每行一个）")
                        .font(.caption)
                    
                    TextEditor(text: $excludedAppsText)
                        .font(.system(.body, design: .monospaced))
                        .frame(height: 80)
                        .border(Color.secondary.opacity(0.3))
                }
                
                VStack(alignment: .leading) {
                    Text("排除 URL（每行一个）")
                        .font(.caption)
                    
                    TextEditor(text: $excludedUrlsText)
                        .font(.system(.body, design: .monospaced))
                        .frame(height: 80)
                        .border(Color.secondary.opacity(0.3))
                }
            }
            
            Section("快捷键") {
                ForEach(Array(shortcuts.keys.sorted()), id: \.self) { key in
                    HStack {
                        Text(actionName(key))
                            .frame(width: 120, alignment: .leading)
                        
                        TextField("", text: Binding(
                            get: { shortcuts[key] ?? "" },
                            set: { shortcuts[key] = $0 }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .help("格式: cmd+t, cmd+shift+w, etc.")
                    }
                }
            }
            
            Section("生词本") {
                TextField("生词本路径", text: $vocabFilePath)
                    .textFieldStyle(.roundedBorder)
                    .disabled(true)
            }
            
            Section("System Prompt") {
                VStack(alignment: .leading) {
                    Text("自定义 System Prompt（留空使用默认）")
                        .font(.caption)
                    
                    TextEditor(text: $customPrompt)
                        .font(.system(.body, design: .monospaced))
                        .frame(height: 200)
                        .border(Color.secondary.opacity(0.3))
                }
            }
            
            HStack {
                Button("取消") {
                    showSettings = false
                }
                .keyboardShortcut(.cancelAction)
                
                Spacer()
                
                Button("保存") {
                    saveSettings()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: 800)
        .navigationTitle("设置")
    }
    
    private func actionName(_ key: String) -> String {
        switch key {
        case "capture_translate": return "截取翻译"
        case "toggle_window": return "显示/隐藏窗口"
        case "toggle_pin": return "窗口置顶"
        case "toggle_monitor": return "划词监控"
        case "quit": return "退出"
        default: return key
        }
    }
    
    private func saveSettings() {
        appState.configStore.update { config in
            config.provider = selectedProvider
            config.apiKeys[selectedProvider] = apiKey.isEmpty ? nil : apiKey
            config.requestTimeout = requestTimeout
            config.monitorInterval = monitorInterval
            config.clipboardTranslateEnabled = clipboardTranslate
            config.excludedApps = excludedAppsText.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            config.excludedUrls = excludedUrlsText.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            config.systemPrompt = customPrompt.isEmpty ? nil : customPrompt
            config.vocabFile = vocabFilePath
            config.shortcuts = shortcuts
        }
        
        // Update monitor settings
        appState.updateMonitorSettings()
        
        // Update hotkeys
        appState.updateHotkeys()
        
        showSettings = false
    }
}
