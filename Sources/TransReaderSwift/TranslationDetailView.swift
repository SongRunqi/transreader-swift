import SwiftUI

// MARK: - Hover Icon Button
private struct HoverIconButton: View {
    let icon: String
    let size: CGFloat
    let color: Color
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size))
                .foregroundStyle(isHovered ? Theme.accent : color)
                .frame(width: size + 10, height: size + 10)
                .background(isHovered ? Theme.accent.opacity(0.1) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
        .focusable(false)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Shared: Analysis Meta Tags (structure + tense pills)
struct AnalysisMetaTags: View {
    let structure: String
    let tense: String

    init(_ analysis: Analysis) {
        self.structure = analysis.structure
        self.tense = analysis.tense
    }

    init(structure: String = "", tense: String = "") {
        self.structure = structure
        self.tense = tense
    }

    var body: some View {
        if !structure.isEmpty || !tense.isEmpty {
            HStack(spacing: 6) {
                if !structure.isEmpty {
                    Text(structure)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 2)
                        .background(Theme.tertiaryBg)
                        .cornerRadius(4)
                }
                if !tense.isEmpty {
                    Text(tense)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.teal)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 2)
                        .background(Theme.tertiaryBg)
                        .cornerRadius(4)
                }
            }
        }
    }
}

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
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Theme.accent)
                            .frame(width: 6, height: 6)
                            .opacity(0.8)
                            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isActive)
                        HoverIconButton(icon: "xmark.circle", size: 10, color: Theme.textSecondary) {
                            onCancel?()
                        }
                        .help("取消翻译")
                    }
                    .fixedSize()
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
                        HoverIconButton(icon: "arrow.clockwise", size: 10, color: Theme.textSecondary.opacity(0.6)) {
                            onRetranslate(result.sourceText)
                        }
                        .help("重新翻译")
                    }

                    // Copy source text
                    HoverIconButton(icon: "doc.on.doc", size: 10, color: Theme.textSecondary.opacity(0.6)) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(result.sourceText, forType: .string)
                    }
                    .help("复制原文")

                    Text(result.source.rawValue)
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.textSecondary.opacity(0.5))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.tertiaryBg)
                        .cornerRadius(3)
                        .fixedSize()
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

    // Resolved analysis — always available (empty when no data yet)
    private var analysis: Analysis {
        sentence.analysis ?? Analysis(structure: "", tense: "", chunks: [], tip: "")
    }

    private var analysisHasContent: Bool {
        let a = analysis
        return !a.structure.isEmpty || !a.tense.isEmpty || !a.chunks.isEmpty || !a.tip.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if displayMode == .read {
                readModeContent
            } else {
                analyzeModeContent
            }

            // Streaming indicator
            if sentence.isPartial {
                ProgressView()
                    .controlSize(.mini)
                    .padding(.top, 2)
            }
        }
        .padding(.vertical, 4)
        .onChange(of: analysisHasContent) { _, hasContent in
            // Auto-expand when analysis content first arrives during streaming
            if hasContent && sentence.isPartial {
                showAnalysis = true
            }
        }
        .onChange(of: sentence.isPartial) { oldValue, newValue in
            // Keep analysis expanded when streaming finishes
            if oldValue == true && newValue == false && analysisHasContent {
                showAnalysis = true
            }
        }
        .onAppear {
            if sentence.isPartial && analysisHasContent {
                showAnalysis = true
            }
        }
    }

    // MARK: - Read Mode: en → zh → [collapsible: meta → tree → tip]
    @ViewBuilder
    private var readModeContent: some View {
        englishText
        chineseText
        metaTags(analysis)
        analysisSection
    }

    @ViewBuilder
    private var analysisSection: some View {
        // Analysis content (may be empty during early streaming)
        let hasContent = !analysis.structure.isEmpty || !analysis.tense.isEmpty
            || !analysis.chunks.isEmpty || !analysis.tip.isEmpty

        if hasContent {
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        showAnalysis.toggle()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: showAnalysis ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                        Text("语法分析")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(Theme.accent)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if showAnalysis {
                    VStack(alignment: .leading, spacing: 10) {
                        chunksTree(analysis)
                        if !analysis.tip.isEmpty { tipBox(analysis.tip) }
                    }
                    .padding(.top, 4)
                }
            }
        }
    }

    // MARK: - Analyze Mode: tree → en → zh → meta → tip
    // All slots always present in VStack; empty data = empty view (no layout jump)
    @ViewBuilder
    private var analyzeModeContent: some View {
        chunksTree(analysis)
        englishText
        chineseText
        metaTags(analysis)
        if !analysis.tip.isEmpty { tipBox(analysis.tip) }
    }

    // MARK: - Shared Components

    private func metaTags(_ analysis: Analysis) -> some View {
        AnalysisMetaTags(analysis)
    }

    @ViewBuilder
    private func chunksTree(_ analysis: Analysis) -> some View {
        if !analysis.chunks.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(analysis.chunks.enumerated()), id: \.offset) { _, chunk in
                    SyntaxTreeNode(chunk: chunk, depth: 0)
                }
            }
        }
    }

    @ViewBuilder
    private var englishText: some View {
        if !sentence.en.isEmpty {
            // Always use ClickableEnglishText — same view identity for streaming and final
            // (avoids layout jump when isPartial changes)
            ClickableEnglishText(text: sentence.en, onWordLookup: sentence.isPartial ? nil : onWordLookup)
                .lineSpacing(6)
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


// MARK: - Clickable English Text (hover highlight + single-click word lookup)
struct ClickableEnglishText: NSViewRepresentable {
    let text: String
    var onWordLookup: ((String) -> Void)?

    func makeNSView(context: Context) -> ClickableEnglishNSView {
        let view = ClickableEnglishNSView()
        view.configure(text: text, font: NSFont(descriptor: Theme.englishNSFont.fontDescriptor, size: Theme.englishNSFont.pointSize)!, textColor: NSColor(Theme.textPrimary), onWordLookup: onWordLookup)
        return view
    }

    func updateNSView(_ nsView: ClickableEnglishNSView, context: Context) {
        nsView.configure(text: text, font: NSFont(descriptor: Theme.englishNSFont.fontDescriptor, size: Theme.englishNSFont.pointSize)!, textColor: NSColor(Theme.textPrimary), onWordLookup: onWordLookup)
    }
}

class ClickableEnglishNSView: NSView {
    private var textStorage = NSTextStorage()
    private var layoutManager = NSLayoutManager()
    private var textContainer = NSTextContainer()
    private var wordRanges: [(NSRange, String)] = []
    private var hoveredWordIndex: Int? = nil
    private var onWordLookup: ((String) -> Void)?
    private var baseFont: NSFont = .systemFont(ofSize: 15)
    private var baseTextColor: NSColor = .labelColor
    private let accentColor = NSColor.systemBlue
    private var trackingArea: NSTrackingArea?

    override init(frame: NSRect) {
        super.init(frame: frame)
        layoutManager.addTextContainer(textContainer)
        textStorage.addLayoutManager(layoutManager)
        textContainer.lineFragmentPadding = 0
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(text: String, font: NSFont, textColor: NSColor, onWordLookup: ((String) -> Void)?) {
        self.baseFont = font
        self.baseTextColor = textColor
        self.onWordLookup = onWordLookup

        // Build attributed string and find word ranges
        let attrStr = NSMutableAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: textColor
        ])

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 4
        attrStr.addAttribute(.paragraphStyle, value: paragraphStyle, range: NSRange(location: 0, length: attrStr.length))

        // Find English word ranges
        wordRanges = []
        let nsText = text as NSString
        let regex = try! NSRegularExpression(pattern: "[a-zA-Z][a-zA-Z'-]*")
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        for match in matches {
            let word = nsText.substring(with: match.range).lowercased().replacingOccurrences(of: "[^a-z'-]", with: "", options: .regularExpression)
            if word.count >= 2 {
                wordRanges.append((match.range, word))
            }
        }

        textStorage.setAttributedString(attrStr)
        hoveredWordIndex = nil
        needsDisplay = true
        invalidateIntrinsicContentSize()
    }

    override var isFlipped: Bool { true }

    override var intrinsicContentSize: NSSize {
        textContainer.size = NSSize(width: bounds.width > 0 ? bounds.width : 300, height: .greatestFiniteMagnitude)
        layoutManager.ensureLayout(for: textContainer)
        let rect = layoutManager.usedRect(for: textContainer)
        return NSSize(width: NSView.noIntrinsicMetric, height: ceil(rect.height))
    }

    override func layout() {
        super.layout()
        textContainer.size = NSSize(width: bounds.width, height: .greatestFiniteMagnitude)
        layoutManager.ensureLayout(for: textContainer)
        invalidateIntrinsicContentSize()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea { removeTrackingArea(existing) }
        trackingArea = NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeInActiveApp], owner: self)
        addTrackingArea(trackingArea!)
    }

    override func draw(_ dirtyRect: NSRect) {
        // Draw hover highlight background
        if let idx = hoveredWordIndex {
            let range = wordRanges[idx].0
            let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            layoutManager.enumerateEnclosingRects(forGlyphRange: glyphRange, withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0), in: textContainer) { rect, _ in
                let bgRect = rect.insetBy(dx: -2, dy: -1)
                self.accentColor.setFill()
                NSBezierPath(roundedRect: bgRect, xRadius: 3, yRadius: 3).fill()
            }
        }

        // Draw text
        let glyphRange = layoutManager.glyphRange(for: textContainer)
        layoutManager.drawGlyphs(forGlyphRange: glyphRange, at: .zero)
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let newIndex = wordIndex(at: point)

        if newIndex != hoveredWordIndex {
            // Reset previous highlight
            if let old = hoveredWordIndex {
                let range = wordRanges[old].0
                textStorage.addAttribute(.foregroundColor, value: baseTextColor, range: range)
            }
            // Set new highlight
            if let new = newIndex {
                let range = wordRanges[new].0
                textStorage.addAttribute(.foregroundColor, value: NSColor.white, range: range)
                NSCursor.pointingHand.set()
            } else {
                NSCursor.arrow.set()
            }
            hoveredWordIndex = newIndex
            needsDisplay = true
        }
    }

    override func mouseExited(with event: NSEvent) {
        if let old = hoveredWordIndex {
            let range = wordRanges[old].0
            textStorage.addAttribute(.foregroundColor, value: baseTextColor, range: range)
            hoveredWordIndex = nil
            needsDisplay = true
            NSCursor.arrow.set()
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let idx = wordIndex(at: point) {
            let word = wordRanges[idx].1
            onWordLookup?(word)
        } else {
            super.mouseDown(with: event)
        }
    }

    private func wordIndex(at point: NSPoint) -> Int? {
        let charIndex = layoutManager.characterIndex(for: point, in: textContainer, fractionOfDistanceBetweenInsertionPoints: nil)
        for (i, (range, _)) in wordRanges.enumerated() {
            if NSLocationInRange(charIndex, range) { return i }
        }
        return nil
    }
}


// MARK: - Syntax Tree Node (Recursive)
// Mirrors the Python version's ga-node (leaf) / ga-branch (has children) design:
// - Branch expanded: [▼ role] → indented children with colored left border
// - Branch collapsed: [▶ role en zh] (summary)
// - Leaf: [role en zh] inline
struct SyntaxTreeNode: View {
    let chunk: Chunk
    let depth: Int
    @State private var expanded = true
    @State private var isHovered = false

    private var hasChildren: Bool {
        chunk.children != nil && !chunk.children!.isEmpty
    }

    private var roleColor: Color { Theme.roleColor(chunk.role) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if hasChildren {
                branchView
            } else {
                leafView
            }
        }
    }

    // MARK: - Leaf node: [role] en zh
    private var leafView: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            // Spacer to align with branch toggle
            Spacer().frame(width: 12)

            roleTag

            textContent
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 2)
        .background(isHovered ? Theme.textSecondary.opacity(0.04) : Color.clear)
        .cornerRadius(3)
        .onHover { isHovered = $0 }
    }

    // MARK: - Branch node: toggle header + indented children
    private var branchView: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row (clickable)
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    expanded.toggle()
                }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    // Toggle indicator
                    Text(expanded ? "▼" : "▶")
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.textSecondary.opacity(0.35))
                        .frame(width: 12, alignment: .center)

                    roleTag

                    // Show en/zh as summary when collapsed
                    if !expanded {
                        textContent
                    }
                }
                .padding(.vertical, 2)
                .padding(.horizontal, 2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .background(isHovered ? Theme.textSecondary.opacity(0.06) : Color.clear)
                .cornerRadius(3)
            }
            .buttonStyle(.plain)
            .onHover { isHovered = $0 }

            // Children with indented left border
            if expanded {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(chunk.children!.enumerated()), id: \.offset) { _, child in
                        SyntaxTreeNode(chunk: child, depth: depth + 1)
                    }
                }
                .padding(.leading, 18)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(depth == 0 ? roleColor.opacity(0.4) : Theme.textSecondary.opacity(0.1))
                        .frame(width: 1.5)
                        .padding(.leading, 5) // align with child toggle center
                }
            }
        }
    }

    // MARK: - Shared components

    private var roleTag: some View {
        Group {
            if depth == 0 {
                Text(chunk.role)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(roleColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(roleColor.opacity(0.15))
                    .cornerRadius(3)
            } else {
                Text(chunk.role)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .fixedSize()
    }

    /// Recursively collect all leaf `en` text from a chunk tree
    private static func collectEn(_ chunk: Chunk) -> String {
        if let children = chunk.children, !children.isEmpty {
            return children.map { collectEn($0) }.joined(separator: " ")
        }
        return chunk.en
    }

    /// Recursively collect all leaf `zh` text from a chunk tree
    private static func collectZh(_ chunk: Chunk) -> String {
        if let children = chunk.children, !children.isEmpty {
            return children.map { collectZh($0) }.joined()
        }
        return chunk.zh
    }

    private var displayEn: String {
        chunk.en.isEmpty && hasChildren ? Self.collectEn(chunk) : chunk.en
    }

    private var displayZh: String {
        chunk.zh.isEmpty && hasChildren ? Self.collectZh(chunk) : chunk.zh
    }

    private var textContent: some View {
        // en and zh inline on the same line, wrapping naturally
        let enText = !displayEn.isEmpty
            ? Text(displayEn)
                .font(.system(size: 12))
                .foregroundColor(Theme.textPrimary)
            : Text("")
        let zhText = !displayZh.isEmpty
            ? Text("  " + displayZh)
                .font(.system(size: 12))
                .foregroundColor(Theme.textSecondary)
            : Text("")

        return (enText + zhText)
            .lineSpacing(4)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .layoutPriority(1)
    }
}
