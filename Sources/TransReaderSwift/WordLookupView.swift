import SwiftUI
import AVFoundation

struct WordLookupView: View {
    let entry: DictionaryEntry
    let onAddToVocab: () -> Void
    
    @State private var audioPlayer: AVAudioPlayer?
    @State private var isPlaying = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Word + Phonetic + Audio
                HStack(alignment: .top) {
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
                    
                    Spacer()
                    
                    // Audio button
                    Button(action: playAudio) {
                        Image(systemName: isPlaying ? "speaker.wave.3.fill" : "speaker.wave.2")
                            .font(.title2)
                    }
                    .buttonStyle(.borderless)
                    .disabled(isPlaying)
                    
                    // Add to vocab button
                    Button(action: onAddToVocab) {
                        Image(systemName: "plus.circle")
                            .font(.title2)
                    }
                    .buttonStyle(.borderless)
                }
                
                Divider()
                
                // Meanings
                if !entry.meanings.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("释义")
                            .font(.headline)
                        
                        ForEach(Array(entry.meanings.enumerated()), id: \.offset) { _, meaning in
                            HStack(alignment: .top) {
                                Text("•")
                                Text(meaning)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }
                
                // Examples
                if !entry.examples.isEmpty {
                    Divider()
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("例句")
                            .font(.headline)
                        
                        ForEach(Array(entry.examples.enumerated()), id: \.offset) { _, example in
                            Text(example)
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }
                
                // Synonyms
                if !entry.synonyms.isEmpty {
                    Divider()
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("近义词")
                            .font(.headline)
                        
                        ForEach(Array(entry.synonyms.enumerated()), id: \.offset) { _, synonym in
                            Text(synonym)
                                .font(.body)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                
                // Related words
                if !entry.relatedWords.isEmpty {
                    Divider()
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("相关词")
                            .font(.headline)
                        
                        FlowLayout(spacing: 8) {
                            ForEach(Array(entry.relatedWords.enumerated()), id: \.offset) { _, word in
                                Text(word)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.accentColor.opacity(0.1))
                                    .cornerRadius(4)
                            }
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle("词典")
    }
    
    private func playAudio() {
        isPlaying = true
        
        // Youdao audio URL: type=2 for US pronunciation
        let encoded = entry.word.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? entry.word
        let audioURL = "https://dict.youdao.com/dictvoice?audio=\(encoded)&type=1"
        
        Task {
            guard let url = URL(string: audioURL) else {
                isPlaying = false
                return
            }
            
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                
                audioPlayer = try AVAudioPlayer(data: data)
                audioPlayer?.play()
                
                // Reset after playback
                DispatchQueue.main.asyncAfter(deadline: .now() + (audioPlayer?.duration ?? 1.0)) {
                    isPlaying = false
                }
            } catch {
                isPlaying = false
            }
        }
    }
}

// Flow layout for related words
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowLayoutResult(
            in: proposal.replacingUnspecifiedDimensions().width,
            subviews: subviews,
            spacing: spacing
        )
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowLayoutResult(
            in: bounds.width,
            subviews: subviews,
            spacing: spacing
        )
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: result.positions[index].x + bounds.origin.x, y: result.positions[index].y + bounds.origin.y), proposal: .unspecified)
        }
    }
}

struct FlowLayoutResult {
    var size: CGSize = .zero
    var positions: [CGPoint] = []
    
    init(in maxWidth: CGFloat, subviews: LayoutSubviews, spacing: CGFloat) {
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            
            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            
            positions.append(CGPoint(x: currentX, y: currentY))
            
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        
        self.size = CGSize(width: maxWidth, height: currentY + lineHeight)
    }
}
