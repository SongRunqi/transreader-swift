import SwiftUI

struct TranslationDetailView: View {
    let result: TranslationResult
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                HStack {
                    VStack(alignment: .leading) {
                        Text("来源: \(result.source.rawValue)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        Text("耗时: \(result.elapsedMs)ms")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    Text(result.timestamp, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
                
                Divider()
                
                // Sentences
                ForEach(Array(result.sentences.enumerated()), id: \.offset) { _, sentence in
                    SentenceView(sentence: sentence)
                        .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
    }
}

struct SentenceView: View {
    let sentence: Sentence
    @State private var analysisExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // English
            Text(sentence.en)
                .font(.body)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
            
            // Chinese
            Text(sentence.zh)
                .font(.body)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            
            // Analysis (if complete)
            if let analysis = sentence.analysis, !sentence.isPartial {
                DisclosureGroup("语法分析", isExpanded: $analysisExpanded) {
                    AnalysisView(analysis: analysis)
                        .padding(.top, 8)
                }
                .font(.subheadline)
            } else if sentence.isPartial {
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    Text("分析中...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 8)
    }
}

struct AnalysisView: View {
    let analysis: Analysis
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Structure & Tense
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("结构").font(.caption).bold()
                    Text(analysis.structure).font(.caption)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("时态").font(.caption).bold()
                    Text(analysis.tense).font(.caption)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            Divider()
            
            // Chunks
            VStack(alignment: .leading, spacing: 8) {
                Text("意群切分").font(.caption).bold()
                ForEach(Array(analysis.chunks.enumerated()), id: \.offset) { _, chunk in
                    ChunkView(chunk: chunk, depth: 0)
                }
            }
            
            Divider()
            
            // Tip
            VStack(alignment: .leading, spacing: 4) {
                Text("语法提示").font(.caption).bold()
                Text(analysis.tip)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color(nsColor: .textBackgroundColor))
        .cornerRadius(8)
    }
}

struct ChunkView: View {
    let chunk: Chunk
    let depth: Int
    @State private var expanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top) {
                // Indentation
                if depth > 0 {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.3))
                        .frame(width: 2)
                        .padding(.leading, CGFloat(depth * 12))
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(chunk.role)
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.2))
                            .cornerRadius(4)
                        
                        if let children = chunk.children, !children.isEmpty {
                            Image(systemName: expanded ? "chevron.down" : "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .onTapGesture {
                                    withAnimation {
                                        expanded.toggle()
                                    }
                                }
                        }
                    }
                    
                    Text(chunk.en)
                        .font(.caption)
                        .foregroundStyle(.primary)
                    
                    Text(chunk.zh)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            // Children
            if let children = chunk.children, !children.isEmpty, expanded {
                ForEach(Array(children.enumerated()), id: \.offset) { _, child in
                    ChunkView(chunk: child, depth: depth + 1)
                        .padding(.leading, 12)
                }
            }
        }
    }
}
