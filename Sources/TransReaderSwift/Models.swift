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
                       model: "glm-4-flash"),
        "kimi": Provider(id: "kimi", name: "Kimi",
                        baseURL: "https://api.moonshot.cn/v1",
                        model: "moonshot-v1-auto")
    ]
}

// MARK: - Translation Models
struct Chunk: Codable, Sendable {
    let en: String
    let zh: String
    let role: String
    let children: [Chunk]?

    init(en: String, zh: String, role: String, children: [Chunk]?) {
        self.en = en; self.zh = zh; self.role = role; self.children = children
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        en = try c.decodeIfPresent(String.self, forKey: .en) ?? ""
        zh = try c.decodeIfPresent(String.self, forKey: .zh) ?? ""
        role = try c.decodeIfPresent(String.self, forKey: .role) ?? ""
        children = try c.decodeIfPresent([Chunk].self, forKey: .children)
    }
}

struct Analysis: Codable, Sendable {
    let structure: String
    let tense: String
    let chunks: [Chunk]
    let tip: String

    init(structure: String, tense: String, chunks: [Chunk], tip: String) {
        self.structure = structure; self.tense = tense; self.chunks = chunks; self.tip = tip
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        structure = try c.decodeIfPresent(String.self, forKey: .structure) ?? ""
        tense = try c.decodeIfPresent(String.self, forKey: .tense) ?? ""
        chunks = try c.decodeIfPresent([Chunk].self, forKey: .chunks) ?? []
        tip = try c.decodeIfPresent(String.self, forKey: .tip) ?? ""
    }
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

    init(en: String, zh: String, analysis: Analysis?, isPartial: Bool, index: Int) {
        self.en = en; self.zh = zh; self.analysis = analysis
        self.isPartial = isPartial; self.index = index
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        en = try c.decode(String.self, forKey: .en)
        zh = try c.decode(String.self, forKey: .zh)
        analysis = try c.decodeIfPresent(Analysis.self, forKey: .analysis)
        isPartial = try c.decodeIfPresent(Bool.self, forKey: .isPartial) ?? false
        index = try c.decodeIfPresent(Int.self, forKey: .index) ?? 0
    }
}

struct TranslationResult: Sendable, Hashable {
    let timestamp: Date
    let sourceText: String
    let sentences: [Sentence]
    let source: TranslationSource
    let elapsedMs: Int
    let sourceApp: String
    let sourceUrl: String
    var wasCancelled: Bool

    init(timestamp: Date, sourceText: String, sentences: [Sentence],
         source: TranslationSource, elapsedMs: Int,
         sourceApp: String = "", sourceUrl: String = "",
         wasCancelled: Bool = false) {
        self.timestamp = timestamp
        self.sourceText = sourceText
        self.sentences = sentences
        self.source = source
        self.elapsedMs = elapsedMs
        self.sourceApp = sourceApp
        self.sourceUrl = sourceUrl
        self.wasCancelled = wasCancelled
    }

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
    case clipboard
    case enhance
}

// MARK: - Latency Testing
struct LatencyResult: Sendable {
    let providerId: String
    let latencyMs: Int?        // nil = test failed
    let error: String?         // failure reason
    let testedAt: Date
}

enum DisplayMode: String, Codable, Sendable {
    case analyze
    case read
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
    var includedApps: [String]
    var excludedUrls: [String]
    var requestTimeout: Int
    var displayMode: DisplayMode
    var longTextThreshold: Int
    var customModels: [String: String]
    var debugMode: Bool
    var maxConcurrentTranslations: Int
    var notificationsEnabled: Bool
    var notifyOnTranslationDone: Bool
    var notifyOnError: Bool
    var notifyOnLongOperation: Bool
    var longOperationThresholdSeconds: Int

    enum CodingKeys: String, CodingKey {
        case provider, port, shortcuts
        case apiKeys = "api_keys"
        case monitorEnabled = "monitor_enabled"
        case monitorInterval = "monitor_interval"
        case clipboardTranslateEnabled = "clipboard_translate_enabled"
        case systemPrompt = "system_prompt"
        case vocabFile = "vocab_file"
        case includedApps = "included_apps"
        case excludedUrls = "excluded_urls"
        case requestTimeout = "request_timeout"
        case displayMode = "display_mode"
        case longTextThreshold = "long_text_threshold"
        case customModels = "custom_models"
        case debugMode = "debug_mode"
        case maxConcurrentTranslations = "max_concurrent_translations"
        case notificationsEnabled = "notifications_enabled"
        case notifyOnTranslationDone = "notify_on_translation_done"
        case notifyOnError = "notify_on_error"
        case notifyOnLongOperation = "notify_on_long_operation"
        case longOperationThresholdSeconds = "long_operation_threshold_seconds"
    }

    // Resilient decoder: missing fields get sensible defaults instead of failing
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        provider = try c.decodeIfPresent(String.self, forKey: .provider) ?? "deepseek"
        apiKeys = try c.decodeIfPresent([String: String].self, forKey: .apiKeys) ?? [:]
        port = try c.decodeIfPresent(Int.self, forKey: .port) ?? 15487
        monitorEnabled = try c.decodeIfPresent(Bool.self, forKey: .monitorEnabled) ?? false
        monitorInterval = try c.decodeIfPresent(Int.self, forKey: .monitorInterval) ?? 1000
        clipboardTranslateEnabled = try c.decodeIfPresent(Bool.self, forKey: .clipboardTranslateEnabled) ?? false
        systemPrompt = try c.decodeIfPresent(String.self, forKey: .systemPrompt)
        shortcuts = try c.decodeIfPresent([String: String].self, forKey: .shortcuts) ?? AppConfig.default.shortcuts
        vocabFile = try c.decodeIfPresent(String.self, forKey: .vocabFile) ?? "~/.transreader/vocab.canvas"
        includedApps = try c.decodeIfPresent([String].self, forKey: .includedApps) ?? AppConfig.defaultIncludedApps
        excludedUrls = try c.decodeIfPresent([String].self, forKey: .excludedUrls) ?? []
        requestTimeout = try c.decodeIfPresent(Int.self, forKey: .requestTimeout) ?? 120
        displayMode = try c.decodeIfPresent(DisplayMode.self, forKey: .displayMode) ?? .analyze
        longTextThreshold = try c.decodeIfPresent(Int.self, forKey: .longTextThreshold) ?? 500
        customModels = try c.decodeIfPresent([String: String].self, forKey: .customModels) ?? [:]
        debugMode = try c.decodeIfPresent(Bool.self, forKey: .debugMode) ?? false
        maxConcurrentTranslations = try c.decodeIfPresent(Int.self, forKey: .maxConcurrentTranslations) ?? 3
        notificationsEnabled = try c.decodeIfPresent(Bool.self, forKey: .notificationsEnabled) ?? true
        notifyOnTranslationDone = try c.decodeIfPresent(Bool.self, forKey: .notifyOnTranslationDone) ?? true
        notifyOnError = try c.decodeIfPresent(Bool.self, forKey: .notifyOnError) ?? true
        notifyOnLongOperation = try c.decodeIfPresent(Bool.self, forKey: .notifyOnLongOperation) ?? false
        longOperationThresholdSeconds = try c.decodeIfPresent(Int.self, forKey: .longOperationThresholdSeconds) ?? 10
    }

    // Memberwise init for programmatic construction
    init(provider: String, apiKeys: [String: String], port: Int, monitorEnabled: Bool,
         monitorInterval: Int, clipboardTranslateEnabled: Bool, systemPrompt: String?,
         shortcuts: [String: String], vocabFile: String, includedApps: [String],
         excludedUrls: [String], requestTimeout: Int, displayMode: DisplayMode,
         longTextThreshold: Int, customModels: [String: String], debugMode: Bool,
         maxConcurrentTranslations: Int = 3,
         notificationsEnabled: Bool = true, notifyOnTranslationDone: Bool = true,
         notifyOnError: Bool = true, notifyOnLongOperation: Bool = false,
         longOperationThresholdSeconds: Int = 10) {
        self.provider = provider; self.apiKeys = apiKeys; self.port = port
        self.monitorEnabled = monitorEnabled; self.monitorInterval = monitorInterval
        self.clipboardTranslateEnabled = clipboardTranslateEnabled; self.systemPrompt = systemPrompt
        self.shortcuts = shortcuts; self.vocabFile = vocabFile; self.includedApps = includedApps
        self.excludedUrls = excludedUrls; self.requestTimeout = requestTimeout
        self.displayMode = displayMode; self.longTextThreshold = longTextThreshold
        self.customModels = customModels; self.debugMode = debugMode
        self.maxConcurrentTranslations = maxConcurrentTranslations
        self.notificationsEnabled = notificationsEnabled
        self.notifyOnTranslationDone = notifyOnTranslationDone
        self.notifyOnError = notifyOnError
        self.notifyOnLongOperation = notifyOnLongOperation
        self.longOperationThresholdSeconds = longOperationThresholdSeconds
    }

    static let defaultIncludedApps = [
        "Safari", "Google Chrome", "Chrome", "Firefox", "Arc", "Microsoft Edge",
        "Brave Browser", "Opera", "Vivaldi", "Chromium", "Orion",
        "DuckDuckGo", "Preview", "Skim", "PDF Expert", "MarginNote 3",
        "Kindle", "Books", "Reeder", "NetNewsWire", "Readwise Reader"
    ]

    static let `default` = AppConfig(
        provider: "deepseek",
        apiKeys: [:],
        port: 15487,
        monitorEnabled: false,
        monitorInterval: 1000,
        clipboardTranslateEnabled: false,
        systemPrompt: nil,
        shortcuts: [
            "capture_translate": "option+cmd+t",
            "toggle_window": "option+cmd+w",
            "toggle_pin": "option+cmd+p",
            "toggle_monitor": "option+cmd+m",
            "enhance_translate": "option+cmd+e",
            "paste_translate": "option+cmd+v"
        ],
        vocabFile: "~/.transreader/vocab.canvas",
        includedApps: defaultIncludedApps,
        excludedUrls: [],
        requestTimeout: 120,
        displayMode: .analyze,
        longTextThreshold: 500,
        customModels: [:],
        debugMode: false
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

// Make VocabEntry Hashable
extension VocabEntry: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(word)
    }
    
    static func == (lhs: VocabEntry, rhs: VocabEntry) -> Bool {
        lhs.word == rhs.word
    }
}
