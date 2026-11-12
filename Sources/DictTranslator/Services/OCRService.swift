import AppKit
import Vision
import VisionKit

enum OCRService {
    /// 优先用系统「实况文本」（VisionKit）：能识别竖排日文（漫画、小说，Vision 的文字识别对竖排一个字都读不出），
    /// 并且自己会按段落合并折行、处理英文断词。不可用或没读到文字时退回 Vision
    static func recognizeText(in cgImage: CGImage) async throws -> String {
        if let text = await liveText(in: cgImage), !text.isEmpty { return text }
        return try await visionText(in: cgImage)
    }

    static func liveText(in cgImage: CGImage) async -> String? {
        guard ImageAnalyzer.isSupported else { return nil }
        var configuration = ImageAnalyzer.Configuration([.text])
        configuration.locales = ["ja-JP", "zh-Hans", "en-US"]
        guard let analysis = try? await ImageAnalyzer().analyze(cgImage, orientation: .up, configuration: configuration) else { return nil }
        return analysis.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func visionText(in cgImage: CGImage) async throws -> String {
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
        // Vision 坐标原点在左下。先从上到下排，再把纵向重叠的归为同一行、行内从左到右
        // （直接用「差不多高就比左右」做排序比较不满足传递性，多栏文字时顺序会乱）
        var rows: [[(text: String, box: CGRect)]] = []
        for line in lines.sorted(by: { $0.box.midY > $1.box.midY }) {
            if let last = rows.last?.first,
               abs(last.box.midY - line.box.midY) < min(last.box.height, line.box.height) * 0.5 {
                rows[rows.count - 1].append(line)
            } else {
                rows.append([line])
            }
        }
        let sorted = rows.flatMap { $0.sorted { $0.box.minX < $1.box.minX } }
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
