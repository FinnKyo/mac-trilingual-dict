import Foundation

/// Google 翻译免费网页接口（translate_a/single, client=gtx）
enum GoogleTranslateService {
    static func translate(_ text: String, from: Lang?, to: Lang) async throws -> String {
        let root = try await request(text, from: from, to: to, session: HTTP.session)
        let result = root["sentences"].array.compactMap { $0["trans"].string }.joined()
        guard !result.isEmpty else { throw TranslatorError.empty }
        return result
    }

    /// 让 Google 自动识别源语言，返回 zh / ja / en；其他语言返回 nil
    static func detect(_ text: String) async throws -> Lang? {
        let root = try await request(text, from: nil, to: .en, session: HTTP.detectSession)
        switch root["src"].string?.lowercased() {
        case "zh", "zh-cn", "zh-tw", "zh-hans", "zh-hant": return .zh
        case "ja": return .ja
        case "en": return .en
        default: return nil
        }
    }

    private static func request(_ text: String, from: Lang?, to: Lang, session: URLSession) async throws -> JSONValue {
        var comps = URLComponents(string: "https://translate.googleapis.com/translate_a/single")!
        comps.queryItems = [
            URLQueryItem(name: "client", value: "gtx"),
            URLQueryItem(name: "sl", value: from?.googleCode ?? "auto"),
            URLQueryItem(name: "tl", value: to.googleCode),
            URLQueryItem(name: "dt", value: "t"),
            URLQueryItem(name: "dj", value: "1"),
            URLQueryItem(name: "ie", value: "UTF-8"),
            URLQueryItem(name: "oe", value: "UTF-8"),
        ]
        // 长文本用 POST，避免 URL 过长
        var req = URLRequest(url: comps.url!)
        req.httpMethod = "POST"
        req.setValue(HTTP.userAgent, forHTTPHeaderField: "User-Agent")
        req.setValue("application/x-www-form-urlencoded;charset=UTF-8", forHTTPHeaderField: "Content-Type")
        req.httpBody = ("q=" + HTTP.encodeQueryValue(text)).data(using: .utf8)

        let (data, resp) = try await session.data(for: req)
        if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw TranslatorError.http(http.statusCode)
        }
        guard let obj = try? JSONSerialization.jsonObject(with: data) else { throw TranslatorError.badResponse }
        return JSONValue(obj)
    }
}
