import Foundation

/// Bing 翻译网页接口（ttranslatev3）。先从 bing.com/translator 页面取 IG / IID / token，有效期约 1 小时
@MainActor
enum BingTranslateService {
    private struct Credentials {
        /// 国内访问 www.bing.com 可能被重定向到 cn.bing.com，token 与域名配套
        var host: String
        var ig: String
        var iid: String
        var key: String
        var token: String
        var expires: Date
    }
    private static var credentials: Credentials?
    /// 中、日两个译文同时开始查询时共用同一次取 token
    private static var pendingCredentials: Task<Credentials, Error>?

    /// 网页接口单次最多 1000 字符
    private nonisolated static let maxChunk = 1000

    /// 网页 cookie 要和 token 配套，用独立 session 保存
    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 15
        config.httpCookieStorage = HTTPCookieStorage()
        return URLSession(configuration: config)
    }()

    static func translate(_ text: String, from: Lang, to: Lang) async throws -> String {
        var joined = ""
        for (i, chunk) in chunks(of: text).enumerated() {
            try Task.checkCancellation()
            let translated = try await translateChunk(chunk.text, from: from, to: to)
            if i > 0 { joined += chunk.startsLine ? "\n" : (to == .en ? " " : "") }
            joined += translated
        }
        // Bing 会在换行前留下多余的空格
        let result = joined
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else { throw TranslatorError.empty }
        return result
    }

    private static func translateChunk(_ text: String, from: Lang, to: Lang) async throws -> String {
        do {
            return try await request(text, from: from, to: to, credentials: try await currentCredentials())
        } catch let error as TranslatorError {
            // token 过期或失效时页面会返回空结果 / 错误码，重新取一次
            credentials = nil
            guard case .badResponse = error else { throw error }
            return try await request(text, from: from, to: to, credentials: try await currentCredentials())
        }
    }

    /// 按段落拼成不超过上限的片段；单个段落过长时再按句子切，仍过长就硬切
    nonisolated static func chunks(of text: String, limit: Int = maxChunk) -> [(text: String, startsLine: Bool)] {
        guard text.count > limit else { return [(text, true)] }
        // startsLine：片段是否从新的一行开始（同一段落切出来的句子之间不加换行）
        var pieces: [(text: String, startsLine: Bool)] = []
        for line in text.components(separatedBy: "\n") {
            if line.count <= limit { pieces.append((line, true)); continue }
            var sentence = ""
            var first = true
            for ch in line {
                sentence.append(ch)
                if "。．.!?！？".contains(ch) || sentence.count >= limit {
                    pieces.append((sentence, first)); sentence = ""; first = false
                }
            }
            if !sentence.isEmpty { pieces.append((sentence, first)) }
        }
        // 相邻片段能合并就合并，减少请求数；原来的换行保留在片段内
        var out: [(text: String, startsLine: Bool)] = []
        for piece in pieces {
            let separator = piece.startsLine ? "\n" : ""
            if let last = out.last, last.text.count + separator.count + piece.text.count <= limit {
                out[out.count - 1].text += separator + piece.text
            } else {
                out.append(piece)
            }
        }
        return out.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private static func currentCredentials() async throws -> Credentials {
        if let c = credentials, Date() < c.expires { return c }
        if let pending = pendingCredentials { return try await pending.value }
        let task = Task { try await fetchCredentials() }
        pendingCredentials = task
        defer { pendingCredentials = nil }
        let c = try await task.value
        credentials = c
        return c
    }

    private static func fetchCredentials() async throws -> Credentials {
        let (data, resp) = try await fetch(URLRequest(url: URL(string: "https://www.bing.com/translator")!))
        guard let html = String(data: data, encoding: .utf8),
              let ig = firstMatch(#"IG:"([0-9A-Fa-f]+)""#, in: html),
              let iid = firstMatch(#"data-iid="(translator\.[0-9]+)""#, in: html),
              let helper = firstMatch(#"params_AbusePreventionHelper\s*=\s*\[([^\]]+)\]"#, in: html)
        else { throw TranslatorError.badResponse }
        // [key, "token", 有效期毫秒]
        let parts = helper.split(separator: ",").map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "\" ")) }
        guard parts.count >= 2 else { throw TranslatorError.badResponse }
        let ttl = parts.count >= 3 ? (Double(parts[2]) ?? 3_600_000) / 1000 : 3600
        return Credentials(host: resp.url?.host ?? "www.bing.com", ig: ig, iid: iid, key: parts[0], token: parts[1],
                           expires: Date().addingTimeInterval(max(60, ttl - 120)))
    }

    private static func request(_ text: String, from: Lang, to: Lang, credentials c: Credentials) async throws -> String {
        guard let url = HTTP.url("https://\(c.host)/ttranslatev3", query: ["isVertical": "1", "IG": c.ig, "IID": c.iid]) else {
            throw TranslatorError.badResponse
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.setValue("https://\(c.host)/translator", forHTTPHeaderField: "Referer")
        let form: KeyValuePairs<String, String> = [
            "fromLang": from.bingCode, "to": to.bingCode, "text": text, "token": c.token, "key": c.key,
        ]
        req.httpBody = form.map { "\($0.key)=\(HTTP.encodeQueryValue($0.value))" }.joined(separator: "&").data(using: .utf8)

        let (data, _) = try await fetch(req)
        guard let obj = try? JSONSerialization.jsonObject(with: data) else { throw TranslatorError.badResponse }
        let root = JSONValue(obj)
        guard let result = root.array.first?["translations"].array.first?["text"].string else {
            throw TranslatorError.badResponse
        }
        return result
    }

    private static func fetch(_ request: URLRequest) async throws -> (Data, URLResponse) {
        var req = request
        req.setValue(HTTP.userAgent, forHTTPHeaderField: "User-Agent")
        let (data, resp) = try await session.data(for: req)
        if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw TranslatorError.http(http.statusCode)
        }
        return (data, resp)
    }

    private static func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let r = Range(m.range(at: 1), in: text) else { return nil }
        return String(text[r])
    }
}
