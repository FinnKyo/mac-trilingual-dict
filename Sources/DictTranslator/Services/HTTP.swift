import Foundation

enum HTTP {
    static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 15
        config.requestCachePolicy = .useProtocolCachePolicy
        config.urlCache = URLCache(memoryCapacity: 8 * 1024 * 1024, diskCapacity: 0)
        return URLSession(configuration: config)
    }()

    /// 语言检测是查询的前置步骤，超时要短，失败就换下一个服务
    static let detectSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 3
        config.timeoutIntervalForResource = 4
        return URLSession(configuration: config)
    }()

    static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

    static func get(_ url: URL, referer: String? = nil) async throws -> Data {
        var req = URLRequest(url: url)
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        if let referer { req.setValue(referer, forHTTPHeaderField: "Referer") }
        let (data, resp) = try await session.data(for: req)
        if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw TranslatorError.http(http.statusCode)
        }
        return data
    }
}

enum TranslatorError: LocalizedError {
    case http(Int)
    case badResponse
    case empty
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case .http(let code): return "网络请求失败（HTTP \(code)）"
        case .badResponse: return "返回数据无法解析"
        case .empty: return "没有结果"
        case .unavailable(let msg): return msg
        }
    }
}

extension Error {
    var friendlyMessage: String {
        if let e = self as? LocalizedError, let d = e.errorDescription { return d }
        let ns = self as NSError
        if ns.domain == NSURLErrorDomain {
            switch ns.code {
            case NSURLErrorNotConnectedToInternet: return "网络未连接"
            case NSURLErrorTimedOut: return "请求超时"
            case NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost: return "无法连接服务器"
            default: return "网络错误（\(ns.code)）"
            }
        }
        return ns.localizedDescription
    }
}
