import Foundation

/// 汉字在中日两种文字体系里的归属
enum HanOrigin {
    /// 只在简体中文里用（们、这、习、议、强、银、师…）。日语不用这些字
    case chineseOnly
    /// 只在日语里用，或是繁体字（経、団、広、県、響、機、電…）。简体中文不用这些字
    case japaneseOnly
    /// 中日通用（学、校、会、社、先、生…），本身不能说明是哪种语言
    case shared
    /// 两边的字符集都没有的生僻字
    case unknown
}

/// 文本的文字构成：假名、汉字（按归属细分）、拉丁字母各有多少
struct ScriptProfile {
    private(set) var kana = 0
    private(set) var han = 0
    private(set) var hanChineseOnly = 0
    private(set) var hanJapaneseOnly = 0
    private(set) var latinLetters = 0
    private(set) var latinWords = 0

    init(_ text: String) {
        var inWord = false
        for s in text.unicodeScalars {
            if LanguageDetector.isLatinLetter(s) {
                latinLetters += 1
                if !inWord { latinWords += 1; inWord = true }
                continue
            }
            inWord = false
            if LanguageDetector.isKana(s) {
                kana += 1
            } else if LanguageDetector.isCJKIdeograph(s) {
                han += 1
                switch LanguageDetector.hanOrigin(of: s) {
                case .chineseOnly: hanChineseOnly += 1
                case .japaneseOnly: hanJapaneseOnly += 1
                case .shared, .unknown: break
                }
            }
        }
    }
}

/// 第一层：只看文字构成就能确定的语言。
///
/// 中日共用汉字，但两边的字符集各有对方没有的字：简体中文字库（GB2312）里的「们 这 习」日语不用，
/// 日语字库（JIS）里的「経 団 広」简体中文不用。有这类字就能直接定论；
/// 全是通用字的汉字文本（如「学校」「寿司」）才是真正的歧义，交给 LanguageIdentifier。
enum LanguageDetector {
    enum Verdict: Equatable {
        case certain(Lang)
        /// 含汉字、没有决定性的文字证据
        case ambiguous
    }

    static func analyze(_ text: String) -> Verdict {
        let p = ScriptProfile(text)
        let cjk = p.han + p.kana
        if cjk == 0 { return .certain(p.latinLetters > 0 ? .en : .zh) }
        // 外文为主，夹少量中日文
        if p.latinWords > cjk || (p.latinWords == cjk && p.kana == 0) { return .certain(.en) }

        // 汉字证据一个字顶三个假名：日语文本假名多，中文里引用日语时假名少但一定带「们 这 说」之类
        let ja = p.hanJapaneseOnly * 3 + p.kana
        let zh = p.hanChineseOnly * 3
        if ja == 0 && zh == 0 { return .ambiguous }
        if ja > 2 * zh { return .certain(.ja) }
        if zh > 2 * ja { return .certain(.zh) }
        return .ambiguous
    }

    /// 只给出最佳猜测的同步判断（歧义时按中文）
    static func detect(_ text: String) -> Lang {
        if case .certain(let lang) = analyze(text) { return lang }
        return .zh
    }

    /// 文本是否可能需要在中文 / 日语之间切换：含汉字、没有假名
    static func isChineseOrJapaneseCandidate(_ text: String) -> Bool {
        let p = ScriptProfile(text)
        return p.han > 0 && p.kana == 0
    }

    // MARK: - 字符分类

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

    // MARK: - 汉字归属

    private static func encoding(_ e: CFStringEncodings) -> String.Encoding {
        String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(e.rawValue)))
    }
    /// GB2312：简体中文常用字库
    private static let simplifiedChineseSet = encoding(.EUC_CN)
    /// Shift_JIS（含 JIS X 0208 全部汉字和常见扩展）：日语字库
    private static let japaneseSet = String.Encoding.shiftJIS

    private static let originLock = NSLock()
    nonisolated(unsafe) private static var originCache: [UInt32: HanOrigin] = [:]

    static func hanOrigin(of s: Unicode.Scalar) -> HanOrigin {
        originLock.lock()
        defer { originLock.unlock() }
        if let hit = originCache[s.value] { return hit }
        let ch = String(s)
        let inChinese = ch.canBeConverted(to: simplifiedChineseSet)
        let inJapanese = ch.canBeConverted(to: japaneseSet)
        let origin: HanOrigin
        switch (inChinese, inJapanese) {
        case (true, true): origin = .shared
        case (true, false): origin = .chineseOnly
        case (false, true): origin = .japaneseOnly
        case (false, false):
            // 不在 GB2312 的生僻简体字（如「镕」）有对应的繁体字，转换后会变化；其他的无法判断
            origin = ch.applyingTransform(StringTransform("Hans-Hant"), reverse: false) != ch ? .chineseOnly : .unknown
        }
        originCache[s.value] = origin
        return origin
    }
}
