import SwiftUI

// MARK: - Main Content View
struct ContentView: View {
    @Bindable var appState: AppState
    @Binding var showSettings: Bool

    @State private var selectedTab = Tab.results

    enum Tab: String, CaseIterable {
        case results = "翻译结果"
        case vocab = "词库"
        case reading = "阅读"
        case stats = "统计"
        case settings = "设置"

        var icon: String {
            switch self {
            case .results: return "doc.text"
            case .vocab: return "book"
            case .reading: return "calendar"
            case .stats: return "chart.bar"
            case .settings: return "gearshape"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header bar
            headerBar

            Divider()
                .foregroundColor(Theme.border)

            // Update progress banner
            if let stage = appState.updateStage {
                UpdateProgressView(
                    stage: stage,
                    pendingVersion: appState.pendingUpdate?.version,
                    error: appState.updateError,
                    countdown: appState.relaunchCountdown,
                    onCancel: { appState.cancelUpdate() },
                    onRetry: { appState.performUpdate() },
                    onRelaunchNow: { appState.relaunchNow() }
                )
                .padding(.horizontal, 16)
                .padding(.top, 8)
            } else if let error = appState.updateError {
                // Show error even after stage clears
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 12))
                        .foregroundStyle(.orange)
                    Text("更新失败: \(error)")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                    Spacer()
                    Button("重试") { appState.performUpdate() }
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.accent)
                        .buttonStyle(.plain)
                    Button {
                        appState.updateError = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Theme.tertiaryBg)
            }

            // Tab content
            Group {
                switch selectedTab {
                case .results:
                    TranslationResultsView(appState: appState)
                case .vocab:
                    VocabView(vocabStore: appState.vocabStore)
                case .reading:
                    ReadingView(translationStore: appState.translationStore)
                case .stats:
                    StatsView(translationStore: appState.translationStore)
                case .settings:
                    SettingsView(appState: appState, showSettings: $showSettings)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.bg)
        .onChange(of: showSettings) { _, newValue in
            if newValue {
                selectedTab = .settings
            }
        }
        // Word lookup popover
        .sheet(isPresented: $appState.showWordPopover) {
            wordLookupSheet
        }
        // Long text confirmation
        .alert("长文本确认", isPresented: $appState.showLongTextConfirm) {
            Button("翻译") {
                appState.confirmLongTextTranslation()
            }
            Button("取消", role: .cancel) {
                appState.cancelLongTextTranslation()
            }
        } message: {
            if let text = appState.pendingLongText {
                Text("选中的文本有 \(text.count) 个字符，确定要翻译吗？")
            }
        }
    }

    // MARK: - Word Lookup Sheet
    @ViewBuilder
    private var wordLookupSheet: some View {
        VStack(spacing: 0) {
            HStack {
                Text("查词")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Button {
                    appState.showWordPopover = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.textSecondary)
                }
                .buttonStyle(.plain)
                .focusable(false)
            }
            .padding(16)

            Divider()

            if appState.isLookingUpWord {
                VStack {
                    ProgressView()
                    Text("查询中...")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let entry = appState.currentWordLookup {
                WordLookupView(entry: entry, dictionaryService: appState.dictionaryService) {
                    appState.addWordToVocab(entry)
                }
            }
        }
        .frame(width: 400, height: 500)
        .background(Theme.bg)
    }

    // MARK: - Header Bar
    private var headerBar: some View {
        HStack(spacing: 0) {
            // Tabs
            HStack(spacing: 2) {
                ForEach(Tab.allCases, id: \.self) { tab in
                    tabButton(tab)
                }
            }
            .padding(.leading, 16)

            Spacer()

            // Action buttons
            HStack(spacing: 12) {
                // Queue indicator with task count
                if appState.isTranslating || !appState.translationQueue.isEmpty {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)

                        let runningCount = appState.translationQueue.filter { $0.status == .running }.count
                        let queuedCount = appState.translationQueue.filter { $0.status == .queued }.count
                        if runningCount + queuedCount > 0 {
                            Text("\(runningCount)/\(runningCount + queuedCount)")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Theme.textSecondary)
                                .help("执行中/总计")
                        }

                        Button {
                            appState.cancelAllTasks()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Theme.textSecondary)
                        }
                        .buttonStyle(.plain)
                        .focusable(false)
                        .help("取消全部")
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Theme.tertiaryBg)
                    .cornerRadius(6)
                }

                // Writing assistance indicator
                if appState.isEnhancing {
                    HStack(spacing: 5) {
                        ProgressView()
                            .controlSize(.mini)
                        Text(appState.enhanceProgress)
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.textSecondary)
                        Button {
                            appState.cancelEnhance()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(Theme.textSecondary)
                        }
                        .buttonStyle(.plain)
                        .focusable(false)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Theme.tertiaryBg)
                    .cornerRadius(5)
                }

                // Display mode toggle
                Button {
                    appState.toggleDisplayMode()
                } label: {
                    Image(systemName: appState.configStore.config.displayMode == .read ? "book.fill" : "text.magnifyingglass")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.accent)
                }
                .buttonStyle(.plain)
                .focusable(false)
                .help(appState.configStore.config.displayMode == .read ? "阅读模式（点击切换分析模式）" : "分析模式（点击切换阅读模式）")

                // Monitor toggle
                Button {
                    appState.toggleMonitor()
                } label: {
                    Image(systemName: appState.monitorEnabled ? "eye.fill" : "eye.slash")
                        .font(.system(size: 14))
                        .foregroundStyle(appState.monitorEnabled ? Theme.accent : Theme.textSecondary)
                }
                .buttonStyle(.plain)
                .focusable(false)
                .help(appState.monitorEnabled ? "划词监控: 开" : "划词监控: 关")

                // OCR capture
                Button {
                    appState.onCaptureTranslate?()
                } label: {
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.textSecondary)
                }
                .buttonStyle(.plain)
                .focusable(false)
                .help("截取翻译 (⌥⌘T)")

                // Pin toggle
                Button {
                    appState.onTogglePin?()
                } label: {
                    Image(systemName: appState.windowPinned ? "pin.fill" : "pin")
                        .font(.system(size: 14))
                        .foregroundStyle(appState.windowPinned ? Theme.accent : Theme.textSecondary)
                }
                .buttonStyle(.plain)
                .focusable(false)
                .help("窗口置顶")
            }
            .padding(.trailing, 16)
        }
        .frame(height: 44)
        .background(.ultraThinMaterial)
    }

    private func tabButton(_ tab: Tab) -> some View {
        Button {
            selectedTab = tab
        } label: {
            HStack(spacing: 5) {
                Image(systemName: tab.icon)
                    .font(.system(size: 12))
                Text(tab.rawValue)
                    .font(.system(size: 13, weight: selectedTab == tab ? .semibold : .regular))
            }
            .foregroundStyle(selectedTab == tab ? Theme.accent : Theme.textSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(selectedTab == tab ? Theme.accent.opacity(0.1) : Color.clear)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .focusable(false)
    }
}

// MARK: - Translation Results Tab
struct TranslationResultsView: View {
    @Bindable var appState: AppState

    var body: some View {
        if appState.translationHistory.isEmpty && appState.currentTranslation == nil {
            emptyState
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        // Queue list (visible when >1 task)
                        if appState.translationQueue.count > 1 {
                            QueueListView(appState: appState)
                                .padding(.bottom, 8)
                        }

                        // Current translating block (if not yet in history)
                        if let current = appState.currentTranslation,
                           !appState.translationHistory.contains(where: { $0.timestamp == current.timestamp }) {
                            TranslationBlockView(
                                result: current,
                                isActive: appState.isTranslating,
                                displayMode: appState.configStore.config.displayMode,
                                onRetranslate: { text in appState.retranslate(text) },
                                onWordLookup: { word in appState.lookupWord(word) },
                                onCancel: appState.isTranslating ? {
                                    // Find the running task that matches this translation
                                    if let task = appState.translationQueue.first(where: {
                                        $0.status == .running && $0.text == current.sourceText
                                    }) {
                                        appState.cancelTask(id: task.id)
                                    } else {
                                        // Fallback: cancel all if we can't identify the specific task
                                        appState.cancelAllTasks()
                                    }
                                } : nil
                            )
                            .id("current")
                        }

                        // History blocks
                        ForEach(appState.translationHistory, id: \.timestamp) { result in
                            TranslationBlockView(
                                result: result,
                                isActive: appState.currentTranslation?.timestamp == result.timestamp,
                                displayMode: appState.configStore.config.displayMode,
                                onRetranslate: { text in appState.retranslate(text) },
                                onWordLookup: { word in appState.lookupWord(word) }
                            )
                        }
                    }
                    .padding(.vertical, 16)
                    .padding(.horizontal, 24)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "character.book.closed")
                .font(.system(size: 48))
                .foregroundStyle(Theme.textSecondary.opacity(0.4))

            VStack(spacing: 8) {
                Text("尚无翻译结果")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)

                Text("点击菜单栏「译」→「截取翻译」，或按 ⌥⌘T")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary.opacity(0.7))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Queue List View
struct QueueListView: View {
    @Bindable var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("翻译队列")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)

            ForEach(appState.translationQueue) { task in
                HStack(spacing: 8) {
                    // Status icon
                    Group {
                        switch task.status {
                        case .running:
                            ProgressView()
                                .controlSize(.mini)
                        case .queued:
                            Image(systemName: "clock")
                                .font(.system(size: 10))
                                .foregroundStyle(Theme.textSecondary)
                        default:
                            EmptyView()
                        }
                    }
                    .frame(width: 14)

                    // Text preview
                    Text(String(task.text.prefix(40)))
                        .font(.system(size: 11))
                        .foregroundStyle(task.status == .running ? Theme.textPrimary : Theme.textSecondary)
                        .lineLimit(1)

                    Spacer()

                    // Per-task cancel
                    Button {
                        appState.cancelTask(id: task.id)
                    } label: {
                        Image(systemName: "xmark.circle")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                }
                .padding(.vertical, 2)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.tertiaryBg)
        .cornerRadius(6)
    }
}

// MARK: - Error Alert Modifier
extension View {
    func translationErrorAlert(appState: AppState) -> some View {
        self.alert("错误", isPresented: .constant(appState.error != nil)) {
            Button("确定") {
                appState.error = nil
            }
        } message: {
            if let error = appState.error {
                Text(error)
            }
        }
    }

    func translocationAlert(appState: AppState) -> some View {
        self.alert("应用需要安装", isPresented: Binding(
            get: { appState.showTranslocationAlert },
            set: { appState.showTranslocationAlert = $0 }
        )) {
            Button("安装并重启") {
                appState.installToApplications()
            }
            Button("稍后", role: .cancel) {
                appState.showTranslocationAlert = false
            }
        } message: {
            Text("TransReader 当前从临时位置运行，自动更新等功能受限。\n是否安装到「应用程序」文件夹？")
        }
    }
}
