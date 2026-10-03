import Foundation

enum QueryClassifier {
    /// 是否按「词条」处理（查辞典），否则按句子翻译
    static func isWordLike(_ text: String, lang: Lang) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !t.contains("\n") else { return false }
        switch lang {
        case .en:
            let sentenceEnd = CharacterSet(charactersIn: ".!?;:,\"()[]{}")
            if t.unicodeScalars.contains(where: { sentenceEnd.contains($0) }) {
                // 允许缩写里的点，如 "e.g." 这类极少见，统一按句子处理
                return false
            }
            let words = t.split(whereSeparator: { $0 == " " || $0 == "\t" })
            return words.count <= 3 && t.count <= 40
        case .ja, .zh:
            let punct = CharacterSet(charactersIn: "。、！？，．,.!?；;：:「」『』（）()…")
            if t.unicodeScalars.contains(where: { punct.contains($0) }) { return false }
            if t.contains(" ") || t.contains("　") { return false }
            return t.count <= 10
        }
    }

    static func normalize(_ text: String) -> String {
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // 合并 OCR / PDF 中断行产生的多余空白
        t = t.replacingOccurrences(of: "\r\n", with: "\n")
        while t.contains("\n\n\n") { t = t.replacingOccurrences(of: "\n\n\n", with: "\n\n") }
        return t
    }
}
