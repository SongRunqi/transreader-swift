import Foundation

@Observable
final class ConfigStore: @unchecked Sendable {
    private(set) var config: AppConfig
    @ObservationIgnored
    private var latestConfig: AppConfig
    private let configURL: URL
    private let queue = DispatchQueue(label: "com.transreader.config", qos: .userInitiated)
    
    init() {
        let configDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".transreader")
        self.configURL = configDir.appendingPathComponent("config.json")
        
        // Ensure directory exists
        try? FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        
        let initialConfig: AppConfig
        // Load or create default, with backward compatibility
        if var loaded = Self.load(from: configURL) {
            // Migrate old excluded_apps → included_apps
            if loaded.includedApps.isEmpty {
                // Check if old config had excluded_apps by reading raw JSON
                if let data = try? Data(contentsOf: configURL),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   json["excluded_apps"] != nil && json["included_apps"] == nil {
                    loaded.includedApps = AppConfig.defaultIncludedApps
                }
            }
            loaded.provider = Providers.validatedId(loaded.provider)
            // Migrate plaintext legacy API keys into Keychain, then keep the
            // in-memory config hydrated for existing UI code paths.
            for (provider, key) in loaded.apiKeys where !key.isEmpty {
                KeychainStore.setAPIKey(key, for: provider)
            }
            loaded.apiKeys = Self.loadKeychainAPIKeys()
            initialConfig = loaded
        } else {
            var defaultConfig = AppConfig.default
            defaultConfig.apiKeys = Self.loadKeychainAPIKeys()
            initialConfig = defaultConfig
            Self.save(defaultConfig, to: configURL)
        }
        self.config = initialConfig
        self.latestConfig = initialConfig
        Self.save(initialConfig, to: configURL)
    }
    
    private static func load(from url: URL) -> AppConfig? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        return try? decoder.decode(AppConfig.self, from: data)
    }
    
    private static func save(_ config: AppConfig, to url: URL) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(config) else { return }
        try? data.write(to: url, options: .atomic)
    }
    
    func update(_ modifier: @escaping @Sendable (inout AppConfig) -> Void) {
        queue.async { [weak self] in
            guard let self = self else { return }
            var updated = self.latestConfig
            modifier(&updated)
            updated.provider = Providers.validatedId(updated.provider)
            for provider in Providers.all.keys {
                KeychainStore.setAPIKey(updated.apiKeys[provider], for: provider)
            }
            updated.apiKeys = Self.loadKeychainAPIKeys()
            let snapshot = updated
            Self.save(snapshot, to: self.configURL)
            self.latestConfig = snapshot
            DispatchQueue.main.async {
                self.config = snapshot
            }
        }
    }
    
    // MARK: - Convenience Getters
    var provider: String { Providers.validatedId(config.provider) }
    var apiKey: String? { apiKey(for: provider) }
    var systemPrompt: String {
        if let custom = config.systemPrompt, !custom.isEmpty {
            return custom
        }
        switch config.displayMode {
        case .analyze:
            return Constants.defaultSystemPrompt
        case .read:
            return Constants.defaultSystemPromptRead
        }
    }
    var requestTimeout: TimeInterval {
        TimeInterval(config.requestTimeout)
    }
    
    // MARK: - Convenience Setters
    func setProvider(_ provider: String) {
        update { $0.provider = provider }
    }
    
    func setAPIKey(_ key: String, for provider: String) {
        update { $0.apiKeys[provider] = key.isEmpty ? nil : key }
    }
    
    func setMonitorEnabled(_ enabled: Bool) {
        update { $0.monitorEnabled = enabled }
    }
    
    func setMonitorInterval(_ interval: Int) {
        update { $0.monitorInterval = max(50, min(interval, 10000)) }
    }
    
    func setSystemPrompt(_ prompt: String?) {
        update { $0.systemPrompt = prompt }
    }
    
    func setShortcuts(_ shortcuts: [String: String]) {
        update { $0.shortcuts = shortcuts }
    }
    
    func setVocabFile(_ path: String) {
        update { $0.vocabFile = path }
    }
    
    func setIncludedApps(_ apps: [String]) {
        update { $0.includedApps = apps }
    }

    func setExcludedUrls(_ urls: [String]) {
        update { $0.excludedUrls = urls }
    }

    func setRequestTimeout(_ timeout: Int) {
        update { $0.requestTimeout = max(10, min(timeout, 600)) }
    }

    func setDisplayMode(_ mode: DisplayMode) {
        update { $0.displayMode = mode }
    }

    func setLongTextThreshold(_ threshold: Int) {
        update { $0.longTextThreshold = max(100, min(threshold, 5000)) }
    }

    var displayMode: DisplayMode { config.displayMode }
    var longTextThreshold: Int { config.longTextThreshold }

    func modelForProvider(_ providerId: String) -> String {
        let validated = Providers.validatedId(providerId)
        if let custom = config.customModels[validated], !custom.isEmpty {
            return custom
        }
        return Providers.provider(for: validated).model
    }

    func apiKey(for provider: String) -> String? {
        let validated = Providers.validatedId(provider)
        return KeychainStore.apiKey(for: validated) ?? config.apiKeys[validated]
    }

    func hasAPIKey(for provider: String) -> Bool {
        !(apiKey(for: provider)?.isEmpty ?? true)
    }

    private static func loadKeychainAPIKeys() -> [String: String] {
        var keys: [String: String] = [:]
        for provider in Providers.all.keys {
            if let key = KeychainStore.apiKey(for: provider), !key.isEmpty {
                keys[provider] = key
            }
        }
        return keys
    }
}

struct Constants {
    static let defaultSystemPrompt = """
你是专业英文阅读教练，帮助中文母语技术学习者提升英文阅读能力。

## 任务
将英文文本**逐句翻译**为中文，并对每句做语法分析（句型、时态、意群切分、语法提示）。

## 输出格式
JSON 数组，字段顺序 `analysis` → `en` → `zh` → `structure` → `tense` → `tip`：
```json
[
  {
    "analysis": {
      "chunks": [
        {"role": "主语", "en": "The study", "zh": "该研究"},
        {"role": "谓语", "en": "shows", "zh": "表明"},
        {
          "role": "宾语从句",
          "children": [
            {"role": "引导词", "en": "that", "zh": "（引导词）"},
            {"role": "主语", "en": "attention mechanisms", "zh": "注意力机制"},
            {
              "role": "定语从句",
              "children": [
                {"role": "引导词", "en": "which", "zh": "（关系代词）"},
                {"role": "谓语", "en": "were first proposed", "zh": "最初被提出"},
                {"role": "目的状语", "en": "for translation", "zh": "为翻译"}
              ]
            },
            {"role": "谓语", "en": "have become", "zh": "已成为"},
            {"role": "表语", "en": "essential", "zh": "关键的"},
            {"role": "状语", "en": "for most NLP tasks", "zh": "对于大多数 NLP 任务"}
          ]
        }
      ]
    },
    "en": "The study shows that attention mechanisms, which were first proposed for translation, have become essential for most NLP tasks.",
    "zh": "该研究表明，注意力机制——最初为翻译提出——已成为大多数 NLP 任务的关键。",
    "structure": "主谓宾（宾语从句内嵌非限制性定语从句）",
    "tense": "一般现在时 / 现在完成时",
    "tip": "that 引导宾语从句作 shows 的宾语；从句内 which 引导非限制性定语从句修饰 attention mechanisms。"
  },
  {
    "analysis": {
      "chunks": [
        {"role": "主语", "en": "The encoder", "zh": "编码器"},
        {"role": "谓语", "en": "processes", "zh": "处理"},
        {"role": "宾语", "en": "the input", "zh": "输入"},
        {"role": "连词", "en": ", while", "zh": "而"},
        {
          "role": "并列分句",
          "children": [
            {"role": "主语", "en": "the decoder", "zh": "解码器"},
            {"role": "谓语", "en": "generates", "zh": "生成"},
            {"role": "宾语", "en": "the output", "zh": "输出"}
          ]
        },
        {"role": "标点", "en": ".", "zh": "。"}
      ]
    },
    "en": "The encoder processes the input, while the decoder generates the output.",
    "zh": "编码器处理输入，而解码器生成输出。",
    "structure": "并列句（while 引导对比分句）",
    "tense": "一般现在时",
    "tip": "while 表对比，连接两个并列分句；while 从句成分必须嵌套在并列分句的 children 内。"
  }
]
```

## 规则
1. 按原文句子边界逐句翻译，不合并不拆分。每句**必须**包含 `analysis`、`en`、`zh`、`structure`、`tense`、`tip` 六个字段（包括简单句），字段顺序如上。
2. `zh`：自然流畅的中文意译。技术术语保留英文并括号注中文，如 "attention mechanism（注意力机制）"。
3. `analysis` 只含 `chunks` 数组。叶子节点含 `role`、`en`、`zh`；分支节点**只含 `role` 和 `children`，不输出 `en`/`zh`**。所有叶子 en 拼接须覆盖完整原文。
4. `structure`(句型概述)、`tense`(时态语态)、`tip`(语法提示) 均与 `en`/`zh` 同级。
5. **递归拆分**：含内部结构的 chunk **必须**用 `children` 拆分，包括：从句（宾语/定语/状语/主语/表语/同位语从句等）、并列结构（并列谓语/分句/宾语等）、复杂短语（介词短语含从句、不定式、分词短语等）。children 内仍有结构则继续嵌套。**禁止**将从句或并列分句的成分平铺在顶层 chunks——必须嵌套在对应分支节点的 children 内。
6. 连词（and/but/or/while/because/although 等）单独作 chunk，role"连词"；从句引导词（which/that/who/when 等）放在 children 内，role"引导词"。while/when/because/although 等引导的从句，连词单独作 chunk，从句整体作含 children 的分支节点。
7. 只输出 JSON，不要输出任何其他内容，不要用 markdown 代码块包裹。
"""

    static let defaultSystemPromptRead = """
你是专业英文阅读教练，帮助中文母语技术学习者提升英文阅读能力。

## 任务
将英文文本**逐句翻译**为中文，并对每句做语法分析（句型、时态、意群切分、语法提示）。

## 输出格式
JSON 数组，字段顺序 `en` → `zh` → `structure` → `tense` → `analysis` → `tip`：
```json
[
  {
    "en": "The study shows that attention mechanisms, which were first proposed for translation, have become essential for most NLP tasks.",
    "zh": "该研究表明，注意力机制——最初为翻译提出——已成为大多数 NLP 任务的关键。",
    "structure": "主谓宾（宾语从句内嵌非限制性定语从句）",
    "tense": "一般现在时 / 现在完成时",
    "analysis": {
      "chunks": [
        {"role": "主语", "en": "The study", "zh": "该研究"},
        {"role": "谓语", "en": "shows", "zh": "表明"},
        {
          "role": "宾语从句",
          "children": [
            {"role": "引导词", "en": "that", "zh": "（引导词）"},
            {"role": "主语", "en": "attention mechanisms", "zh": "注意力机制"},
            {
              "role": "定语从句",
              "children": [
                {"role": "引导词", "en": "which", "zh": "（关系代词）"},
                {"role": "谓语", "en": "were first proposed", "zh": "最初被提出"},
                {"role": "目的状语", "en": "for translation", "zh": "为翻译"}
              ]
            },
            {"role": "谓语", "en": "have become", "zh": "已成为"},
            {"role": "表语", "en": "essential", "zh": "关键的"},
            {"role": "状语", "en": "for most NLP tasks", "zh": "对于大多数 NLP 任务"}
          ]
        }
      ]
    },
    "tip": "that 引导宾语从句作 shows 的宾语；从句内 which 引导非限制性定语从句修饰 attention mechanisms。"
  },
  {
    "en": "The encoder processes the input, while the decoder generates the output.",
    "zh": "编码器处理输入，而解码器生成输出。",
    "structure": "并列句（while 引导对比分句）",
    "tense": "一般现在时",
    "analysis": {
      "chunks": [
        {"role": "主语", "en": "The encoder", "zh": "编码器"},
        {"role": "谓语", "en": "processes", "zh": "处理"},
        {"role": "宾语", "en": "the input", "zh": "输入"},
        {"role": "连词", "en": ", while", "zh": "而"},
        {
          "role": "并列分句",
          "children": [
            {"role": "主语", "en": "the decoder", "zh": "解码器"},
            {"role": "谓语", "en": "generates", "zh": "生成"},
            {"role": "宾语", "en": "the output", "zh": "输出"}
          ]
        },
        {"role": "标点", "en": ".", "zh": "。"}
      ]
    },
    "tip": "while 表对比，连接两个并列分句；while 从句成分必须嵌套在并列分句的 children 内。"
  }
]
```

## 规则
1. 按原文句子边界逐句翻译，不合并不拆分。每句**必须**包含 `en`、`zh`、`structure`、`tense`、`analysis`、`tip` 六个字段（包括简单句），字段顺序如上。
2. `zh`：自然流畅的中文意译。技术术语保留英文并括号注中文，如 "attention mechanism（注意力机制）"。
3. `analysis` 只含 `chunks` 数组。叶子节点含 `role`、`en`、`zh`；分支节点**只含 `role` 和 `children`，不输出 `en`/`zh`**。所有叶子 en 拼接须覆盖完整原文。
4. `structure`(句型概述)、`tense`(时态语态)、`tip`(语法提示) 均与 `en`/`zh` 同级。
5. **递归拆分**：含内部结构的 chunk **必须**用 `children` 拆分，包括：从句（宾语/定语/状语/主语/表语/同位语从句等）、并列结构（并列谓语/分句/宾语等）、复杂短语（介词短语含从句、不定式、分词短语等）。children 内仍有结构则继续嵌套。**禁止**将从句或并列分句的成分平铺在顶层 chunks——必须嵌套在对应分支节点的 children 内。
6. 连词（and/but/or/while/because/although 等）单独作 chunk，role"连词"；从句引导词（which/that/who/when 等）放在 children 内，role"引导词"。while/when/because/although 等引导的从句，连词单独作 chunk，从句整体作含 children 的分支节点。
7. 只输出 JSON，不要输出任何其他内容，不要用 markdown 代码块包裹。
"""

    static let grammarFixSystemPrompt = """
你是一个英文写作助手。请修正以下英文文本的语法和拼写错误，改善表达使其更加自然地道。

## 规则
1. 只修正语法、拼写和表达问题，不要改变原文含义。
2. 保持原文的风格和语气。
3. 只输出修正后的文本，不要输出任何解释或注释。
"""

    static let zhEnSystemPrompt = """
你是一个专业的中英翻译助手。请将以下中文文本翻译为地道的英文。

## 规则
1. 翻译要自然流畅，符合英文表达习惯。
2. 专业术语要准确。
3. 只输出翻译后的英文文本，不要输出任何解释或注释。
"""
}
