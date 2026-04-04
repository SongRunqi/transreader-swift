import SwiftUI
import AppKit
import UniformTypeIdentifiers

enum VocabSortOrder: String, CaseIterable {
    case dateDesc = "最新"
    case alphabetical = "A-Z"
}

struct VocabView: View {
    @Bindable var vocabStore: VocabStore

    @State private var searchQuery = ""
    @State private var selectedWord: VocabEntry?
    @State private var sortOrder: VocabSortOrder = .dateDesc
    @State private var importResultMessage: String?

    var filteredWords: [VocabEntry] {
        let base = searchQuery.isEmpty ? vocabStore.data.words : vocabStore.searchWords(searchQuery)
        switch sortOrder {
        case .dateDesc:
            return base.reversed()
        case .alphabetical:
            return base.sorted { $0.word.lowercased() < $1.word.lowercased() }
        }
    }

    var body: some View {
        if vocabStore.data.words.isEmpty {
            emptyState
        } else {
            vocabContent
        }
    }

    // MARK: - Empty State
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "book")
                .font(.system(size: 48))
                .foregroundStyle(Theme.textSecondary.opacity(0.3))

            VStack(spacing: 8) {
                Text("词库为空")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)

                Text("双击翻译结果中的英文单词可查词并添加")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary.opacity(0.7))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg)
    }

    // MARK: - Vocab Content
    private var vocabContent: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)

                TextField("搜索生词...", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))

                if !searchQuery.isEmpty {
                    Button {
                        searchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
            .background(Theme.tertiaryBg)
            .cornerRadius(8)
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 8)

            // Toolbar: stats + sort + export/import
            HStack(spacing: 8) {
                Text("共 \(vocabStore.data.words.count) 个生词")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)

                Spacer()

                Picker("", selection: $sortOrder) {
                    ForEach(VocabSortOrder.allCases, id: \.self) { order in
                        Text(order.rawValue).tag(order)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 100)

                Button {
                    exportVocab()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                }
                .buttonStyle(.plain)
                .help("导出词库")

                Button {
                    importVocab()
                } label: {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                }
                .buttonStyle(.plain)
                .help("导入词库")
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 8)

            Divider()
                .foregroundColor(Theme.border)

            // Word list
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filteredWords, id: \.word) { entry in
                        VocabCardView(entry: entry, isSelected: selectedWord == entry) {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                if selectedWord == entry {
                                    selectedWord = nil
                                } else {
                                    selectedWord = entry
                                }
                            }
                        } onDelete: {
                            withAnimation {
                                _ = vocabStore.removeWord(entry.word)
                                if selectedWord == entry {
                                    selectedWord = nil
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
            }
        }
        .background(Theme.bg)
        .alert("导入结果", isPresented: .constant(importResultMessage != nil)) {
            Button("确定") { importResultMessage = nil }
        } message: {
            if let msg = importResultMessage {
                Text(msg)
            }
        }
    }

    // MARK: - Export / Import

    private func exportVocab() {
        guard let data = vocabStore.exportData() else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "vocab.json"
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? data.write(to: url, options: .atomic)
    }

    private func importVocab() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url,
              let data = try? Data(contentsOf: url) else { return }

        if let result = vocabStore.importData(data) {
            importResultMessage = "新增 \(result.added) 个单词，跳过 \(result.skipped) 个重复"
        } else {
            importResultMessage = "文件格式错误，导入失败"
        }
    }
}

// MARK: - Vocab Card
struct VocabCardView: View {
    let entry: VocabEntry
    let isSelected: Bool
    let onTap: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Collapsed card (always visible)
            Button(action: onTap) {
                VStack(alignment: .leading, spacing: 4) {
                    // Row 1: word + pos badge
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(entry.word)
                            .font(.system(size: 16, weight: .semibold, design: .serif))
                            .foregroundStyle(Theme.textPrimary)

                        if let pos = entry.pos, !pos.isEmpty {
                            Text(pos.uppercased())
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(Theme.accent)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Theme.accent.opacity(0.1))
                                .cornerRadius(3)
                        }

                        Spacer()

                        Text(entry.addedAt.prefix(10))
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.textSecondary.opacity(0.5))
                    }

                    // Row 2: Chinese meaning (short summary)
                    let shortMeaning: String? = {
                        if let zh = entry.zh, !zh.isEmpty { return zh }
                        if let m = entry.meanings, let first = m.first, !first.isEmpty { return first.stripHTML() }
                        return nil
                    }()
                    if let text = shortMeaning {
                        Text(text)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                    }

                    // Row 3: context (truncated)
                    if let context = entry.context, !context.isEmpty {
                        Text(context)
                            .font(.system(size: 12, design: .serif))
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Expanded detail
            if isSelected {
                VStack(alignment: .leading, spacing: 12) {
                    // Full meaning (split by `;` into separate lines)
                    if let meaning = entry.meaning, !meaning.isEmpty {
                        let parts = meaning.components(separatedBy: ";")
                            .map { $0.trimmingCharacters(in: .whitespaces).stripHTML() }
                            .filter { !$0.isEmpty }
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                                Text(part)
                                    .font(.system(size: 13))
                                    .foregroundStyle(Theme.textPrimary)
                                    .textSelection(.enabled)
                            }
                        }
                    }

                    // Swift-sourced meanings (from DictionaryEntry)
                    if let meanings = entry.meanings, !meanings.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(meanings.enumerated()), id: \.offset) { _, m in
                                Text(m.stripHTML())
                                    .font(.system(size: 13))
                                    .foregroundStyle(Theme.textPrimary)
                                    .textSelection(.enabled)
                            }
                        }
                    }

                    // Examples
                    if let examples = entry.examples, !examples.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("例句")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Theme.textSecondary)
                            ForEach(Array(examples.enumerated()), id: \.offset) { _, ex in
                                Text(ex)
                                    .font(.system(size: 12))
                                    .foregroundStyle(Theme.textSecondary)
                                    .textSelection(.enabled)
                            }
                        }
                    }

                    // Synonyms
                    if let synonyms = entry.synonyms, !synonyms.isEmpty {
                        HStack(spacing: 4) {
                            Text("近义:")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Theme.textSecondary)
                            Text(synonyms.joined(separator: " · "))
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.accent)
                        }
                    }

                    // Context (full, untruncated)
                    if let context = entry.context, !context.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("记忆上下文")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Theme.textSecondary)
                            Text(context)
                                .font(.system(size: 12, design: .serif))
                                .foregroundStyle(Theme.textPrimary.opacity(0.8))
                                .textSelection(.enabled)
                        }
                    }

                    // Delete
                    HStack {
                        Spacer()
                        Button { onDelete() } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.textSecondary.opacity(0.5))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.bottom, 10)
                .transition(.opacity)
            }

            Divider()
                .foregroundColor(Theme.border.opacity(0.5))
        }
    }

    private func formatDate(_ iso8601: String) -> String {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: iso8601) {
            let displayFormatter = DateFormatter()
            displayFormatter.dateStyle = .short
            displayFormatter.timeStyle = .none
            return displayFormatter.string(from: date)
        }
        return iso8601
    }
}
