import SwiftUI

// MARK: - Reading History Tab
struct ReadingView: View {
    let translationStore: TranslationStore
    @State private var readingDates: [TranslationStore.ReadingDate] = []
    @State private var selectedDate: String?
    @State private var groups: [TranslationStore.ReadingGroup] = []
    @State private var translations: [SavedTranslation] = []

    // Search & filter state
    @State private var searchQuery: String = ""
    @State private var filterApp: String?
    @State private var searchResults: [SavedTranslation] = []
    @State private var searchTask: Task<Void, Never>?

    private var isSearchMode: Bool { !searchQuery.isEmpty }

    var body: some View {
        HStack(spacing: 0) {
            // Date list (left panel) — dimmed in search mode
            dateList
                .frame(width: 200)
                .opacity(isSearchMode ? 0.4 : 1.0)
                .allowsHitTesting(!isSearchMode)

            Divider()

            // Content (right panel)
            VStack(spacing: 0) {
                // Search bar
                searchBar

                Divider()

                if isSearchMode {
                    searchResultsContent
                } else if let date = selectedDate {
                    dateContent(date: date)
                } else {
                    emptyState
                }
            }
        }
        .background(Theme.bg)
        .onAppear {
            loadDates()
        }
        .onChange(of: searchQuery) { _, newValue in
            searchTask?.cancel()
            if newValue.isEmpty {
                searchResults = []
                filterApp = nil
                return
            }
            searchTask = Task {
                try? await Task.sleep(nanoseconds: 300_000_000) // 300ms debounce
                guard !Task.isCancelled else { return }
                let results = translationStore.searchTranslations(
                    query: newValue,
                    sourceApp: filterApp
                )
                await MainActor.run {
                    searchResults = results
                }
            }
        }
        .onChange(of: filterApp) { _, _ in
            if isSearchMode {
                // Re-search with new filter
                let query = searchQuery
                searchTask?.cancel()
                searchTask = Task {
                    let results = translationStore.searchTranslations(
                        query: query,
                        sourceApp: filterApp
                    )
                    await MainActor.run {
                        searchResults = results
                    }
                }
            } else if let date = selectedDate {
                // Filter within current date
                loadTranslations(date: date)
            }
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)

            TextField("搜索翻译历史...", text: $searchQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 13))

            if !searchQuery.isEmpty {
                Button {
                    searchQuery = ""
                    filterApp = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                }
                .buttonStyle(.plain)
            }

            // App filter picker
            if let apps = distinctApps, !apps.isEmpty {
                Menu {
                    Button("全部应用") {
                        filterApp = nil
                    }
                    Divider()
                    ForEach(apps, id: \.self) { app in
                        Button(app) {
                            filterApp = filterApp == app ? nil : app
                        }
                    }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .font(.system(size: 12))
                        if let app = filterApp {
                            Text(app)
                                .font(.system(size: 11))
                                .lineLimit(1)
                        }
                    }
                    .foregroundStyle(filterApp != nil ? Theme.accent : Theme.textSecondary)
                }
                .menuStyle(.borderlessButton)
                .frame(width: filterApp != nil ? nil : 20)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.cardBg)
    }

    @State private var _distinctApps: [String]?
    private var distinctApps: [String]? {
        if _distinctApps == nil {
            DispatchQueue.main.async {
                _distinctApps = translationStore.getDistinctSourceApps()
            }
        }
        return _distinctApps
    }

    // MARK: - Date List

    private var dateList: some View {
        VStack(spacing: 0) {
            HStack {
                Text("阅读记录")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Button {
                    loadDates()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(readingDates, id: \.date) { dateEntry in
                        Button {
                            selectedDate = dateEntry.date
                            loadGroups(date: dateEntry.date)
                            loadTranslations(date: dateEntry.date)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(formatDateDisplay(dateEntry.date))
                                        .font(.system(size: 13, weight: selectedDate == dateEntry.date ? .semibold : .regular))
                                        .foregroundStyle(selectedDate == dateEntry.date ? Theme.accent : Theme.textPrimary)

                                    HStack(spacing: 8) {
                                        if dateEntry.translationCount > 0 {
                                            Text("\(dateEntry.translationCount) 翻译")
                                                .font(.system(size: 10))
                                                .foregroundStyle(Theme.textSecondary)
                                        }
                                        if dateEntry.lookupCount > 0 {
                                            Text("\(dateEntry.lookupCount) 查词")
                                                .font(.system(size: 10))
                                                .foregroundStyle(Theme.textSecondary)
                                        }
                                    }
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(selectedDate == dateEntry.date ? Theme.accent.opacity(0.08) : Color.clear)
                        }
                        .buttonStyle(.plain)

                        Divider()
                            .padding(.leading, 16)
                    }
                }
            }
        }
        .background(Theme.cardBg)
    }

    // MARK: - Search Results Content

    private var searchResultsContent: some View {
        VStack(spacing: 0) {
            HStack {
                Text("搜索结果: \(searchResults.count) 条")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            if searchResults.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 36))
                        .foregroundStyle(Theme.textSecondary.opacity(0.3))
                    Text("未找到匹配结果")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(searchResults, id: \.timestamp) { saved in
                            savedTranslationCard(saved)
                        }
                    }
                    .padding(16)
                }
            }
        }
    }

    // MARK: - Date Content

    private func dateContent(date: String) -> some View {
        VStack(spacing: 0) {
            // Groups header — clickable as filters
            if !groups.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(formatDateDisplay(date)) 阅读来源")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)

                    FlowLayout(spacing: 8) {
                        ForEach(groups, id: \.self) { group in
                            let appName = group.sourceApp.isEmpty ? "未知" : group.sourceApp
                            let isFiltered = filterApp == group.sourceApp

                            Button {
                                filterApp = isFiltered ? nil : group.sourceApp
                            } label: {
                                HStack(spacing: 4) {
                                    Text(appName)
                                        .font(.system(size: 11))
                                        .foregroundStyle(isFiltered ? .white : Theme.textPrimary)
                                    Text("×\(group.count)")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(isFiltered ? .white.opacity(0.8) : Theme.accent)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(isFiltered ? Theme.accent : Theme.tertiaryBg)
                                .cornerRadius(6)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(16)

                Divider()
            }

            // Translations
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(translations, id: \.timestamp) { saved in
                        savedTranslationCard(saved)
                    }
                }
                .padding(16)
            }
        }
    }

    private func savedTranslationCard(_ saved: SavedTranslation) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(formatTime(saved.timestamp))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary)

                if saved.elapsedMs > 0 {
                    Text("(\(String(format: "%.1fs", Double(saved.elapsedMs) / 1000.0)))")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary.opacity(0.7))
                }

                Spacer()

                if !saved.sourceApp.isEmpty {
                    Text(saved.sourceApp)
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.textSecondary.opacity(0.5))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.tertiaryBg)
                        .cornerRadius(3)
                }
            }

            ForEach(Array(saved.sentences.enumerated()), id: \.offset) { _, sentence in
                VStack(alignment: .leading, spacing: 4) {
                    Text(sentence.en)
                        .font(Theme.englishFont)
                        .foregroundStyle(Theme.textPrimary)
                        .textSelection(.enabled)
                    Text(sentence.zh)
                        .font(Theme.chineseFont)
                        .foregroundStyle(Theme.textSecondary)
                        .textSelection(.enabled)
                }
            }
        }
        .padding(16)
        .background(Theme.cardBg)
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Theme.border.opacity(0.5), lineWidth: 1)
        )
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "calendar")
                .font(.system(size: 48))
                .foregroundStyle(Theme.textSecondary.opacity(0.3))

            Text("选择日期查看阅读记录")
                .font(.system(size: 14))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Data Loading

    private func loadDates() {
        readingDates = translationStore.getReadingDates()
        if selectedDate == nil, let first = readingDates.first {
            selectedDate = first.date
            loadGroups(date: first.date)
            loadTranslations(date: first.date)
        }
    }

    private func loadGroups(date: String) {
        groups = translationStore.getReadingGroups(date: date)
    }

    private func loadTranslations(date: String) {
        translations = translationStore.getTranslations(date: date, sourceApp: filterApp)
    }

    // MARK: - Formatting

    private func formatDateDisplay(_ dateStr: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: dateStr) else { return dateStr }

        let display = DateFormatter()
        display.dateFormat = "M月d日 EEEE"
        display.locale = Locale(identifier: "zh_CN")
        return display.string(from: date)
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
}

// MARK: - Stats Tab
struct StatsView: View {
    let translationStore: TranslationStore
    @State private var stats: TranslationStore.ReadingStats?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if let stats = stats {
                    // Today
                    statSection("今日") {
                        HStack(spacing: 24) {
                            statCard(value: stats.todayTranslations, label: "翻译", icon: "doc.text")
                            statCard(value: stats.todayLookups, label: "查词", icon: "book")
                        }
                    }

                    // This week
                    statSection("本周") {
                        HStack(spacing: 24) {
                            statCard(value: stats.weekTranslations, label: "翻译", icon: "doc.text")
                            statCard(value: stats.weekLookups, label: "查词", icon: "book")
                        }
                    }

                    // This month
                    statSection("本月") {
                        HStack(spacing: 24) {
                            statCard(value: stats.monthTranslations, label: "翻译", icon: "doc.text")
                            statCard(value: stats.monthLookups, label: "查词", icon: "book")
                        }
                    }

                    // Total
                    statSection("累计") {
                        HStack(spacing: 24) {
                            statCard(value: stats.totalTranslations, label: "翻译", icon: "doc.text")
                            statCard(value: stats.totalLookups, label: "查词", icon: "book")
                        }
                    }

                    // Active Apps
                    if !stats.activeApps.isEmpty {
                        statSection("常用应用") {
                            FlowLayout(spacing: 8) {
                                ForEach(stats.activeApps, id: \.self) { app in
                                    Text(app)
                                        .font(.system(size: 12))
                                        .foregroundStyle(Theme.textPrimary)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(Theme.tertiaryBg)
                                        .cornerRadius(6)
                                }
                            }
                        }
                    }

                    // Top URLs
                    if !stats.topUrls.isEmpty {
                        statSection("热门来源") {
                            VStack(spacing: 8) {
                                ForEach(stats.topUrls, id: \.url) { item in
                                    HStack {
                                        Text(item.url)
                                            .lineLimit(1)
                                            .font(.system(size: 12))
                                            .foregroundStyle(Theme.textPrimary)
                                        Spacer()
                                        Text("\(item.count)")
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundStyle(Theme.accent)
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Theme.tertiaryBg)
                                    .cornerRadius(6)
                                }
                            }
                        }
                    }
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .padding(24)
        }
        .background(Theme.bg)
        .onAppear {
            stats = translationStore.getStats()
        }
    }

    private func statSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            content()
        }
    }

    private func statCard(value: Int, label: String, icon: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(Theme.accent)

            Text("\(value)")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)

            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(Theme.cardBg)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Theme.border.opacity(0.5), lineWidth: 1)
        )
    }
}
