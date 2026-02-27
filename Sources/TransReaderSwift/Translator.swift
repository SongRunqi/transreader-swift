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
    private var currentTask: Task<Void, Error>?
    
    init(configStore: ConfigStore) {
        self.configStore = configStore
    }
    
    func cancel() {
        currentTask?.cancel()
        currentTask = nil
    }
    
    func translateStream(
        text: String,
        onSentence: @Sendable @escaping (Sentence) -> Void
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
        
        let payload: [String: Any] = [
            "model": provider.model,
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
        var completeSentences: [Sentence] = []
        var completeIndex = 0
        var partialEmitted = false
        
        let task: Task<Void, Error> = Task {
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
                
                // Phase 2: Extract complete JSON objects
                let (objects, remaining) = extractJSONObjects(from: accumulated)
                accumulated = remaining
                
                for obj in objects {
                    var sentence = obj
                    sentence.index = completeIndex
                    sentence.isPartial = false
                    completeSentences.append(sentence)
                    onSentence(sentence)
                    completeIndex += 1
                    partialEmitted = false
                }
                
                // Phase 1: Emit partial as soon as en+zh are both complete
                if !partialEmitted, let partial = extractPartial(from: accumulated) {
                    var sentence = partial
                    sentence.index = completeIndex
                    sentence.isPartial = true
                    onSentence(sentence)
                    partialEmitted = true
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
                        onSentence(obj)
                        completeIndex += 1
                    }
                }
            }
        }
        
        self.currentTask = task
        
        do {
            try await task.value
        } catch is CancellationError {
            throw TranslatorError.cancelled
        }
        
        return completeSentences
    }
    
    // MARK: - JSON Extraction
    
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
            
            // Find matching closing brace
            var depth = 0
            var inString = false
            var escaped = false
            var endIndex: String.Index?
            
            for (i, char) in remaining.enumerated() {
                let index = remaining.index(remaining.startIndex, offsetBy: i)
                
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
                            endIndex = remaining.index(after: index)
                            break
                        }
                    }
                }
            }
            
            guard let end = endIndex else { break }
            
            let jsonStr = String(remaining[..<end])
            if let data = jsonStr.data(using: .utf8),
               let obj = try? JSONDecoder().decode(Sentence.self, from: data) {
                objects.append(obj)
            }
            
            remaining = String(remaining[end...])
        }
        
        return (objects, remaining)
    }
    
    private func extractPartial(from text: String) -> Sentence? {
        // Regex to match: "en": "...", "zh": "..."
        let pattern = #""en"\s*:\s*"((?:[^"\\]|\\.)*)"\s*,\s*"zh"\s*:\s*"((?:[^"\\]|\\.)*)""#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else {
            return nil
        }
        
        let enRange = Range(match.range(at: 1), in: text)!
        let zhRange = Range(match.range(at: 2), in: text)!
        
        let enRaw = String(text[enRange])
        let zhRaw = String(text[zhRange])
        
        return Sentence(
            en: unescapeJSON(enRaw),
            zh: unescapeJSON(zhRaw),
            analysis: nil,
            isPartial: true,
            index: 0
        )
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
