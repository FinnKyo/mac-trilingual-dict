import Foundation

/// Weblio 辞書网页上的《デジタル大辞泉》（小学館）：详细的日文释义（国语辞典）
enum WeblioService {
    private final class Box { let value: KokugoEntry?; init(_ v: KokugoEntry?) { value = v } }
    private static let cache = NSCache<NSString, Box>()

    /// 查不到（或页面里没有大辞泉的条目）时返回 nil
    static func daijisen(_ word: String) async throws -> KokugoEntry? {
        if let hit = cache.object(forKey: word as NSString) { return hit.value }
        guard let url = URL(string: "https://www.weblio.jp/content/" + HTTP.encodeQueryValue(word)) else { return nil }
        let entry: KokugoEntry?
        do {
            let data = try await HTTP.get(url, referer: "https://www.weblio.jp/")
            entry = parseDaijisen(String(decoding: data, as: UTF8.self), word: word)
        } catch TranslatorError.http(404) {
            entry = nil   // 没有这个词
        }
        cache.setObject(Box(entry), forKey: word as NSString)
        return entry
    }

    /// 页面里每个辞典的条目是「<h2 class=midashigo title="掛ける">か・ける【掛ける／懸ける】</h2><div class=Sgkdj>…</div>」，
    /// Sgkdj 即大辞泉。同音词（掛ける、欠ける、駆ける…）各有一条，优先取词头一致的
    static func parseDaijisen(_ html: String, word: String) -> KokugoEntry? {
        // 标题内容不能跨过 </h2>：页面里排在前面的是其他辞典的条目（实用日本語表現辞典等），
        // 否则会从它们的标题一路匹配到大辞泉，把中间的导航、广告脚本都当成标题
        let pattern = #"<h2 class=midashigo title="([^"]*)">((?:(?!</h2>).)*)</h2>\s*<div class=Sgkdj>"#
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { return nil }
        let ns = html as NSString
        let matches = re.matches(in: html, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return nil }
        let chosen = matches.first { ns.substring(with: $0.range(at: 1)) == word } ?? matches[0]

        let heading = ns.substring(with: chosen.range(at: 2)).strippingHTML.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = blockContent(ns, from: chosen.range.location + chosen.range.length)
        let lines = paragraphs(body)
        return lines.isEmpty ? nil : KokugoEntry(heading: heading, lines: lines)
    }

    /// 从 <div class=Sgkdj> 之后取到与之配对的 </div>（中间可能嵌套 div）
    private static func blockContent(_ ns: NSString, from start: Int) -> String {
        let rest = ns.substring(from: start)
        var depth = 1
        var index = rest.startIndex
        while let r = rest.range(of: #"</?div\b"#, options: .regularExpression, range: index..<rest.endIndex) {
            depth += rest[r].hasPrefix("</") ? -1 : 1
            if depth == 0 { return String(rest[..<r.lowerBound]) }
            index = r.upperBound
        }
        return rest
    }

    /// 段落转成文本行。「１」「２」这类单独成段的义项编号并到下一行；读音行（読み方：…）不要
    private static func paragraphs(_ body: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: #"<p[^>]*>(.*?)</p>"#, options: [.dotMatchesLineSeparators]) else { return [] }
        let ns = body as NSString
        var lines: [String] = []
        var pendingNumber: String?
        for m in re.matches(in: body, range: NSRange(location: 0, length: ns.length)) {
            let text = decodeEntities(ns.substring(with: m.range(at: 1)).strippingHTML)
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, !text.hasPrefix("読み方：") else { continue }
            if text.count <= 3, text.allSatisfy({ $0.isNumber }) {
                pendingNumber = text
                continue
            }
            if let n = pendingNumber {
                lines.append("\(n) \(text)")
                pendingNumber = nil
            } else {
                lines.append(text)
            }
        }
        return lines
    }

    private static func decodeEntities(_ s: String) -> String {
        guard s.contains("&#") else { return s }
        var out = s
        let re = try? NSRegularExpression(pattern: #"&#(x?)([0-9a-fA-F]+);"#)
        for m in (re?.matches(in: s, range: NSRange(location: 0, length: (s as NSString).length)) ?? []).reversed() {
            let ns = out as NSString
            let hex = ns.substring(with: m.range(at: 1)) == "x"
            guard let v = UInt32(ns.substring(with: m.range(at: 2)), radix: hex ? 16 : 10), let u = Unicode.Scalar(v) else { continue }
            out = ns.replacingCharacters(in: m.range, with: String(u))
        }
        return out
    }
}
