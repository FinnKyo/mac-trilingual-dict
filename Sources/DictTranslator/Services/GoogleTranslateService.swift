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
        let url = HTTP.url("https://translate.googleapis.com/translate_a/single", query: [
            "client": "gtx", "sl": "auto", "tl": "en", "dt": "t", "dj": "1", "ie": "UTF-8", "oe": "UTF-8",
        ])!
        return try await HTTP.json(HTTP.postForm(url, ["q": text]), session: HTTP.detectSession)
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
