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
    @State private var filterUrl: String?
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
                filterUrl = nil
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
            if let date = selectedDate { loadTranslations(date: date) }
        }
        .onChange(of: filterUrl) { _, _ in
            if let date = selectedDate { loadTranslations(date: date) }
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
                        DateRowButton(
                            dateEntry: dateEntry,
                            isSelected: selectedDate == dateEntry.date,
                            displayText: formatDateDisplay(dateEntry.date)
                        ) {
                            selectedDate = dateEntry.date
                            filterApp = nil
                            filterUrl = nil
                            loadGroups(date: dateEntry.date)
                            loadTranslations(date: dateEntry.date)
                        }

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
                    let items = searchResults.flatMap { saved in
                        saved.sentences.enumerated().map { (i, sentence) in
                            ReadingItem(
                                id: "\(saved.timestamp.timeIntervalSince1970)_\(i)",
                                sentence: sentence,
                                timestamp: saved.timestamp
                            )
                        }
                    }
                    LazyVStack(spacing: 0) {
                        ForEach(items, id: \.id) { item in
                            readingItemView(item)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
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
                            let domain = extractDomain(group.sourceUrl)
                            let isFiltered = filterApp == group.sourceApp && filterUrl == group.sourceUrl

                            Button {
                                if isFiltered {
                                    filterApp = nil
                                    filterUrl = nil
                                } else {
                                    filterApp = group.sourceApp
                                    filterUrl = group.sourceUrl
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Text(appName)
                                        .font(.system(size: 11))
                                        .foregroundStyle(isFiltered ? .white : Theme.textPrimary)
                                    if !domain.isEmpty {
                                        Text(domain)
                                            .font(.system(size: 10))
                                            .foregroundStyle(isFiltered ? .white.opacity(0.7) : Theme.textSecondary)
                                    }
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

            // Translations (per-sentence items)
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(allSentenceItems, id: \.id) { item in
                        readingItemView(item)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
        }
    }

    // Flatten translations into per-sentence items with unique ids
    private struct ReadingItem: Identifiable {
        let id: String  // "timestamp_sentenceIndex"
        let sentence: Sentence
        let timestamp: Date
    }

    private var allSentenceItems: [ReadingItem] {
        translations.flatMap { saved in
            saved.sentences.enumerated().map { (i, sentence) in
                ReadingItem(
                    id: "\(saved.timestamp.timeIntervalSince1970)_\(i)",
                    sentence: sentence,
                    timestamp: saved.timestamp
                )
            }
        }
    }

    private func readingItemView(_ item: ReadingItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.sentence.en)
                .font(.system(size: 13.5, design: .serif))
                .foregroundStyle(Theme.textPrimary)
                .lineSpacing(4)
                .textSelection(.enabled)

            Text(item.sentence.zh)
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.textSecondary)
                .lineSpacing(3)
                .textSelection(.enabled)

            HStack(spacing: 6) {
                if let analysis = item.sentence.analysis {
                    if !analysis.structure.isEmpty {
                        Text(analysis.structure)
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.textSecondary.opacity(0.7))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Theme.tertiaryBg)
                            .cornerRadius(3)
                    }
                    if !analysis.tense.isEmpty {
                        Text(analysis.tense)
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.textSecondary.opacity(0.7))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Theme.tertiaryBg)
                                .cornerRadius(3)
                        }
                    }
                    Spacer()
                    Text(formatTime(item.timestamp))
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.textSecondary.opacity(0.5))
                }
                .padding(.top, 2)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 4)
            .overlay(alignment: .bottom) {
                Divider().foregroundColor(Theme.border.opacity(0.3))
            }
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
        translations = translationStore.getTranslations(date: date, sourceApp: filterApp, sourceUrl: filterUrl)
        appLog("[Reading] Loaded \(translations.count) translations for \(date), total sentences: \(translations.reduce(0) { $0 + $1.sentences.count })")
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

    private func extractDomain(_ url: String) -> String {
        guard !url.isEmpty, let parsed = URL(string: url), let host = parsed.host else { return "" }
        // Strip "www." prefix
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}

// MARK: - Date Row Button (with hover)
private struct DateRowButton: View {
    let dateEntry: TranslationStore.ReadingDate
    let isSelected: Bool
    let displayText: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(displayText)
                        .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? Theme.accent : Theme.textPrimary)

                    Text("\(dateEntry.translationCount) 句")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .background(isSelected ? Theme.accent.opacity(0.08) : isHovered ? Theme.textSecondary.opacity(0.06) : Color.clear)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Stats Tab
struct StatsView: View {
    let translationStore: TranslationStore
    @State private var stats: TranslationStore.ReadingStats?
    @State private var dailyCounts: [String: Int] = [:]  // "YYYY-MM-DD" -> sentence count

    var body: some View {
        GeometryReader { geo in
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 20) {
                if let stats = stats {
                    // Stats grid: 2x2
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        statPill("今日", translations: stats.todayTranslations, lookups: stats.todayLookups)
                        statPill("本周", translations: stats.weekTranslations, lookups: stats.weekLookups)
                        statPill("本月", translations: stats.monthTranslations, lookups: stats.monthLookups)
                        statPill("累计", translations: stats.totalTranslations, lookups: stats.totalLookups)
                    }

                    // Contribution calendar
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("阅读活跃度")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Theme.textPrimary)
                            Spacer()
                            // Legend inline with title
                            HStack(spacing: 3) {
                                Text("少")
                                    .font(.system(size: 9))
                                    .foregroundStyle(Theme.textSecondary)
                                ForEach([0.0, 0.25, 0.5, 0.75, 1.0], id: \.self) { level in
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(level == 0 ? Theme.tertiaryBg : Theme.accent.opacity(0.2 + level * 0.8))
                                        .frame(width: 10, height: 10)
                                }
                                Text("多")
                                    .font(.system(size: 9))
                                    .foregroundStyle(Theme.textSecondary)
                            }
                        }

                        ContributionCalendar(dailyCounts: dailyCounts)
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Theme.cardBg)
                    )
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border.opacity(0.5), lineWidth: 1))

                    // Active Apps
                    if !stats.activeApps.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("常用应用")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Theme.textSecondary)
                            FlowLayout(spacing: 6) {
                                ForEach(stats.activeApps, id: \.self) { app in
                                    Text(app)
                                        .font(.system(size: 11))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Theme.tertiaryBg)
                                        .cornerRadius(4)
                                }
                            }
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.cardBg)
                        .cornerRadius(10)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border.opacity(0.5), lineWidth: 1))
                    }

                    // Top URLs
                    if !stats.topUrls.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("热门来源")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Theme.textSecondary)
                            VStack(spacing: 4) {
                                ForEach(stats.topUrls.prefix(5), id: \.url) { item in
                                    HStack {
                                        Text(extractDomain(item.url))
                                            .font(.system(size: 11))
                                            .foregroundStyle(Theme.textPrimary)
                                            .lineLimit(1)
                                        Spacer()
                                        Text("\(item.count)")
                                            .font(.system(size: 10, weight: .medium))
                                            .foregroundStyle(Theme.accent)
                                    }
                                }
                            }
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.cardBg)
                        .cornerRadius(10)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border.opacity(0.5), lineWidth: 1))
                    }
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .padding(20)
            .frame(width: geo.size.width)
        }
        }
        .background(Theme.bg)
        .onAppear {
            stats = translationStore.getStats()
            loadDailyCounts()
        }
    }

    private func statPill(_ label: String, translations: Int, lookups: Int) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            HStack(spacing: 10) {
                HStack(spacing: 3) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.accent)
                    Text("\(translations)")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)
                }
                HStack(spacing: 3) {
                    Image(systemName: "book")
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.teal)
                    Text("\(lookups)")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Theme.cardBg)
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border.opacity(0.5), lineWidth: 1))
    }

    private func extractDomain(_ url: String) -> String {
        guard !url.isEmpty, let parsed = URL(string: url), let host = parsed.host else { return url }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    private func loadDailyCounts() {
        let dates = translationStore.getReadingDates(limit: 365)
        dailyCounts = Dictionary(uniqueKeysWithValues: dates.map { ($0.date, $0.translationCount) })
    }
}

// MARK: - Calendar hover state (shared across all cells)
class CalendarHoverState: ObservableObject {
    @Published var hoveredKey: String?
    @Published var hoveredCount: Int = 0
    @Published var hoveredPosition: CGPoint = .zero
}

// MARK: - GitHub-style Contribution Calendar
struct ContributionCalendar: View {
    let dailyCounts: [String: Int]
    @StateObject private var hover = CalendarHoverState()
    private let cellSpacing: CGFloat = 3
    private let labelWidth: CGFloat = 28
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f
    }()
    private static let monthFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "M月"; return f
    }()

    private var maxCount: Int { max(dailyCounts.values.max() ?? 1, 1) }

    private struct WeekData {
        let days: [Date]
        let monthLabel: String?  // shown on first week of each month
    }

    private func generateWeeks(count: Int) -> [WeekData] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let weekday = cal.component(.weekday, from: today) // 1=Sun

        var result: [WeekData] = []
        var labeledMonths: Set<Int> = []

        for weekOffset in stride(from: count - 1, through: 0, by: -1) {
            let days = (0..<7).map { day in
                cal.date(byAdding: .day, value: -(weekOffset * 7) + day - (7 - weekday), to: today)!
            }
            // Check if this week contains the 1st of any month
            var label: String? = nil
            for date in days {
                if cal.component(.day, from: date) == 1 {
                    let month = cal.component(.month, from: date)
                    if !labeledMonths.contains(month) {
                        label = Self.monthFormatter.string(from: date)
                        labeledMonths.insert(month)
                    }
                    break
                }
            }
            result.append(WeekData(days: days, monthLabel: label))
        }
        return result
    }

    private func dateKey(_ date: Date) -> String { Self.dateFormatter.string(from: date) }

    private func cellColor(_ date: Date) -> Color {
        let count = dailyCounts[dateKey(date)] ?? 0
        if count == 0 { return Theme.tertiaryBg }
        return Theme.accent.opacity(0.15 + min(Double(count) / Double(maxCount), 1.0) * 0.85)
    }

    var body: some View {
        GeometryReader { geo in
            let availableWidth = geo.size.width - labelWidth
            let cellSize: CGFloat = 12
            let weekCount = Int(availableWidth / (cellSize + cellSpacing))
            let weeks = generateWeeks(count: weekCount)
            let gridWidth = labelWidth + cellSpacing + CGFloat(weekCount) * (cellSize + cellSpacing)

            VStack(alignment: .leading, spacing: 2) {
                // Month labels — positioned at each month's first week column
                ZStack(alignment: .topLeading) {
                    Color.clear.frame(height: 14)
                    ForEach(Array(weeks.enumerated()), id: \.offset) { i, week in
                        if let label = week.monthLabel {
                            Text(label)
                                .font(.system(size: 9))
                                .foregroundStyle(Theme.textSecondary)
                                .fixedSize()
                                .offset(x: labelWidth + cellSpacing + CGFloat(i) * (cellSize + cellSpacing))
                        }
                    }
                }

                // Grid: day labels + cells
                HStack(spacing: cellSpacing) {
                    // Day of week labels
                    VStack(spacing: cellSpacing) {
                        ForEach(["日", "一", "", "三", "", "五", ""], id: \.self) { label in
                            Text(label)
                                .font(.system(size: 9))
                                .foregroundStyle(Theme.textSecondary)
                                .frame(width: labelWidth, height: cellSize, alignment: .trailing)
                        }
                    }

                    // Week columns
                    ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                        VStack(spacing: cellSpacing) {
                            ForEach(Array(week.days.enumerated()), id: \.offset) { _, date in
                                let key = dateKey(date)
                                let count = dailyCounts[key] ?? 0
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(cellColor(date))
                                    .frame(width: cellSize, height: cellSize)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 2)
                                            .stroke(hover.hoveredKey == key ? Theme.accent : Color.clear, lineWidth: 1)
                                    )
                                    .onHover { h in
                                        if h {
                                            hover.hoveredKey = key
                                            hover.hoveredCount = count
                                        } else if hover.hoveredKey == key {
                                            hover.hoveredKey = nil
                                        }
                                    }
                            }
                        }
                    }
                }
            }
            .frame(width: gridWidth)
            .frame(maxWidth: .infinity)
            .overlay(alignment: .topLeading) {
                if let key = hover.hoveredKey {
                    Text(hover.hoveredCount > 0 ? "\(hover.hoveredCount) 句 · \(key)" : key)
                        .font(.system(size: 10))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(0.85))
                        .cornerRadius(5)
                        .fixedSize()
                        .position(tooltipPosition(for: key, cellSize: cellSize, weeks: weeks, gridWidth: gridWidth))
                        .allowsHitTesting(false)
                        .animation(.none, value: key)
                }
            }
        }
        .frame(height: 12 * 7 + 3 * 6 + 20)
    }

    private func tooltipPosition(for key: String, cellSize: CGFloat, weeks: [WeekData], gridWidth: CGFloat) -> CGPoint {
        // Find the week and day index for this key
        for (wi, week) in weeks.enumerated() {
            for (di, date) in week.days.enumerated() {
                if dateKey(date) == key {
                    let x = labelWidth + cellSpacing + CGFloat(wi) * (cellSize + cellSpacing) + cellSize / 2
                    let y = 14 + 2 + CGFloat(di) * (cellSize + cellSpacing) - 10 // above the cell
                    // Center horizontally, clamp to grid bounds
                    let clampedX = min(max(x, 50), gridWidth - 50)
                    return CGPoint(x: clampedX, y: max(y, 6))
                }
            }
        }
        return .zero
    }
}
