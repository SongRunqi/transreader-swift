import Foundation

struct DictionaryEntry: Codable, Sendable {
    let word: String
    let phonetic: String?
    let meanings: [String]
    let examples: [String]
    let synonyms: [String]
    let relatedWords: [String]
}

actor DictionaryService {
    private let configStore: ConfigStore

    // Audio pronunciation cache: "word_type" → audio data
    private var audioCache: [String: Data] = [:]
    private var audioCacheOrder: [String] = []  // for LRU eviction
    private let audioCacheLimit = 50

    init(configStore: ConfigStore) {
        self.configStore = configStore
    }

    // MARK: - Audio Pronunciation

    func fetchAudio(for word: String, type: Int = 1) async throws -> Data {
        let cacheKey = "\(word)_\(type)"

        // Check cache
        if let cached = audioCache[cacheKey] {
            return cached
        }

        // Download from Youdao
        let encoded = word.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? word
        guard let url = URL(string: "https://dict.youdao.com/dictvoice?audio=\(encoded)&type=\(type)") else {
            throw AudioError.invalidURL
        }

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw AudioError.downloadFailed
        }

        guard !data.isEmpty else {
            throw AudioError.emptyData
        }

        // Store in cache with LRU eviction
        audioCache[cacheKey] = data
        audioCacheOrder.removeAll { $0 == cacheKey }
        audioCacheOrder.append(cacheKey)
        if audioCacheOrder.count > audioCacheLimit {
            let evicted = audioCacheOrder.removeFirst()
            audioCache.removeValue(forKey: evicted)
        }

        return data
    }

    enum AudioError: LocalizedError {
        case invalidURL
        case downloadFailed
        case emptyData

        var errorDescription: String? {
            switch self {
            case .invalidURL: return "无效的音频 URL"
            case .downloadFailed: return "音频下载失败"
            case .emptyData: return "音频数据为空"
            }
        }
    }

    enum LookupError: LocalizedError {
        case noAPIKey
        case requestFailed
        case invalidResponse
        case invalidContent

        var errorDescription: String? {
            switch self {
            case .noAPIKey: return "未配置 API Key"
            case .requestFailed: return "API 请求失败"
            case .invalidResponse: return "API 返回格式无效"
            case .invalidContent: return "无法解析 AI 返回的词典数据"
            }
        }
    }
    
    func lookupWord(_ word: String) async throws -> DictionaryEntry {
        // Try Youdao dictionary first
        if let entry = try? await lookupYoudao(word) {
            return entry
        }
        
        // Fallback to AI
        return try await lookupWithAI(word)
    }
    
    private func lookupYoudao(_ word: String) async throws -> DictionaryEntry? {
        let encoded = word.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? word
        let urlString = "https://dict.youdao.com/jsonapi_s?doctype=json&jsonversion=4&le=en&q=\(encoded)"
        
        guard let url = URL(string: urlString) else {
            return nil
        }
        
        let (data, response) = try await URLSession.shared.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            return nil
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        
        // Parse phonetic
        var phonetic: String?
        if let ec = json["ec"] as? [String: Any],
           let word = ec["word"] as? [String: Any] {
            phonetic = word["ukphone"] as? String ?? word["usphone"] as? String
        }
        if phonetic == nil,
           let simple = json["simple"] as? [String: Any],
           let word = simple["word"] as? [[String: Any]],
           let first = word.first {
            phonetic = first["ukphone"] as? String ?? first["usphone"] as? String
        }
        
        // Parse meanings (ec.word.trs[].pos + trs[].tran)
        var meanings: [String] = []
        if let ec = json["ec"] as? [String: Any],
           let word = ec["word"] as? [String: Any],
           let trs = word["trs"] as? [[String: Any]] {
            for tr in trs {
                let pos = tr["pos"] as? String ?? ""
                let tran = tr["tran"] as? String ?? ""
                if !tran.isEmpty {
                    meanings.append(pos.isEmpty ? tran : "\(pos) \(tran)")
                }
            }
        }
        
        // Parse examples (blng_sents_part.sentence-pair[].sentence-eng)
        var examples: [String] = []
        if let blng = json["blng_sents_part"] as? [String: Any],
           let pairs = blng["sentence-pair"] as? [[String: Any]] {
            for pair in pairs.prefix(3) {
                if let eng = pair["sentence-eng"] as? String {
                    examples.append(eng)
                }
            }
        }
        
        // Parse synonyms (syno.synos[].pos + .tran)
        var synonyms: [String] = []
        if let syno = json["syno"] as? [String: Any],
           let synos = syno["synos"] as? [[String: Any]] {
            for item in synos {
                if let pos = item["pos"] as? String,
                   let tran = item["tran"] as? String {
                    synonyms.append("\(pos): \(tran)")
                }
            }
        }
        
        // Parse related words (rel_word.rels[].pos + .words[].word)
        var relatedWords: [String] = []
        if let relWord = json["rel_word"] as? [String: Any],
           let rels = relWord["rels"] as? [[String: Any]] {
            for rel in rels {
                if let words = rel["words"] as? [[String: Any]] {
                    for wordItem in words {
                        if let w = wordItem["word"] as? String {
                            relatedWords.append(w)
                        }
                    }
                }
            }
        }
        
        guard !meanings.isEmpty else {
            return nil
        }
        
        return DictionaryEntry(
            word: word,
            phonetic: phonetic,
            meanings: meanings,
            examples: examples,
            synonyms: synonyms,
            relatedWords: relatedWords
        )
    }
    
    private func lookupWithAI(_ word: String) async throws -> DictionaryEntry {
        guard let apiKey = configStore.apiKey else { throw LookupError.noAPIKey }
        
        let providerId = configStore.provider
        let provider = Providers.provider(for: providerId)
        let url = URL(string: "\(provider.baseURL)/chat/completions")!
        
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let prompt = """
        Please provide a dictionary entry for the word "\(word)" in JSON format:
        {
          "word": "\(word)",
          "phonetic": "UK pronunciation (IPA)",
          "meanings": ["part of speech: definition", ...],
          "examples": ["example sentence 1", ...],
          "synonyms": ["synonym1", ...],
          "related_words": ["related1", ...]
        }
        Only output JSON, no other text.
        """
        
        let payload: [String: Any] = [
            "model": configStore.modelForProvider(providerId),
            "temperature": 0.3,
            "messages": [
                ["role": "user", "content": prompt]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw LookupError.requestFailed
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              var content = message["content"] as? String else {
            throw LookupError.invalidResponse
        }
        
        // Remove markdown code blocks if present
        if content.hasPrefix("```") {
            let lines = content.components(separatedBy: "\n").dropFirst().dropLast()
            content = lines.joined(separator: "\n")
        }
        content = content.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard let contentData = content.data(using: .utf8),
              let entryJSON = try? JSONSerialization.jsonObject(with: contentData) as? [String: Any] else {
            throw LookupError.invalidContent
        }
        
        return DictionaryEntry(
            word: entryJSON["word"] as? String ?? word,
            phonetic: entryJSON["phonetic"] as? String,
            meanings: entryJSON["meanings"] as? [String] ?? [],
            examples: entryJSON["examples"] as? [String] ?? [],
            synonyms: entryJSON["synonyms"] as? [String] ?? [],
            relatedWords: entryJSON["related_words"] as? [String] ?? []
        )
    }
}
