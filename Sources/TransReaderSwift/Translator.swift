import Foundation

enum TranslatorError: Error, LocalizedError {
    case noAPIKey
    case networkError(Error)
    case invalidResponse
    case cancelled
    case timeout

    var errorDescription: String? {
        switch self {
        case .noAPIKey: return "未配置 API Key"
        case .networkError(let error): return "网络错误: \(error.localizedDescription)"
        case .invalidResponse: return "无效的响应格式"
        case .cancelled: return "翻译已取消"
        case .timeout: return "请求超时"
        }
    }
}

actor Translator {
    private let configStore: ConfigStore

    init(configStore: ConfigStore) {
        self.configStore = configStore
    }

    /// Stateless streaming translation. Cancellation is managed by the caller via
    /// Swift structured concurrency (cancelling the parent Task).
    func translateStream(
        text: String,
        onSentence: @Sendable @escaping (Sentence) async -> Void
    ) async throws -> [Sentence] {
        guard let apiKey = configStore.apiKey else {
            throw TranslatorError.noAPIKey
        }

        let provider = Providers.all[configStore.provider]!
        let url = URL(string: "\(provider.baseURL)/chat/completions")!

        var request = URLRequest(url: url, timeoutInterval: configStore.requestTimeout)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let model = configStore.modelForProvider(configStore.provider)
        let payload: [String: Any] = [
            "model": model,
            "temperature": 0.3,
            "stream": true,
            "messages": [
                ["role": "system", "content": configStore.systemPrompt],
                ["role": "user", "content": text]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (asyncBytes, response) = try await URLSession.shared.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw TranslatorError.invalidResponse
        }

        var accumulated = ""
        let maxBufferSize = 512 * 1024  // 512KB safety cap
        var completeSentences: [Sentence] = []
        var completeIndex = 0

        // Streaming state for the current incomplete sentence
        var enStreamed = ""
        var zhStreamed = ""
        var structureStreamed = ""
        var tenseStreamed = ""
        var tipStreamed = ""
        var allStreamedChunks: [Chunk] = []
        var chunksEmitted = 0

        // Inline streaming loop — cancellation propagates via Task.checkCancellation()
        do {
            for try await line in asyncBytes.lines {
                try Task.checkCancellation()

                guard line.hasPrefix("data: ") else { continue }
                let dataStr = line.dropFirst(6).trimmingCharacters(in: .whitespaces)

                if dataStr == "[DONE]" { break }

                guard let data = dataStr.data(using: .utf8),
                      let chunk = try? JSONDecoder().decode(StreamChunk.self, from: data),
                      let content = chunk.choices.first?.delta.content else {
                    continue
                }

                accumulated += content

                // Safety: if buffer grows beyond limit, the response is likely malformed
                if accumulated.utf8.count > maxBufferSize {
                    appLog("[Translate] Buffer exceeded \(maxBufferSize) bytes, truncating to prevent memory leak")
                    accumulated = String(accumulated.suffix(maxBufferSize / 2))
                }

                // Phase 2: Extract complete JSON objects
                let (objects, remaining) = extractJSONObjects(from: accumulated)
                accumulated = remaining

                for obj in objects {
                    var sentence = obj
                    sentence.index = completeIndex
                    sentence.isPartial = false
                    completeSentences.append(sentence)
                    await onSentence(sentence)
                    completeIndex += 1
                    // Reset streaming state for next sentence
                    enStreamed = ""
                    zhStreamed = ""
                    structureStreamed = ""
                    tenseStreamed = ""
                    tipStreamed = ""
                    allStreamedChunks = []
                    chunksEmitted = 0
                }

                // Phase 1: Progressive streaming of partial content
                guard !accumulated.isEmpty else { continue }

                var hasUpdate = false

                // Extract analysis chunks incrementally (complete + partial branch)
                let (newChunks, partialBranch) = extractAnalysisChunksWithPartial(from: accumulated, after: chunksEmitted)
                if !newChunks.isEmpty {
                    allStreamedChunks.append(contentsOf: newChunks)
                    chunksEmitted += newChunks.count
                    hasUpdate = true
                }
                // Track partial branch separately (don't add to chunksEmitted)
                let currentPartialBranch = partialBranch

                // Extract sentence-level fields ONLY from text after the analysis block closes.
                // This prevents matching chunk-level "en"/"zh" during analysis streaming.
                let afterAnalysis = textAfterAnalysisBlock(accumulated)

                if let text = afterAnalysis {
                    let (enText, _) = extractPartialString(from: text, field: "en")
                    if let e = enText, e != enStreamed {
                        enStreamed = e
                        hasUpdate = true
                    }

                    let (zhText, _) = extractPartialString(from: text, field: "zh")
                    if let z = zhText, z != zhStreamed {
                        zhStreamed = z
                        hasUpdate = true
                    }

                    let (sText, _) = extractPartialString(from: text, field: "structure")
                    if let s = sText, s != structureStreamed {
                        structureStreamed = s
                        hasUpdate = true
                    }

                    let (tText, _) = extractPartialString(from: text, field: "tense")
                    if let t = tText, t != tenseStreamed {
                        tenseStreamed = t
                        hasUpdate = true
                    }

                    let (tipText, _) = extractPartialString(from: text, field: "tip")
                    if let t = tipText, t != tipStreamed {
                        tipStreamed = t
                        hasUpdate = true
                    }
                }

                // Also treat partial branch changes as updates
                if currentPartialBranch != nil { hasUpdate = true }

                // Emit progressive update if anything changed
                if hasUpdate {
                    // Combine complete chunks + partial branch for display
                    var displayChunks = allStreamedChunks
                    if let partial = currentPartialBranch {
                        displayChunks.append(partial)
                    }

                    let hasAnalysis = !structureStreamed.isEmpty || !tenseStreamed.isEmpty
                        || !displayChunks.isEmpty || !tipStreamed.isEmpty

                    let sentence = Sentence(
                        en: enStreamed,
                        zh: zhStreamed,
                        analysis: hasAnalysis ? Analysis(
                            structure: structureStreamed,
                            tense: tenseStreamed,
                            chunks: displayChunks,
                            tip: tipStreamed
                        ) : nil,
                        isPartial: true,
                        index: completeIndex
                    )
                    await onSentence(sentence)
                }
            }

            // Flush remaining
            if !accumulated.isEmpty {
                let cleaned = accumulated
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "`[],"))

                if !cleaned.isEmpty,
                   let data = "[\(cleaned)]".data(using: .utf8),
                   let objects = try? JSONDecoder().decode([Sentence].self, from: data) {
                    for var obj in objects {
                        obj.index = completeIndex
                        obj.isPartial = false
                        completeSentences.append(obj)
                        await onSentence(obj)
                        completeIndex += 1
                    }
                }
                accumulated = ""
            }
        } catch is CancellationError {
            throw TranslatorError.cancelled
        }

        return completeSentences
    }

    // MARK: - JSON Object Extraction

    private func extractJSONObjects(from text: String) -> ([Sentence], String) {
        var objects: [Sentence] = []
        var remaining = text

        // Skip markdown fence
        if remaining.hasPrefix("```") {
            if let newlineIndex = remaining.firstIndex(of: "\n") {
                remaining = String(remaining[newlineIndex...].dropFirst())
            } else {
                return ([], text)
            }
        }

        // Extract complete objects
        while true {
            // Skip whitespace and array punctuation
            let trimmed = remaining.drop(while: { " \t\n\r[,]".contains($0) })
            remaining = String(trimmed)

            guard remaining.first == "{" else { break }

            guard let endIndex = findMatchingBrace(in: remaining) else { break }

            let jsonStr = String(remaining[..<endIndex])
            if let data = jsonStr.data(using: .utf8) {
                do {
                    let compactJson = jsonStr.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "  ", with: "")
                    appLog("[Translate] Raw JSON: \(compactJson)")
                    let obj = try JSONDecoder().decode(Sentence.self, from: data)
                    appLog("[Translate] Decoded sentence: en=\(obj.en.prefix(80)), zh=\(obj.zh.prefix(80)), chunks=\(obj.analysis?.chunks.count ?? 0)")
                    if let chunks = obj.analysis?.chunks {
                        func logChunks(_ chunks: [Chunk], indent: String = "  ") {
                            for (i, c) in chunks.enumerated() {
                                appLog("[Translate] \(indent)chunk[\(i)] role=\(c.role) en=\"\(c.en.prefix(60))\" zh=\"\(c.zh.prefix(60))\" children=\(c.children?.count ?? 0)")
                                if let kids = c.children { logChunks(kids, indent: indent + "  ") }
                            }
                        }
                        logChunks(chunks)
                    }
                    objects.append(obj)
                } catch {
                    appLog("[Translate] JSON decode error: \(error.localizedDescription)")
                    appLog("[Translate] JSON fragment: \(jsonStr.prefix(200))")
                }
            }

            remaining = String(remaining[endIndex...])
        }

        return (objects, remaining)
    }

    // MARK: - Streaming Field Extraction

    /// Extract a JSON string field value from a partial buffer.
    /// Returns `(value, isComplete)` — value is nil if the field hasn't started yet,
    /// isComplete is true if the closing quote was found.
    /// When `lastMatch` is true, finds the last occurrence of the field (for sentence-level
    /// en/zh which appear after chunk-level en/zh in analyze mode).
    private func extractPartialString(from text: String, field: String, lastMatch: Bool = false) -> (String?, Bool) {
        // Find "field" : "
        let key = "\"\(field)\""
        let keyRange: Range<String.Index>?
        if lastMatch {
            keyRange = text.range(of: key, options: .backwards)
        } else {
            keyRange = text.range(of: key)
        }
        guard let keyRange else { return (nil, false) }

        // Advance past the key to find : "
        var idx = keyRange.upperBound
        while idx < text.endIndex {
            let c = text[idx]
            if c == ":" || c == " " || c == "\t" || c == "\n" || c == "\r" {
                idx = text.index(after: idx)
                continue
            }
            if c == "\"" {
                idx = text.index(after: idx) // skip opening quote
                break
            }
            return (nil, false) // unexpected character (e.g. nested object)
        }

        guard idx < text.endIndex || idx == text.endIndex else { return (nil, false) }

        let startIdx = idx
        var i = startIdx
        while i < text.endIndex {
            let c = text[i]
            if c == "\\" {
                // Skip escape pair
                i = text.index(after: i)
                if i < text.endIndex {
                    i = text.index(after: i)
                }
            } else if c == "\"" {
                // Complete string found
                let raw = String(text[startIdx..<i])
                return (unescapeJSON(raw), true)
            } else {
                i = text.index(after: i)
            }
        }

        // Incomplete — return what we have so far
        var raw = String(text[startIdx...])
        if raw.hasSuffix("\\") {
            raw = String(raw.dropLast()) // strip trailing incomplete escape
        }
        return (unescapeJSON(raw), false)
    }

    /// Extract Chunk objects from the "chunks" array in a partial buffer.
    /// Returns (completeChunks, partialBranch):
    /// - completeChunks: fully parsed chunks after skipCount
    /// - partialBranch: an incomplete branch chunk being streamed (role + available children)
    private func extractAnalysisChunksWithPartial(from text: String, after skipCount: Int) -> ([Chunk], Chunk?) {
        // Find "chunks" : [
        let pattern = "\"chunks\"\\s*:\\s*\\["
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let matchRange = Range(match.range, in: text) else {
            return ([], nil)
        }

        let arrayStart = matchRange.upperBound
        var remaining = String(text[arrayStart...])
        var chunks: [Chunk] = []
        var skipped = 0

        while true {
            let trimmed = remaining.drop(while: { " \t\n\r,".contains($0) })
            remaining = String(trimmed)

            if remaining.first == "]" { break }
            guard remaining.first == "{" else { break }

            // Try to find matching closing brace
            if let endIdx = findMatchingBrace(in: remaining) {
                let jsonStr = String(remaining[..<endIdx])
                remaining = String(remaining[endIdx...])

                if skipped < skipCount {
                    skipped += 1
                    continue
                }

                if let data = jsonStr.data(using: .utf8),
                   let chunk = try? JSONDecoder().decode(Chunk.self, from: data) {
                    chunks.append(chunk)
                }
            } else {
                // Incomplete object — try to extract as partial branch
                if skipped < skipCount {
                    break // still within already-emitted range, skip
                }
                let partial = extractPartialBranch(from: remaining)
                return (chunks, partial)
            }
        }

        return (chunks, nil)
    }

    /// Extract a partial branch chunk from an incomplete JSON object.
    /// Parses `role` and any complete children from `{"role":"...","children":[{...},{...}`
    private func extractPartialBranch(from text: String) -> Chunk? {
        // Extract role
        let (role, _) = extractPartialString(from: text, field: "role")
        guard let role, !role.isEmpty else { return nil }

        // Check for children array
        let childPattern = "\"children\"\\s*:\\s*\\["
        guard let childRegex = try? NSRegularExpression(pattern: childPattern),
              let childMatch = childRegex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let childRange = Range(childMatch.range, in: text) else {
            // Leaf chunk still incomplete — extract en/zh if available
            let (en, _) = extractPartialString(from: text, field: "en")
            let (zh, _) = extractPartialString(from: text, field: "zh")
            if en != nil || zh != nil {
                return Chunk(en: en ?? "", zh: zh ?? "", role: role, children: nil)
            }
            return Chunk(en: "", zh: "", role: role, children: [])
        }

        // Extract complete children from the children array
        var childRemaining = String(text[childRange.upperBound...])
        var children: [Chunk] = []

        while true {
            let trimmed = childRemaining.drop(while: { " \t\n\r,".contains($0) })
            childRemaining = String(trimmed)

            if childRemaining.first == "]" { break }
            guard childRemaining.first == "{" else { break }

            if let endIdx = findMatchingBrace(in: childRemaining) {
                let jsonStr = String(childRemaining[..<endIdx])
                childRemaining = String(childRemaining[endIdx...])

                if let data = jsonStr.data(using: .utf8),
                   let chunk = try? JSONDecoder().decode(Chunk.self, from: data) {
                    children.append(chunk)
                }
            } else {
                // Recurse: incomplete child might also be a branch
                if let partialChild = extractPartialBranch(from: childRemaining) {
                    children.append(partialChild)
                }
                break
            }
        }

        return Chunk(en: "", zh: "", role: role, children: children)
    }

    // MARK: - Helpers

    /// Returns the portion of the buffer AFTER the `"analysis": {...}` block closes.
    /// If the analysis block hasn't closed yet, returns nil.
    /// If there's no "analysis" key, returns the full text (en/zh come first in read mode).
    private func textAfterAnalysisBlock(_ text: String) -> String? {
        let key = "\"analysis\""
        guard let keyRange = text.range(of: key) else {
            // No analysis key — en/zh are at the top level (read mode), use full text
            return text
        }

        // Find the opening { of the analysis value
        var searchIdx = keyRange.upperBound
        while searchIdx < text.endIndex {
            let c = text[searchIdx]
            if c == "{" { break }
            if c == ":" || c == " " || c == "\t" || c == "\n" || c == "\r" {
                searchIdx = text.index(after: searchIdx)
                continue
            }
            return nil // unexpected
        }
        guard searchIdx < text.endIndex else { return nil }

        // Extract substring starting from { and find matching }
        let substring = String(text[searchIdx...])
        guard let braceEnd = findMatchingBrace(in: substring) else {
            // Analysis block not yet closed — don't extract en/zh
            return nil
        }

        // braceEnd is relative to substring; convert to offset
        let offset = substring.distance(from: substring.startIndex, to: braceEnd)
        let afterIdx = text.index(searchIdx, offsetBy: offset)
        return String(text[afterIdx...])
    }

    /// Find the index after the matching `}` for a string starting with `{`.
    /// Correctly handles nested braces, string literals, and escape sequences.
    private func findMatchingBrace(in text: String) -> String.Index? {
        guard text.first == "{" else { return nil }

        var depth = 0
        var inString = false
        var escaped = false

        for i in text.indices {
            let char = text[i]

            if escaped {
                escaped = false
                continue
            }

            if char == "\\" && inString {
                escaped = true
                continue
            }

            if char == "\"" {
                inString.toggle()
                continue
            }

            if !inString {
                if char == "{" {
                    depth += 1
                } else if char == "}" {
                    depth -= 1
                    if depth == 0 {
                        return text.index(after: i)
                    }
                }
            }
        }

        return nil
    }

    private func unescapeJSON(_ raw: String) -> String {
        let escaped = "\"\(raw)\""
        guard let data = escaped.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(String.self, from: data) else {
            return raw
        }
        return decoded
    }
}

// MARK: - Stream Response Models
private struct StreamChunk: Codable {
    let choices: [Choice]

    struct Choice: Codable {
        let delta: Delta
    }

    struct Delta: Codable {
        let content: String?
    }
}
