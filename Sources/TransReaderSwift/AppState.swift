import Foundation
import SwiftUI

@Observable
@MainActor
final class AppState {
    let configStore: ConfigStore
    let vocabStore: VocabStore
    let translator: Translator
    let ocrEngine: OCREngine
    
    var translationHistory: [TranslationResult] = []
    var currentTranslation: TranslationResult?
    var isTranslating = false
    var translationQueue: [QueuedTask] = []
    var error: String?
    
    var windowPinned = false
    
    init() {
        self.configStore = ConfigStore()
        self.vocabStore = VocabStore(path: configStore.config.vocabFile)
        self.translator = Translator(configStore: configStore)
        self.ocrEngine = OCREngine()
    }
    
    func translate(_ text: String, source: TranslationSource) {
        let task = QueuedTask(text: text, source: source)
        translationQueue.append(task)
        
        Task {
            await processQueue()
        }
    }
    
    func cancelCurrentTranslation() {
        Task {
            await translator.cancel()
            translationQueue.removeAll()
        }
    }
    
    private func processQueue() async {
        guard !isTranslating, let task = translationQueue.first else { return }
        
        isTranslating = true
        translationQueue.removeFirst()
        error = nil
        
        let startTime = Date()
        var sentences: [Sentence] = []
        
        do {
            sentences = try await translator.translateStream(text: task.text) { [weak self] sentence in
                Task { @MainActor in
                    guard let self = self else { return }
                    
                    if sentence.isPartial {
                        // Update current with partial
                        if self.currentTranslation == nil {
                            self.currentTranslation = TranslationResult(
                                timestamp: startTime,
                                sourceText: task.text,
                                sentences: [sentence],
                                source: task.source,
                                elapsedMs: 0
                            )
                        }
                    } else {
                        // Add complete sentence
                        if var current = self.currentTranslation {
                            var updated = current.sentences
                            // Replace partial if exists at same index
                            if let idx = updated.firstIndex(where: { $0.index == sentence.index && $0.isPartial }) {
                                updated[idx] = sentence
                            } else {
                                updated.append(sentence)
                            }
                            current = TranslationResult(
                                timestamp: current.timestamp,
                                sourceText: current.sourceText,
                                sentences: updated,
                                source: current.source,
                                elapsedMs: Int(Date().timeIntervalSince(startTime) * 1000)
                            )
                            self.currentTranslation = current
                        } else {
                            self.currentTranslation = TranslationResult(
                                timestamp: startTime,
                                sourceText: task.text,
                                sentences: [sentence],
                                source: task.source,
                                elapsedMs: Int(Date().timeIntervalSince(startTime) * 1000)
                            )
                        }
                    }
                }
            }
            
            let elapsed = Int(Date().timeIntervalSince(startTime) * 1000)
            let result = TranslationResult(
                timestamp: startTime,
                sourceText: task.text,
                sentences: sentences,
                source: task.source,
                elapsedMs: elapsed
            )
            
            currentTranslation = result
            translationHistory.insert(result, at: 0)
            
            // Keep only last 50
            if translationHistory.count > 50 {
                translationHistory = Array(translationHistory.prefix(50))
            }
            
        } catch {
            self.error = error.localizedDescription
        }
        
        isTranslating = false
        
        // Process next task
        if !translationQueue.isEmpty {
            await processQueue()
        }
    }
}

struct QueuedTask: Identifiable {
    let id = UUID()
    let text: String
    let source: TranslationSource
}
