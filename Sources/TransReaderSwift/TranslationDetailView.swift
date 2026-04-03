import SwiftUI

// MARK: - Translation Block (one per translation request)
struct TranslationBlockView: View {
    let result: TranslationResult
    var isActive: Bool = false
    var displayMode: DisplayMode = .analyze
    var onRetranslate: ((String) -> Void)?
    var onWordLookup: ((String) -> Void)?
    var onCancel: (() -> Void)?

    private var timeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: result.timestamp)
    }

    private var elapsedString: String {
        let secs = Double(result.elapsedMs) / 1000.0
        return String(format: "%.1fs", secs)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Block header: timestamp + elapsed + actions
            HStack {
                HStack(spacing: 8) {
                    Text(timeString)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(Theme.textSecondary)

                    if result.elapsedMs > 0 {
                        Text("(\(elapsedString))")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textSecondary.opacity(0.7))
                    }
                }

                // In-progress indicator + cancel
                if isActive && onCancel != nil && !result.wasCancelled {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Theme.accent)
                            .frame(width: 6, height: 6)
                            .opacity(0.8)
                            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isActive)
                        Text("翻译中...")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textSecondary)
                        Button {
                            onCancel?()
                        } label: {
                            Image(systemName: "xmark.circle")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.textSecondary)
                        }
                        .buttonStyle(.plain)
                        .focusable(false)
                        .help("取消翻译")
                    }
                }

                // Cancelled label
                if result.wasCancelled {
                    Text("已取消")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.orange)
                }

                Spacer()

                HStack(spacing: 8) {
                    // Retranslate button
                    if let onRetranslate = onRetranslate {
                        Button {
                            onRetranslate(result.sourceText)
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 10))
                                .foregroundStyle(Theme.textSecondary.opacity(0.6))
                        }
                        .buttonStyle(.plain)
                        .help("重新翻译")
                    }

                    // Copy source text
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(result.sourceText, forType: .string)
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.textSecondary.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                    .help("复制原文")

                    Text(result.source.rawValue)
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.textSecondary.opacity(0.5))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.tertiaryBg)
                        .cornerRadius(3)
                }
            }
            .padding(.bottom, 12)

            // Sentences
            VStack(alignment: .leading, spacing: 16) {
                ForEach(Array(result.sentences.enumerated()), id: \.offset) { _, sentence in
                    SentenceBlockView(sentence: sentence, displayMode: displayMode, onWordLookup: onWordLookup)
                }
            }
        }
        .padding(20)
        .background(Theme.cardBg)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isActive ? Theme.accent.opacity(0.3) : Theme.border.opacity(0.5), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 2)
        .padding(.bottom, 16)
    }
}

// MARK: - Sentence Pair (en + zh + optional analysis)
struct SentenceBlockView: View {
    let sentence: Sentence
    var displayMode: DisplayMode = .analyze
    var onWordLookup: ((String) -> Void)?
    @State private var showAnalysis = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if displayMode == .read {
                readModeContent
            } else {
                analyzeModeContent
            }

            // Streaming indicator (same for both modes)
            if sentence.isPartial {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.mini)
                    if sentence.en.isEmpty {
                        Text("翻译中...")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .padding(.top, sentence.en.isEmpty ? 0 : 2)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Read Mode: en/zh first, analysis collapsed
    @ViewBuilder
    private var readModeContent: some View {
        // 1. English text (large)
        englishText

        // 2. Chinese translation (right after)
        chineseText

        // 3. Analysis in collapsible DisclosureGroup (default collapsed)
        if let analysis = sentence.analysis {
            if sentence.isPartial {
                StreamingAnalysisView(analysis: analysis, sentence: sentence)
            } else {
                DisclosureGroup(isExpanded: $showAnalysis) {
                    GrammarAnalysisCard(analysis: analysis, sentence: sentence)
                } label: {
                    HStack(spacing: 4) {
                        Text("语法分析")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(Theme.accent)
                }
            }
        }
    }

    // MARK: - Analyze Mode: structure first, zh after chunks
    @ViewBuilder
    private var analyzeModeContent: some View {
        // 1. English text
        englishText

        // 2. Analysis section (expanded by default)
        if let analysis = sentence.analysis {
            if sentence.isPartial {
                StreamingAnalysisView(analysis: analysis, sentence: sentence)
            } else {
                // Structure + tense summary
                if !analysis.structure.isEmpty || !analysis.tense.isEmpty {
                    HStack(spacing: 6) {
                        if !analysis.structure.isEmpty {
                            analysisMeta(label: "结构", value: analysis.structure)
                        }
                        if !analysis.tense.isEmpty {
                            analysisMeta(label: "时态", value: analysis.tense)
                        }
                    }
                }

                // Chunks tree (always visible in analyze mode)
                if !analysis.chunks.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(analysis.chunks.enumerated()), id: \.offset) { _, chunk in
                            SyntaxTreeNode(chunk: chunk, depth: 0)
                        }
                    }
                }
            }
        }

        // 3. Chinese translation (after analysis)
        chineseText

        // 4. Tip (at the end)
        if let analysis = sentence.analysis, !sentence.isPartial, !analysis.tip.isEmpty {
            tipBox(analysis.tip)
        }
    }

    // MARK: - Shared Components

    @ViewBuilder
    private var englishText: some View {
        if !sentence.en.isEmpty {
            if sentence.isPartial {
                Text(sentence.en)
                    .font(Theme.englishFont)
                    .foregroundStyle(Theme.textPrimary)
                    .lineSpacing(6)
                    .textSelection(.enabled)
            } else {
                ClickableEnglishText(text: sentence.en, onWordLookup: onWordLookup)
                    .lineSpacing(6)
            }
        }
    }

    @ViewBuilder
    private var chineseText: some View {
        if !sentence.zh.isEmpty {
            Text(sentence.zh)
                .font(Theme.chineseFont)
                .foregroundStyle(Theme.textSecondary)
                .lineSpacing(4)
                .textSelection(.enabled)
        }
    }

    private func analysisMeta(label: String, value: String) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.textSecondary.opacity(0.7))
            Text(value)
                .font(.system(size: 10))
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Theme.bg)
        .cornerRadius(4)
    }

    private func tipBox(_ tip: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "lightbulb.fill")
                .font(.system(size: 11))
                .foregroundStyle(Theme.tipBorder.opacity(0.7))
            Text(tip)
                .font(.system(size: 11))
                .foregroundStyle(Theme.textPrimary.opacity(0.9))
                .lineSpacing(3)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.tipBg.opacity(0.6))
        .cornerRadius(6)
    }
}

// MARK: - Streaming Analysis (renders partial analysis fields as they arrive)
struct StreamingAnalysisView: View {
    let analysis: Analysis
    let sentence: Sentence

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Meta tags (structure + tense) — show as soon as available
            if !analysis.structure.isEmpty || !analysis.tense.isEmpty {
                HStack(spacing: 6) {
                    if !analysis.structure.isEmpty {
                        streamingMetaTag(label: "结构", value: analysis.structure)
                    }
                    if !analysis.tense.isEmpty {
                        streamingMetaTag(label: "时态", value: analysis.tense)
                    }
                }
            }

            // Chunks — render incrementally as they arrive
            if !analysis.chunks.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(analysis.chunks.enumerated()), id: \.offset) { _, chunk in
                        SyntaxTreeNode(chunk: chunk, depth: 0)
                    }
                }
            }

            // Tip — show as it streams in
            if !analysis.tip.isEmpty {
                streamingTipBox(analysis.tip)
            }
        }
        .padding(12)
        .background(Theme.tertiaryBg.opacity(0.6))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Theme.border.opacity(0.3), lineWidth: 1)
        )
    }

    private func streamingMetaTag(label: String, value: String) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.textSecondary.opacity(0.7))
            Text(value)
                .font(.system(size: 10))
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Theme.bg)
        .cornerRadius(4)
    }

    private func streamingTipBox(_ tip: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "lightbulb.fill")
                .font(.system(size: 11))
                .foregroundStyle(Theme.tipBorder.opacity(0.7))
            Text(tip)
                .font(.system(size: 11))
                .foregroundStyle(Theme.textPrimary.opacity(0.9))
                .lineSpacing(3)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.tipBg.opacity(0.6))
        .cornerRadius(6)
    }
}

// MARK: - Clickable English Text (double-click word for lookup)
struct ClickableEnglishText: View {
    let text: String
    var onWordLookup: ((String) -> Void)?

    // Split text into tokens: words and separators
    private var tokens: [(String, Bool)] {
        // Bool = isWord
        var result: [(String, Bool)] = []
        var current = ""
        var inWord = false

        for ch in text {
            let isWordChar = ch.isLetter || ch == "-" || ch == "'"
            if isWordChar {
                if !inWord && !current.isEmpty {
                    result.append((current, false))
                    current = ""
                }
                inWord = true
                current.append(ch)
            } else {
                if inWord && !current.isEmpty {
                    result.append((current, true))
                    current = ""
                }
                inWord = false
                current.append(ch)
            }
        }
        if !current.isEmpty {
            result.append((current, inWord))
        }
        return result
    }

    var body: some View {
        // Build attributed text with individual word tap targets
        let wordTokens = tokens
        HStack(spacing: 0) {
            // Use Text concatenation for proper line wrapping
            wordTokens.reduce(Text("")) { result, token in
                let (str, isWord) = token
                if isWord {
                    return result + Text(str)
                        .font(Theme.englishFont)
                        .foregroundColor(Theme.textPrimary)
                } else {
                    return result + Text(str)
                        .font(Theme.englishFont)
                        .foregroundColor(Theme.textPrimary)
                }
            }
            .lineSpacing(6)
        }
        .overlay(
            // Invisible overlay with word-level tap targets using a custom layout
            WordTapOverlay(text: text, onWordLookup: onWordLookup)
                .allowsHitTesting(true)
        )
    }
}

// Invisible overlay that provides word-level double-tap targets
struct WordTapOverlay: NSViewRepresentable {
    let text: String
    var onWordLookup: ((String) -> Void)?

    func makeNSView(context: Context) -> WordTapNSView {
        let view = WordTapNSView()
        view.text = text
        view.onWordLookup = onWordLookup
        return view
    }

    func updateNSView(_ nsView: WordTapNSView, context: Context) {
        nsView.text = text
        nsView.onWordLookup = onWordLookup
    }
}

class WordTapNSView: NSView {
    var text: String = ""
    var onWordLookup: ((String) -> Void)?

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            // Extract word at click position
            let word = wordAtPoint(event.locationInWindow)
            if let word = word, !word.isEmpty {
                onWordLookup?(word)
                return
            }
        }
        super.mouseDown(with: event)
    }

    private func wordAtPoint(_ windowPoint: NSPoint) -> String? {
        // Use NSString word-at-index to find the word under cursor
        let nsText = text as NSString
        let localPoint = convert(windowPoint, from: nil)

        // Estimate character position based on view width and text length
        let fraction = max(0, min(1, localPoint.x / max(bounds.width, 1)))
        let charIndex = Int(fraction * CGFloat(nsText.length))
        let safeIndex = max(0, min(charIndex, nsText.length - 1))

        guard nsText.length > 0 else { return nil }

        // Find word boundaries around the estimated character position
        let range = nsText.range(of: "[a-zA-Z][a-zA-Z'-]*",
                                  options: .regularExpression,
                                  range: NSRange(location: 0, length: nsText.length))
        guard range.location != NSNotFound else { return nil }

        // Find all word ranges and pick the one closest to our estimated position
        var bestWord: String?
        var bestDistance = Int.max

        var searchStart = 0
        while searchStart < nsText.length {
            let searchRange = NSRange(location: searchStart, length: nsText.length - searchStart)
            let wordRange = nsText.range(of: "[a-zA-Z][a-zA-Z'-]*",
                                          options: .regularExpression,
                                          range: searchRange)
            guard wordRange.location != NSNotFound else { break }

            let wordMid = wordRange.location + wordRange.length / 2
            let dist = abs(wordMid - safeIndex)
            if dist < bestDistance {
                bestDistance = dist
                bestWord = nsText.substring(with: wordRange)
            }

            searchStart = wordRange.location + wordRange.length
        }

        // Only return if the click was reasonably close to the word
        if bestDistance <= 5, let word = bestWord, word.count >= 2 {
            return word
        }
        return nil
    }

    override var isFlipped: Bool { true }
}

// MARK: - Grammar Analysis Card
struct GrammarAnalysisCard: View {
    let analysis: Analysis
    let sentence: Sentence

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Meta tags (structure + tense)
            HStack(spacing: 6) {
                metaTag(label: "结构", value: analysis.structure)
                metaTag(label: "时态", value: analysis.tense)
            }

            // Sentence display in card
            VStack(alignment: .leading, spacing: 4) {
                Text(sentence.en)
                    .font(Theme.serifFont(14))
                    .foregroundStyle(Theme.textPrimary)
                    .textSelection(.enabled)

                Text(sentence.zh)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                    .textSelection(.enabled)
            }

            // Syntax tree
            if !analysis.chunks.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("句法结构")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.bottom, 4)

                    ForEach(Array(analysis.chunks.enumerated()), id: \.offset) { _, chunk in
                        SyntaxTreeNode(chunk: chunk, depth: 0)
                    }
                }
            }

            // Tip box
            if !analysis.tip.isEmpty {
                tipBox(analysis.tip)
            }
        }
        .padding(14)
        .background(Theme.tertiaryBg)
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Theme.border.opacity(0.5), lineWidth: 1)
        )
    }

    private func metaTag(label: String, value: String) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.textSecondary.opacity(0.7))
            Text(value)
                .font(.system(size: 10))
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Theme.bg)
        .cornerRadius(4)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(Theme.border.opacity(0.3), lineWidth: 0.5)
        )
    }

    private func tipBox(_ tip: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "lightbulb.fill")
                .font(.system(size: 12))
                .foregroundStyle(Theme.tipBorder)

            Text(tip)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textPrimary)
                .lineSpacing(3)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.tipBg)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Theme.tipBorder.opacity(0.4), lineWidth: 1)
        )
    }
}

// MARK: - Syntax Tree Node (Recursive)
struct SyntaxTreeNode: View {
    let chunk: Chunk
    let depth: Int
    @State private var expanded = true

    private var hasChildren: Bool {
        if let children = chunk.children, !children.isEmpty {
            return true
        }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // This node
            HStack(alignment: .top, spacing: 0) {
                // Left colored border
                if depth > 0 {
                    Rectangle()
                        .fill(Theme.roleColor(chunk.role))
                        .frame(width: 2)
                        .padding(.leading, CGFloat(depth - 1) * 16)
                }

                // Node content
                HStack(alignment: .top, spacing: 6) {
                    // Expand/collapse toggle
                    if hasChildren {
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                expanded.toggle()
                            }
                        } label: {
                            Image(systemName: expanded ? "chevron.down" : "chevron.right")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(Theme.textSecondary)
                                .frame(width: 12, height: 12)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Spacer()
                            .frame(width: 12)
                    }

                    // Role tag
                    Text(chunk.role)
                        .font(.system(size: depth == 0 ? 11 : 10, weight: depth == 0 ? .semibold : .medium))
                        .foregroundStyle(Theme.roleColor(chunk.role))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Theme.roleColorBg(chunk.role))
                        .cornerRadius(3)

                    // Text content
                    VStack(alignment: .leading, spacing: 1) {
                        Text(chunk.en)
                            .font(.system(size: depth == 0 ? 13 : 12))
                            .foregroundStyle(Theme.textPrimary)
                            .textSelection(.enabled)

                        Text(chunk.zh)
                            .font(.system(size: depth == 0 ? 12 : 11))
                            .foregroundStyle(Theme.textSecondary)
                            .textSelection(.enabled)
                    }
                }
                .padding(.leading, depth > 0 ? 8 : 0)
                .padding(.vertical, depth == 0 ? 6 : 4)
            }

            // Children (if expanded)
            if hasChildren && expanded {
                ForEach(Array(chunk.children!.enumerated()), id: \.offset) { _, child in
                    SyntaxTreeNode(chunk: child, depth: depth + 1)
                }
            }
        }
    }
}
