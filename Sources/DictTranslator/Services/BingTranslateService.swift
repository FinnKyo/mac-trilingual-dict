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

    /// 网页 cookie 要和 token 配套，用独立 session 保存
    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 15
        config.httpCookieStorage = HTTPCookieStorage()
        return URLSession(configuration: config)
    }()

    /// 网页接口单次最多 1000 字符，长文由 MachineTranslator 先切好段
    static func translate(_ text: String, from: Lang, to: Lang) async throws -> String {
        do {
            return try await request(text, from: from, to: to, credentials: try await currentCredentials())
        } catch let error as TranslatorError {
            // token 过期或失效时页面会返回空结果 / 错误码，重新取一次
            credentials = nil
            guard case .badResponse = error else { throw error }
            return try await request(text, from: from, to: to, credentials: try await currentCredentials())
        }
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
        let (data, resp) = try await HTTP.send(URLRequest(url: URL(string: "https://www.bing.com/translator")!), session: session)
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
        var req = HTTP.postForm(url, ["fromLang": from.bingCode, "to": to.bingCode, "text": text, "token": c.token, "key": c.key])
        req.setValue("https://\(c.host)/translator", forHTTPHeaderField: "Referer")
        let root = try await HTTP.json(req, session: session)
        guard let result = root.array.first?["translations"].array.first?["text"].string else {
            throw TranslatorError.badResponse
        }
        return result
    }

    private static func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let r = Range(m.range(at: 1), in: text) else { return nil }
        return String(text[r])
    }
}
