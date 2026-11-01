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

    /// 合并排版折行：从 PDF、网页复制的文字句子中间常有换行，翻译服务会把半句话当成一句来译。
    /// 只合并「够长（接近最长行）、不以句末标点结尾、下一行不是列表项」的行；正好写满一行的（排版折行）以句号结尾也合并。
    /// 空行（分段）、标题、列表保留
    static func joinSoftWraps(_ text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        guard lines.count > 1 else { return text }
        let longest = lines.map(\.count).max() ?? 0
        let wrapWidth = max(10, Int(Double(longest) * 0.6))
        let fullWidth = max(10, Int(Double(longest) * 0.9))
        // 列表通常不止一项；只有一行以「・」开头时才可能是被折断的人名
        let dotLines = lines.filter { $0.hasPrefix("・") || $0.hasPrefix("·") }.count
        var out = lines[0]
        for i in 1..<lines.count {
            let prev = lines[i - 1].trimmingCharacters(in: .whitespaces)
            let next = lines[i].trimmingCharacters(in: .whitespaces)
            guard !prev.isEmpty, !next.isEmpty, prev.count >= wrapWidth,
                  let last = prev.unicodeScalars.last, let first = next.unicodeScalars.first,
                  !sentenceEnd.contains(last) || prev.count >= fullWidth,
                  next.range(of: listItem, options: .regularExpression) == nil
                    // 写满的行后面以「・」开头：是被折断的人名（エド・デイビー），不是列表
                    || (dotLines == 1 && prev.count >= fullWidth && !sentenceEnd.contains(last) && (next.hasPrefix("・") || next.hasPrefix("·"))) else {
                out += "\n" + lines[i]
                continue
            }
            out = out.trimmingCharacters(in: .whitespaces)
            let latinBefore = last.isASCII && !CharacterSet.whitespaces.contains(last)
            if last == "-", out.unicodeScalars.dropLast().last.map(LanguageDetector.isLatinLetter) == true,
               CharacterSet.lowercaseLetters.contains(first) {
                out.removeLast()   // 英文断词连字符：inter-␤national
                out += next
            } else {
                out += (latinBefore && first.isASCII ? " " : "") + next
            }
        }
        return out
    }

    private static let sentenceEnd = CharacterSet(charactersIn: "。！？!?．.…：:;；」』）)】〕\"”’")
    private static let listItem = #"^([-–•・●○■□◆▪*·※]|\d{1,2}[.)、．]|[①-⑳]|[(（]\d{1,2}[)）]|[a-zA-Z][.)]\s)"#

    static func normalize(_ text: String) -> String {
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // 合并 OCR / PDF 中断行产生的多余空白
        t = t.replacingOccurrences(of: "\r\n", with: "\n")
        while t.contains("\n\n\n") { t = t.replacingOccurrences(of: "\n\n\n", with: "\n\n") }
        return t
    }
}
