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
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 0) {
                    ForEach(Tab.allCases, id: \.self) { tab in
                        tabButton(tab)
                    }
                }
                .padding(.horizontal, 4)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                toolbarActions
            }
        }
        .onChange(of: showSettings) { _, newValue in
            if newValue {
                selectedTab = .settings
            }
        }
        .onChange(of: appState.currentTranslation?.timestamp) { _, timestamp in
            if timestamp != nil {
                selectedTab = .results
            }
        }
        .overlay {
            if appState.showWordPopover {
                wordLookupOverlay
            }
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

    // MARK: - Word Lookup Overlay
    @ViewBuilder
    private var wordLookupOverlay: some View {
        ZStack {
            // Dimmed backdrop
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture { appState.dismissWordLookup() }

            VStack(spacing: 0) {
                HStack {
                    Text("查词")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Button {
                        appState.dismissWordLookup()
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
            .frame(maxWidth: 400, maxHeight: 500)
            .background(Theme.bg)
            .cornerRadius(10)
            .shadow(color: .black.opacity(0.2), radius: 20)
            .padding(16)
        }
    }

    // MARK: - Toolbar Actions
    @ViewBuilder
    private var toolbarActions: some View {
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

        // Monitor toggle
        Button {
            appState.toggleMonitor()
        } label: {
            Image(systemName: appState.monitorEnabled ? "eye.fill" : "eye.slash")
        }
        .help(appState.monitorEnabled ? "划词监控: 开" : "划词监控: 关")

        // Pin toggle
        Button {
            appState.onTogglePin?()
        } label: {
            Image(systemName: appState.windowPinned ? "pin.fill" : "pin")
        }
        .help("窗口置顶")

        // More actions menu
        Menu {
            Button {
                appState.toggleDisplayMode()
            } label: {
                Label(
                    appState.configStore.config.displayMode == .read ? "切换分析模式" : "切换阅读模式",
                    systemImage: appState.configStore.config.displayMode == .read ? "text.magnifyingglass" : "book.fill"
                )
            }
            Button {
                appState.onCaptureTranslate?()
            } label: {
                Label("截取翻译 (⌥⌘T)", systemImage: "camera.viewfinder")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
    }

    private func tabButton(_ tab: Tab) -> some View {
        TabButton(tab: tab, isSelected: selectedTab == tab) {
            selectedTab = tab
        }
    }

    // Separate view struct so @State (hover) is per-tab
    private struct TabButton: View {
        let tab: Tab
        let isSelected: Bool
        let action: () -> Void
        @State private var isHovered = false

        var body: some View {
            Button(action: action) {
                Image(systemName: tab.icon)
                    .font(.system(size: 13))
                    .foregroundStyle(isSelected ? Theme.accent : isHovered ? Theme.textPrimary : Theme.textSecondary)
                    .frame(width: 32, height: 28)
                    .background(isSelected ? Theme.accent.opacity(0.12) : isHovered ? Theme.textSecondary.opacity(0.1) : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .focusable(false)
            .onHover { isHovered = $0 }
            .help(tab.rawValue)
        }
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

                        // Current translation block — persists until a new translation starts
                        if let current = appState.currentTranslation {
                            TranslationBlockView(
                                result: current,
                                isActive: appState.isTranslating,
                                displayMode: appState.configStore.config.displayMode,
                                onRetranslate: { text in appState.retranslate(text) },
                                onWordLookup: { word in appState.lookupWord(word) },
                                onCancel: appState.isTranslating ? {
                                    if let task = appState.translationQueue.first(where: {
                                        $0.status == .running && $0.text == current.sourceText
                                    }) {
                                        appState.cancelTask(id: task.id)
                                    } else {
                                        appState.cancelAllTasks()
                                    }
                                } : nil
                            )
                            .id("current")
                        }

                        // History blocks — skip the one shown as current
                        ForEach(appState.translationHistory.filter { $0.timestamp != appState.currentTranslation?.timestamp }, id: \.timestamp) { result in
                            TranslationBlockView(
                                result: result,
                                isActive: false,
                                displayMode: appState.configStore.config.displayMode,
                                onRetranslate: { text in appState.retranslate(text) },
                                onWordLookup: { word in appState.lookupWord(word) }
                            )
                        }
                    }
                    .padding(.vertical, 16)
                    .padding(.horizontal, 24)
                }
                .onChange(of: appState.currentTranslation?.timestamp) { _, timestamp in
                    guard timestamp != nil else { return }
                    DispatchQueue.main.async {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo("current", anchor: .top)
                        }
                    }
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
