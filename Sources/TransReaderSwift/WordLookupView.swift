import SwiftUI
import AVFoundation

// MARK: - Audio Playback State Machine

enum AudioPlaybackState: Equatable {
    case idle
    case loading
    case playing
    case error(String)
    case retrying(Int)
}

// Bridge NSObject delegate for AVAudioPlayer (SwiftUI structs can't be delegates)
class AudioDelegate: NSObject, AVAudioPlayerDelegate {
    var onFinish: () -> Void = {}
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully: Bool) { onFinish() }
    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) { onFinish() }
}

struct WordLookupView: View {
    let entry: DictionaryEntry
    let dictionaryService: DictionaryService
    let onAddToVocab: () -> Void

    @State private var audioPlayer: AVAudioPlayer?
    @State private var audioDelegate = AudioDelegate()
    @State private var playbackState: AudioPlaybackState = .idle

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // Word + Phonetic + Actions
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.word)
                            .font(.system(size: 22, weight: .bold, design: .serif))
                            .foregroundStyle(Theme.textPrimary)

                        if let phonetic = entry.phonetic {
                            Text("/\(phonetic)/")
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }

                    Spacer()

                    HStack(spacing: 10) {
                        // Pronunciation button with state-driven UI
                        Button(action: playAudio) {
                            audioButtonContent
                        }
                        .buttonStyle(.plain)
                        .disabled(playbackState == .loading || playbackState == .playing || playbackState == .retrying(1))

                        // Error text (shown briefly next to button)
                        if case .error(let msg) = playbackState {
                            Text(msg)
                                .font(.system(size: 10))
                                .foregroundStyle(.orange)
                                .lineLimit(1)
                                .transition(.opacity)
                        }

                        Button(action: onAddToVocab) {
                            Image(systemName: "plus.circle")
                                .font(.system(size: 15))
                                .foregroundStyle(Theme.accent)
                        }
                        .buttonStyle(.plain)
                        .help("添加到生词本")
                    }
                }

                Divider()
                    .foregroundColor(Theme.border)

                // Meanings
                if !entry.meanings.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(entry.meanings.enumerated()), id: \.offset) { _, meaning in
                            HStack(alignment: .top, spacing: 6) {
                                Text("·")
                                    .foregroundStyle(Theme.textSecondary)
                                Text(meaning)
                                    .font(.system(size: 13))
                                    .foregroundStyle(Theme.textPrimary)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }

                // Examples
                if !entry.examples.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("例句")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.textSecondary)

                        ForEach(Array(entry.examples.enumerated()), id: \.offset) { _, example in
                            Text(example)
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.textSecondary)
                                .textSelection(.enabled)
                        }
                    }
                }

                // Synonyms
                if !entry.synonyms.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("近义词")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.textSecondary)

                        FlowLayout(spacing: 6) {
                            ForEach(Array(entry.synonyms.enumerated()), id: \.offset) { _, synonym in
                                Text(synonym)
                                    .font(.system(size: 12))
                                    .foregroundStyle(Theme.accent)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Theme.accent.opacity(0.08))
                                    .cornerRadius(4)
                            }
                        }
                    }
                }

                // Related words
                if !entry.relatedWords.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("相关词")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.textSecondary)

                        FlowLayout(spacing: 6) {
                            ForEach(Array(entry.relatedWords.enumerated()), id: \.offset) { _, word in
                                Text(word)
                                    .font(.system(size: 12))
                                    .foregroundStyle(Theme.textPrimary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Theme.tertiaryBg)
                                    .cornerRadius(4)
                            }
                        }
                    }
                }
            }
            .padding(16)
        }
        .background(Theme.bg)
    }

    // MARK: - Audio Button Content

    @ViewBuilder
    private var audioButtonContent: some View {
        switch playbackState {
        case .idle:
            Image(systemName: "speaker.wave.2")
                .font(.system(size: 15))
                .foregroundStyle(Theme.accent)
        case .loading, .retrying:
            ProgressView()
                .controlSize(.mini)
        case .playing:
            Image(systemName: "speaker.wave.3.fill")
                .font(.system(size: 15))
                .foregroundStyle(Theme.accent)
                .symbolEffect(.variableColor.iterative)
        case .error:
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 14))
                .foregroundStyle(.orange)
        }
    }

    // MARK: - Audio Playback

    private func playAudio() {
        playbackState = .loading

        Task {
            do {
                let data = try await fetchAudioWithRetry()
                let player = try AVAudioPlayer(data: data)

                audioDelegate.onFinish = {
                    playbackState = .idle
                }
                player.delegate = audioDelegate
                audioPlayer = player
                player.play()
                playbackState = .playing

            } catch {
                let msg: String
                if error is CancellationError {
                    msg = "已取消"
                } else {
                    msg = error.localizedDescription
                }
                playbackState = .error(msg)
                // Auto-clear error after 3 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    if case .error = playbackState {
                        playbackState = .idle
                    }
                }
            }
        }
    }

    private func fetchAudioWithRetry() async throws -> Data {
        do {
            return try await dictionaryService.fetchAudio(for: entry.word, type: 1)
        } catch {
            // Auto-retry once
            await MainActor.run { playbackState = .retrying(1) }
            try? await Task.sleep(nanoseconds: 500_000_000) // 500ms before retry
            return try await dictionaryService.fetchAudio(for: entry.word, type: 1)
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
            subview.place(
                at: CGPoint(
                    x: result.positions[index].x + bounds.origin.x,
                    y: result.positions[index].y + bounds.origin.y
                ),
                proposal: .unspecified
            )
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
