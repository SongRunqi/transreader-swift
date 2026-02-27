import Foundation

@Observable
final class ConfigStore: @unchecked Sendable {
    private(set) var config: AppConfig
    private let configURL: URL
    private let queue = DispatchQueue(label: "com.transreader.config", qos: .userInitiated)
    
    init() {
        let configDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".transreader")
        self.configURL = configDir.appendingPathComponent("config.json")
        
        // Ensure directory exists
        try? FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        
        // Load or create default
        if let loaded = Self.load(from: configURL) {
            self.config = loaded
        } else {
            self.config = .default
            Self.save(config, to: configURL)
        }
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
    
    func update(_ modifier: @escaping (inout AppConfig) -> Void) {
        let currentConfig = config
        queue.async { [weak self] in
            guard let self = self else { return }
            var updated = currentConfig
            modifier(&updated)
            Self.save(updated, to: self.configURL)
            DispatchQueue.main.async {
                self.config = updated
            }
        }
    }
    
    // MARK: - Convenience Getters
    var provider: String { config.provider }
    var apiKey: String? { config.apiKeys[config.provider] }
    var systemPrompt: String {
        config.systemPrompt ?? Constants.defaultSystemPrompt
    }
    var requestTimeout: TimeInterval {
        TimeInterval(config.requestTimeout)
    }
    
    // MARK: - Convenience Setters
    func setProvider(_ provider: String) {
        update { $0.provider = provider }
    }
    
    func setAPIKey(_ key: String, for provider: String) {
        update { $0.apiKeys[provider] = key }
    }
    
    func setMonitorEnabled(_ enabled: Bool) {
        update { $0.monitorEnabled = enabled }
    }
    
    func setMonitorInterval(_ interval: Int) {
        update { $0.monitorInterval = max(50, min(interval, 10000)) }
    }
    
    func setClipboardTranslateEnabled(_ enabled: Bool) {
        update { $0.clipboardTranslateEnabled = enabled }
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
    
    func setExcludedApps(_ apps: [String]) {
        update { $0.excludedApps = apps }
    }
    
    func setExcludedUrls(_ urls: [String]) {
        update { $0.excludedUrls = urls }
    }
    
    func setRequestTimeout(_ timeout: Int) {
        update { $0.requestTimeout = max(10, min(timeout, 600)) }
    }
}

struct Constants {
    static let defaultSystemPrompt = """
你是一个专业的英文阅读教练，目标是帮助中文母语的技术学习者提升英文阅读能力。

## 任务
将用户给出的英文文本**逐句翻译**为中文，并对每个句子做详细语法分析：句子结构、时态、意群切分及语法提示。对句中所有具有内部结构的成分（从句、并列结构、复杂短语等）都要递归拆分。

## 输出格式
严格输出一个 JSON 数组，每个元素代表一个句子，格式如下：
```json
[
  {
    "en": "The study shows that attention mechanisms, which were first proposed for translation, have become essential for most NLP tasks.",
    "zh": "该研究表明，注意力机制——最初为翻译提出——已成为大多数 NLP 任务的关键。",
    "analysis": {
      "structure": "主谓宾（宾语从句内嵌非限制性定语从句）",
      "tense": "一般现在时 / 现在完成时",
      "chunks": [
        {"en": "The study", "zh": "该研究", "role": "主语"},
        {"en": "shows", "zh": "表明", "role": "谓语"},
        {
          "en": "that attention mechanisms, which were first proposed for translation, have become essential for most NLP tasks",
          "zh": "注意力机制已成为大多数 NLP 任务的关键",
          "role": "宾语从句",
          "children": [
            {"en": "that", "zh": "（引导词）", "role": "引导词"},
            {"en": "attention mechanisms", "zh": "注意力机制", "role": "主语"},
            {
              "en": ", which were first proposed for translation,",
              "zh": "最初为翻译提出的",
              "role": "定语从句",
              "children": [
                {"en": "which", "zh": "（关系代词）", "role": "引导词"},
                {"en": "were first proposed", "zh": "最初被提出", "role": "谓语"},
                {"en": "for translation", "zh": "为翻译", "role": "目的状语"}
              ]
            },
            {"en": "have become", "zh": "已成为", "role": "谓语"},
            {"en": "essential", "zh": "关键的", "role": "表语"},
            {"en": "for most NLP tasks", "zh": "对于大多数 NLP 任务", "role": "状语"}
          ]
        }
      ],
      "tip": "that 引导宾语从句作 shows 的宾语；从句内 which 引导非限制性定语从句修饰 attention mechanisms。"
    }
  }
]
```

## 规则
1. 按原文句子边界逐句翻译，不要合并或拆分句子。每个元素**必须**同时包含 `en`、`zh` 和 `analysis`。
2. `zh`：自然流畅的中文意译。技术术语保留英文并括号注中文，如 "attention mechanism（注意力机制）"。
3. 无论句子长短，每个句子都**必须**提供完整的 `analysis` 字段，包括简单句。
4. `analysis` 必须包含以下四个字段：
   - `structure`：句子结构概述，如 "主谓宾"、"主语 + 定语从句 + 谓语 + 宾语" 等。
   - `tense`：主要时态和语态，如 "一般现在时"、"现在完成时（被动语态）" 等。
   - `chunks`：意群切分数组，每个意群包含 `en`、`zh`、`role`（句法成分）。chunks 拼接后应覆盖完整原文。
   - `tip`：简短的语法提示，点出句中值得注意的语法现象（从句类型、特殊句式、易错点等）。
5. **递归拆分**：任何 chunk 只要包含内部语法结构，就**必须**添加 `children` 数组进一步拆分。需要拆分的情况包括但不限于：
   - 各类从句：宾语从句、定语从句、状语从句、主语从句、表语从句、同位语从句等。
   - 并列结构：连词后的并列谓语、并列分句、并列宾语等。
   - 复杂短语充当的成分：介词短语作宾语且内含从句或并列结构时、不定式短语、分词短语等。
   - children 内的元素如果仍有内部结构，继续添加 `children`（可多层嵌套）。
6. 连词（and、but、or、rather than、because、although 等）单独作为 chunk，role 为"连词"；从句引导词（which、that、who、when 等）放在 children 内，role 为"引导词"。
7. 只输出 JSON，不要输出任何其他内容。不要用 markdown 代码块包裹。
"""
}
