import Foundation

struct DictionaryEntry: Sendable {
    let word: String
    let phonetic: String?
    let meanings: [String]
    let examples: [String]
    let synonyms: [String]
    let relatedWords: [String]
}

actor DictionaryService {
    private let configStore: ConfigStore
    
    init(configStore: ConfigStore) {
        self.configStore = configStore
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
        
        // Parse phonetic (simple)
        var phonetic: String?
        if let simple = json["simple"] as? [String: Any],
           let word = simple["word"] as? [[String: Any]],
           let first = word.first,
           let ukphone = first["ukphone"] as? String {
            phonetic = ukphone
        }
        
        // Parse meanings (ec.word[].trs[].tr[].l.i)
        var meanings: [String] = []
        if let ec = json["ec"] as? [String: Any],
           let word = ec["word"] as? [[String: Any]] {
            for wordItem in word {
                if let trs = wordItem["trs"] as? [[String: Any]] {
                    for tr in trs {
                        if let trList = tr["tr"] as? [[String: Any]] {
                            for trItem in trList {
                                if let l = trItem["l"] as? [String: Any],
                                   let i = l["i"] as? [String] {
                                    meanings.append(contentsOf: i)
                                }
                            }
                        }
                    }
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
        guard let apiKey = configStore.apiKey else {
            throw NSError(domain: "DictionaryService", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "未配置 API Key"
            ])
        }
        
        let provider = Providers.all[configStore.provider]!
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
            "model": provider.model,
            "temperature": 0.3,
            "messages": [
                ["role": "user", "content": prompt]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw NSError(domain: "DictionaryService", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "API 请求失败"
            ])
        }
        
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let choices = json["choices"] as! [[String: Any]]
        let message = choices[0]["message"] as! [String: Any]
        var content = message["content"] as! String
        
        // Remove markdown code blocks if present
        if content.hasPrefix("```") {
            let lines = content.components(separatedBy: "\n").dropFirst().dropLast()
            content = lines.joined(separator: "\n")
        }
        content = content.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard let contentData = content.data(using: .utf8),
              let entryJSON = try? JSONSerialization.jsonObject(with: contentData) as? [String: Any] else {
            throw NSError(domain: "DictionaryService", code: 3, userInfo: [
                NSLocalizedDescriptionKey: "无法解析 AI 返回的词典数据"
            ])
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
