import Foundation

/// Google 翻译免费网页接口（translate_a/single, client=gtx）
enum GoogleTranslateService {
    static func translate(_ text: String, from: Lang?, to: Lang) async throws -> String {
        let root = try await request(text, from: from, to: to)
        let sentences = root["sentences"].array
        let result = sentences.compactMap { $0["trans"].string }.joined()
        guard !result.isEmpty else { throw TranslatorError.empty }
        return result
    }

    /// 识别文本语言（sl=auto 时返回的 src 字段）；不是中、日、英时返回 nil
    static func detect(_ text: String) async throws -> Lang? {
        let root = try await request(text, from: nil, to: .en, timeout: 3)
        guard let src = root["src"].string?.lowercased() else { throw TranslatorError.badResponse }
        if src.hasPrefix("zh") { return .zh }
        if src == "ja" { return .ja }
        if src == "en" { return .en }
        return nil
    }

    private static func request(_ text: String, from: Lang?, to: Lang, timeout: TimeInterval? = nil) async throws -> JSONValue {
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
        if let timeout { req.timeoutInterval = timeout }
        req.httpMethod = "POST"
        req.setValue(HTTP.userAgent, forHTTPHeaderField: "User-Agent")
        req.setValue("application/x-www-form-urlencoded;charset=UTF-8", forHTTPHeaderField: "Content-Type")
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        req.httpBody = ("q=" + (text.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")).data(using: .utf8)

        let (data, resp) = try await HTTP.session.data(for: req)
        if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw TranslatorError.http(http.statusCode)
        }
        guard let obj = try? JSONSerialization.jsonObject(with: data) else { throw TranslatorError.badResponse }
        return JSONValue(obj)
    }
}
