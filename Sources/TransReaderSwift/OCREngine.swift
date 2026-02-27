import Foundation
import Vision
import CoreImage
import AppKit

actor OCREngine {
    func recognizeText(from imagePath: String) async throws -> String {
        let url = URL(fileURLWithPath: imagePath)
        
        guard let ciImage = CIImage(contentsOf: url) else {
            throw NSError(domain: "OCREngine", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "无法加载图片"
            ])
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: "")
                    return
                }
                
                let lines = self.extractLines(from: observations)
                let result = self.joinLines(lines)
                continuation.resume(returning: result)
            }
            
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["en"]
            
            let handler = VNImageRequestHandler(ciImage: ciImage, options: [:])
            
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
    
    private func extractLines(from observations: [VNRecognizedTextObservation]) -> [(topY: Double, leftX: Double, text: String)] {
        var lines: [(topY: Double, leftX: Double, text: String)] = []
        
        for obs in observations {
            guard let candidate = obs.topCandidates(1).first else { continue }
            let text = candidate.string
            let bbox = obs.boundingBox
            
            // Vision coordinates: origin bottom-left, y goes up
            // Sort by: top-to-bottom (descending y of top edge), then left-to-right
            let topY = bbox.origin.y + bbox.size.height
            let leftX = bbox.origin.x
            
            lines.append((topY: -topY, leftX: leftX, text: text))
        }
        
        lines.sort { lhs, rhs in
            if abs(lhs.topY - rhs.topY) < 0.01 {
                return lhs.leftX < rhs.leftX
            }
            return lhs.topY < rhs.topY
        }
        
        return lines
    }
    
    private func joinLines(_ lines: [(topY: Double, leftX: Double, text: String)]) -> String {
        guard !lines.isEmpty else { return "" }
        
        var merged: [String] = []
        var carry = ""
        
        for line in lines {
            var text = line.text.trimmingCharacters(in: .whitespaces)
            if text.isEmpty { continue }
            
            // Previous line ended with hyphen → merge
            if !carry.isEmpty {
                if text.first?.isLowercase == true {
                    text = carry + text
                } else {
                    text = carry + "-" + text
                }
                carry = ""
            }
            
            // Current line ends with hyphen (but not double hyphen --)
            if text.hasSuffix("-") && !text.hasSuffix("--") {
                carry = String(text.dropLast())
            } else {
                merged.append(text)
            }
        }
        
        if !carry.isEmpty {
            merged.append(carry)
        }
        
        return merged.joined(separator: "\n")
    }
    
    func captureScreen() async throws -> String {
        let tempFile = NSTemporaryDirectory() + UUID().uuidString + ".png"
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-i", "-x", "-s", tempFile]
        
        try process.run()
        process.waitUntilExit()
        
        guard process.terminationStatus == 0,
              FileManager.default.fileExists(atPath: tempFile),
              (try? FileManager.default.attributesOfItem(atPath: tempFile))?[.size] as? UInt64 ?? 0 > 0 else {
            try? FileManager.default.removeItem(atPath: tempFile)
            throw NSError(domain: "OCREngine", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "截图取消或失败"
            ])
        }
        
        defer {
            try? FileManager.default.removeItem(atPath: tempFile)
        }
        
        return try await recognizeText(from: tempFile)
    }
}
