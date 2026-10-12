import Foundation

/// Google 翻译免费网页接口（translate_a/single, client=gtx），只用于中日语言识别
@MainActor
enum GoogleTranslateService {
    /// 被限流（429 / 人机验证）或连不上（超时等）后暂停使用一段时间，避免每次都等它失败
    private static var blockedUntil = Date.distantPast

    static var isBlocked: Bool { Date() < blockedUntil }

    /// 让 Google 自动识别源语言，返回 zh / ja / en；其他语言返回 nil
    static func detect(_ text: String) async throws -> Lang? {
        let root: JSONValue
        do {
            root = try await request(text)
        } catch {
            noteFailure(error)
            throw error
        }
        switch root["src"].string?.lowercased() {
        case "zh", "zh-cn", "zh-tw", "zh-hans", "zh-hant": return .zh
        case "ja": return .ja
        case "en": return .en
        default: return nil
        }
    }

    private static func request(_ text: String) async throws -> JSONValue {
        var comps = URLComponents(string: "https://translate.googleapis.com/translate_a/single")!
        comps.queryItems = [
            URLQueryItem(name: "client", value: "gtx"),
            URLQueryItem(name: "sl", value: "auto"),
            URLQueryItem(name: "tl", value: "en"),
            URLQueryItem(name: "dt", value: "t"),
            URLQueryItem(name: "dj", value: "1"),
            URLQueryItem(name: "ie", value: "UTF-8"),
            URLQueryItem(name: "oe", value: "UTF-8"),
        ]
        var req = URLRequest(url: comps.url!)
        req.httpMethod = "POST"
        req.setValue(HTTP.userAgent, forHTTPHeaderField: "User-Agent")
        req.setValue("application/x-www-form-urlencoded;charset=UTF-8", forHTTPHeaderField: "Content-Type")
        req.httpBody = ("q=" + HTTP.encodeQueryValue(text)).data(using: .utf8)

        let (data, resp) = try await HTTP.detectSession.data(for: req)
        if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw TranslatorError.http(http.statusCode)
        }
        guard let obj = try? JSONSerialization.jsonObject(with: data) else { throw TranslatorError.badResponse }
        return JSONValue(obj)
    }

    private static func noteFailure(_ error: Error) {
        if isRateLimited(error) {
            blockedUntil = Date().addingTimeInterval(600)
        } else if isUnreachable(error) {
            blockedUntil = Date().addingTimeInterval(120)
        }
    }

    private static func isUnreachable(_ error: Error) -> Bool {
        let ns = error as NSError
        guard ns.domain == NSURLErrorDomain else { return false }
        return [NSURLErrorTimedOut, NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost,
                NSURLErrorNetworkConnectionLost].contains(ns.code)
    }

    private static func isRateLimited(_ error: Error) -> Bool {
        if case TranslatorError.http(let code) = error, code == 429 || code == 403 || code == 503 { return true }
        if case TranslatorError.badResponse = error { return true }   // 被重定向到人机验证页面
        return false
    }
}
