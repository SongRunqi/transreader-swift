import SwiftUI

struct VocabView: View {
    @Bindable var vocabStore: VocabStore
    
    @State private var searchQuery = ""
    @State private var selectedWord: VocabEntry?
    
    var filteredWords: [VocabEntry] {
        if searchQuery.isEmpty {
            return vocabStore.data.words
        } else {
            return vocabStore.searchWords(searchQuery)
        }
    }
    
    var body: some View {
        NavigationSplitView {
            VStack {
                // Search bar
                TextField("搜索生词...", text: $searchQuery)
                    .textFieldStyle(.roundedBorder)
                    .padding()
                
                // Word list
                List(selection: $selectedWord) {
                    ForEach(filteredWords, id: \.word) { entry in
                        VocabEntryRow(entry: entry)
                            .tag(entry)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    _ = vocabStore.removeWord(entry.word)
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                            }
                    }
                }
                .listStyle(.sidebar)
                
                // Statistics
                HStack {
                    Text("共 \(vocabStore.data.words.count) 个生词")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding()
            }
            .navigationTitle("生词本")
        } detail: {
            if let selected = selectedWord {
                VocabDetailView(entry: selected, vocabStore: vocabStore)
            } else {
                PlaceholderView2()
            }
        }
    }
}

struct VocabEntryRow: View {
    let entry: VocabEntry
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.word)
                .font(.headline)
            
            if let firstMeaning = entry.meanings?.first {
                Text(firstMeaning)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            
            if !entry.addedAt.isEmpty {
                Text(formatDate(entry.addedAt))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
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

struct VocabDetailView: View {
    let entry: VocabEntry
    @Bindable var vocabStore: VocabStore
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Word + Phonetic
                VStack(alignment: .leading) {
                    Text(entry.word)
                        .font(.largeTitle)
                        .bold()
                    
                    if let phonetic = entry.phonetic {
                        Text("/\(phonetic)/")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Divider()
                
                // Meanings
                if let meanings = entry.meanings, !meanings.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("释义")
                            .font(.headline)
                        
                        ForEach(Array(meanings.enumerated()), id: \.offset) { _, meaning in
                            HStack(alignment: .top) {
                                Text("•")
                                Text(meaning)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }
                
                // Examples
                if let examples = entry.examples, !examples.isEmpty {
                    Divider()
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("例句")
                            .font(.headline)
                        
                        ForEach(Array(examples.enumerated()), id: \.offset) { _, example in
                            Text(example)
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }
                
                // Synonyms
                if let synonyms = entry.synonyms, !synonyms.isEmpty {
                    Divider()
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("近义词")
                            .font(.headline)
                        
                        ForEach(Array(synonyms.enumerated()), id: \.offset) { _, synonym in
                            Text(synonym)
                                .font(.body)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                
                // Added date
                if !entry.addedAt.isEmpty {
                    Divider()
                    
                    HStack {
                        Text("添加时间：")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        Text(formatDate(entry.addedAt))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
                
                // Delete button
                Button(role: .destructive) {
                    _ = vocabStore.removeWord(entry.word)
                } label: {
                    Label("从生词本删除", systemImage: "trash")
                }
                .buttonStyle(.bordered)
            }
            .padding()
        }
        .navigationTitle("生词详情")
    }
    
    private func formatDate(_ iso8601: String) -> String {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: iso8601) {
            let displayFormatter = DateFormatter()
            displayFormatter.dateStyle = .medium
            displayFormatter.timeStyle = .short
            return displayFormatter.string(from: date)
        }
        return iso8601
    }
}

struct PlaceholderView2: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "book")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            
            Text("选择一个生词查看详情")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
