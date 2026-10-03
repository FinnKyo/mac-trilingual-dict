import Foundation

enum LanguageDetector {
    static func isKana(_ s: Unicode.Scalar) -> Bool {
        switch s.value {
        case 0x3040...0x309F,   // 平假名
             0x30A0...0x30FF,   // 片假名
             0x31F0...0x31FF,   // 片假名扩展
             0xFF66...0xFF9F:   // 半角片假名
            return true
        default:
            return false
        }
    }

    static func isCJKIdeograph(_ s: Unicode.Scalar) -> Bool {
        switch s.value {
        case 0x4E00...0x9FFF, 0x3400...0x4DBF, 0x20000...0x2A6DF, 0xF900...0xFAFF:
            return true
        default:
            return false
        }
    }

    static func isLatinLetter(_ s: Unicode.Scalar) -> Bool {
        switch s.value {
        case 0x41...0x5A, 0x61...0x7A, 0xC0...0xD6, 0xD8...0xF6, 0xF8...0x24F:
            return true
        default:
            return false
        }
    }

    /// 没有假名、以汉字为主（可夹少量字母数字，如「全日本空手道連盟（JKJO）」）：
    /// 中文和日语的写法可能一样，需要借助识别服务判断
    static func isAmbiguousChineseJapanese(_ text: String) -> Bool {
        var hasHan = false
        for s in text.unicodeScalars {
            if isKana(s) { return false }
            if isCJKIdeograph(s) { hasHan = true }
        }
        return hasHan && detect(text) == .zh
    }

    private static let eucCN = String.Encoding(
        rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.EUC_CN.rawValue)))

    /// 含有简体中文字库（GB2312）以外的汉字，即繁体字或日语新字体（経、団、響、機…）。
    /// 本 App 只面向简体中文用户，这类字符可以直接当作日语的证据。
    /// 生僻简体字（如「镕」）也不在 GB2312 里，但它们有对应的繁体，转换后会变化，不算
    static func hasNonSimplifiedHan(_ text: String) -> Bool {
        var seen = Set<Unicode.Scalar>()
        for s in text.unicodeScalars where isCJKIdeograph(s) && seen.insert(s).inserted {
            let ch = String(s)
            if ch.canBeConverted(to: eucCN) { continue }
            if ch.applyingTransform(StringTransform("Hans-Hant"), reverse: false) == ch { return true }
        }
        return false
    }

    /// 含假名且占比不太低 → 日语；拉丁字母占多数 → 英语；其余（纯汉字）→ 中文。
    /// 纯汉字文本里中日写法相同，这里一律给 .zh，真正的中 / 日判断见 LanguageIdentifier
    static func detect(_ text: String) -> Lang {
        var kana = 0, cjk = 0, latin = 0
        for s in text.unicodeScalars {
            if isKana(s) { kana += 1 }
            else if isCJKIdeograph(s) { cjk += 1 }
            else if isLatinLetter(s) { latin += 1 }
        }
        // 英文单词数（按单词算，避免长单词把英文占比算高）
        let latinWords = latin == 0 ? 0 : text.split(whereSeparator: { !$0.unicodeScalars.allSatisfy(isLatinLetter) }).count
        // 中文文本里偶尔夹一个「の」之类的，按比例判断；外文里夹少量日文则看谁占多数
        if kana > 0, kana * 10 >= cjk, latinWords <= kana + cjk { return .ja }
        if cjk == 0 { return latin > 0 ? .en : .zh }
        return latinWords >= cjk ? .en : .zh
    }
}
