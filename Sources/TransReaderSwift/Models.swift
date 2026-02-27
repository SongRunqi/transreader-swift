import Foundation

// MARK: - Provider Configuration
struct Provider: Codable, Sendable {
    let id: String
    let name: String
    let baseURL: String
    let model: String
}

struct Providers {
    static let all: [String: Provider] = [
        "deepseek": Provider(id: "deepseek", name: "DeepSeek", 
                            baseURL: "https://api.deepseek.com/v1", 
                            model: "deepseek-chat"),
        "minimax": Provider(id: "minimax", name: "MiniMax", 
                           baseURL: "https://api.minimax.chat/v1", 
                           model: "MiniMax-Text-01"),
        "glm": Provider(id: "glm", name: "GLM", 
                       baseURL: "https://open.bigmodel.cn/api/paas/v4", 
                       model: "glm-4-flash")
    ]
}

// MARK: - Translation Models
struct Chunk: Codable, Sendable {
    let en: String
    let zh: String
    let role: String
    let children: [Chunk]?
}

struct Analysis: Codable, Sendable {
    let structure: String
    let tense: String
    let chunks: [Chunk]
    let tip: String
}

struct Sentence: Codable, Sendable {
    let en: String
    let zh: String
    let analysis: Analysis?
    var isPartial: Bool
    var index: Int
    
    enum CodingKeys: String, CodingKey {
        case en, zh, analysis
        case isPartial = "_partial"
        case index = "_idx"
    }
}

struct TranslationResult: Sendable, Hashable {
    let timestamp: Date
    let sourceText: String
    let sentences: [Sentence]
    let source: TranslationSource
    let elapsedMs: Int
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(timestamp)
    }
    
    static func == (lhs: TranslationResult, rhs: TranslationResult) -> Bool {
        lhs.timestamp == rhs.timestamp
    }
}

extension Sentence: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(en)
        hasher.combine(index)
    }
    
    static func == (lhs: Sentence, rhs: Sentence) -> Bool {
        lhs.en == rhs.en && lhs.index == rhs.index
    }
}

extension Chunk: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(en)
        hasher.combine(role)
    }
}

extension Analysis: Hashable {}

enum TranslationSource: String, Codable, Sendable {
    case ocr
    case selection
    case retranslate
    case manual
}

// MARK: - Config Models
struct AppConfig: Codable, Sendable {
    var provider: String
    var apiKeys: [String: String]
    var port: Int
    var monitorEnabled: Bool
    var monitorInterval: Int
    var clipboardTranslateEnabled: Bool
    var systemPrompt: String?
    var shortcuts: [String: String]
    var vocabFile: String
    var excludedApps: [String]
    var excludedUrls: [String]
    var requestTimeout: Int
    
    enum CodingKeys: String, CodingKey {
        case provider, port, shortcuts
        case apiKeys = "api_keys"
        case monitorEnabled = "monitor_enabled"
        case monitorInterval = "monitor_interval"
        case clipboardTranslateEnabled = "clipboard_translate_enabled"
        case systemPrompt = "system_prompt"
        case vocabFile = "vocab_file"
        case excludedApps = "excluded_apps"
        case excludedUrls = "excluded_urls"
        case requestTimeout = "request_timeout"
    }
    
    static let `default` = AppConfig(
        provider: "deepseek",
        apiKeys: [:],
        port: 15487,
        monitorEnabled: false,
        monitorInterval: 1000,
        clipboardTranslateEnabled: false,
        systemPrompt: nil,
        shortcuts: [
            "capture_translate": "t",
            "toggle_window": "w",
            "toggle_pin": "p",
            "toggle_monitor": "m",
            "quit": "q"
        ],
        vocabFile: "~/.transreader/vocab.canvas",
        excludedApps: ["TransReader"],
        excludedUrls: [],
        requestTimeout: 120
    )
}

// MARK: - Vocab Models
struct VocabEntry: Codable, Sendable {
    var word: String
    var phonetic: String?
    var meanings: [String]?
    var examples: [String]?
    var synonyms: [String]?
    var addedAt: String
    
    enum CodingKeys: String, CodingKey {
        case word, phonetic, meanings, examples, synonyms
        case addedAt = "added_at"
    }
}

struct VocabData: Codable, Sendable {
    var version: Int
    var words: [VocabEntry]
    
    static let empty = VocabData(version: 1, words: [])
}
