import AppKit
import Vision

enum OCRService {
    static func recognizeText(in cgImage: CGImage) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.automaticallyDetectsLanguage = true
            request.recognitionLanguages = ["zh-Hans", "ja-JP", "en-US"]
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            try handler.perform([request])
            return joinLines(request.results ?? [])
        }.value
    }

    /// 按从上到下的行顺序拼接；中日文行之间不加空格，英文行之间加空格（同一段落）
    private static func joinLines(_ observations: [VNRecognizedTextObservation]) -> String {
        let lines: [(text: String, box: CGRect)] = observations.compactMap { obs in
            guard let s = obs.topCandidates(1).first?.string else { return nil }
            return (s, obs.boundingBox)
        }
        // Vision 坐标原点在左下
        let sorted = lines.sorted { a, b in
            if abs(a.box.midY - b.box.midY) < min(a.box.height, b.box.height) * 0.5 {
                return a.box.minX < b.box.minX
            }
            return a.box.midY > b.box.midY
        }
        var result = ""
        var previous: (text: String, box: CGRect)?
        for line in sorted {
            defer { previous = line }
            guard let prev = previous else { result = line.text; continue }
            let sameRow = abs(prev.box.midY - line.box.midY) < min(prev.box.height, line.box.height) * 0.5
            let gap = prev.box.minY - line.box.maxY
            let paragraphBreak = !sameRow && gap > prev.box.height * 0.8
            if paragraphBreak {
                result += "\n" + line.text
            } else {
                let lastChar = result.unicodeScalars.last
                let firstChar = line.text.unicodeScalars.first
                let needsSpace = (lastChar.map(LanguageDetector.isLatinLetter) ?? false)
                    || (firstChar.map(LanguageDetector.isLatinLetter) ?? false)
                    || (lastChar.map { CharacterSet.punctuationCharacters.contains($0) && $0.isASCII } ?? false)
                if result.hasSuffix("-"), !sameRow {
                    result.removeLast()   // 英文断词连字符
                    result += line.text
                } else {
                    result += (needsSpace ? " " : "") + line.text
                }
            }
        }
        return result
    }
}
