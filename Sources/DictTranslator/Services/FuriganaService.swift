import Foundation

/// 用系统自带的日语分词器（CFStringTokenizer）为日文文本生成假名注音
enum FuriganaService {
    static func tokens(for text: String) -> [RubyToken] {
        guard !text.isEmpty else { return [] }
        let cfText = text as CFString
        let fullRange = CFRange(location: 0, length: CFStringGetLength(cfText))
        guard let tokenizer = CFStringTokenizerCreate(
            kCFAllocatorDefault, cfText, fullRange,
            kCFStringTokenizerUnitWordBoundary, Locale(identifier: "ja") as CFLocale
        ) else {
            return [RubyToken(surface: text, reading: nil)]
        }

        let ns = text as NSString
        var result: [RubyToken] = []
        var cursor = 0

        while true {
            let type = CFStringTokenizerAdvanceToNextToken(tokenizer)
            if type.isEmpty { break }
            let range = CFStringTokenizerGetCurrentTokenRange(tokenizer)
            guard range.location != kCFNotFound, range.length > 0 else { continue }
            if range.location > cursor {
                result.append(RubyToken(surface: ns.substring(with: NSRange(location: cursor, length: range.location - cursor)), reading: nil))
            }
            let surface = ns.substring(with: NSRange(location: range.location, length: range.length))
            cursor = range.location + range.length

            guard containsKanji(surface),
                  let latin = CFStringTokenizerCopyCurrentTokenAttribute(tokenizer, kCFStringTokenizerAttributeLatinTranscription) as? String,
                  let hira = latinToHiragana(latin)
            else {
                result.append(RubyToken(surface: surface, reading: nil))
                continue
            }
            result.append(contentsOf: splitOkurigana(surface: surface, reading: hira))
        }
        if cursor < ns.length {
            result.append(RubyToken(surface: ns.substring(from: cursor), reading: nil))
        }
        return merge(result)
    }

    static func containsKanji(_ s: String) -> Bool {
        s.unicodeScalars.contains(where: LanguageDetector.isCJKIdeograph)
    }

    static func latinToHiragana(_ latin: String) -> String? {
        let m = NSMutableString(string: latin) as CFMutableString
        guard CFStringTransform(m, nil, kCFStringTransformLatinHiragana, false) else { return nil }
        let s = m as String
        // 转换失败时会残留拉丁字母，此时不显示注音
        if s.unicodeScalars.contains(where: { LanguageDetector.isLatinLetter($0) }) { return nil }
        return s
    }

    /// 把「食べる/たべる」拆成「食(た)」+「べる」，让注音只标在汉字上
    static func splitOkurigana(surface: String, reading: String) -> [RubyToken] {
        let toHira: (String) -> String = { s in
            (s.applyingTransform(.hiraganaToKatakana, reverse: true)) ?? s
        }
        let sChars = Array(surface)
        var rChars = Array(reading)
        let sHira = sChars.map { toHira(String($0)) }

        // 公共前缀（假名开头，如「お茶」）
        var prefix = 0
        while prefix < sChars.count, prefix < rChars.count,
              !containsKanji(String(sChars[prefix])),
              sHira[prefix] == String(rChars[prefix]) {
            prefix += 1
        }
        // 公共后缀（送假名）
        var suffix = 0
        while suffix < sChars.count - prefix, suffix < rChars.count - prefix,
              !containsKanji(String(sChars[sChars.count - 1 - suffix])),
              sHira[sChars.count - 1 - suffix] == String(rChars[rChars.count - 1 - suffix]) {
            suffix += 1
        }
        var out: [RubyToken] = []
        if prefix > 0 { out.append(RubyToken(surface: String(sChars[0..<prefix]), reading: nil)) }
        let coreSurface = String(sChars[prefix..<(sChars.count - suffix)])
        rChars = Array(rChars[prefix..<(rChars.count - suffix)])
        let coreReading = String(rChars)
        if !coreSurface.isEmpty {
            out.append(RubyToken(surface: coreSurface,
                                 reading: (coreReading.isEmpty || coreReading == coreSurface) ? nil : coreReading))
        }
        if suffix > 0 { out.append(RubyToken(surface: String(sChars[(sChars.count - suffix)...]), reading: nil)) }
        return out
    }

    /// 合并相邻的无注音片段，减少视图数量
    private static func merge(_ tokens: [RubyToken]) -> [RubyToken] {
        var out: [RubyToken] = []
        for t in tokens {
            if t.reading == nil, let last = out.last, last.reading == nil {
                out[out.count - 1].surface += t.surface
            } else {
                out.append(t)
            }
        }
        return out
    }
}
