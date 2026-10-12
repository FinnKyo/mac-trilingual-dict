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

    /// 查询参数值的百分号编码。URLComponents 不会编码「+」（服务器会当成空格），所以自己编码
    static func encodeQueryValue(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
    }

    static func url(_ base: String, query: KeyValuePairs<String, String>) -> URL? {
        let qs = query.map { "\($0.key)=\(encodeQueryValue($0.value))" }.joined(separator: "&")
        return URL(string: base + "?" + qs)
    }

    static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

    static func get(_ url: URL, referer: String? = nil, session: URLSession = HTTP.session) async throws -> Data {
        var req = URLRequest(url: url)
        if let referer { req.setValue(referer, forHTTPHeaderField: "Referer") }
        return try await send(req, session: session).data
    }

    /// 发送请求（未指定 User-Agent 时用浏览器的），非 2xx 状态码抛出 TranslatorError.http
    static func send(_ request: URLRequest, session: URLSession = HTTP.session) async throws -> (data: Data, response: URLResponse) {
        var req = request
        if req.value(forHTTPHeaderField: "User-Agent") == nil { req.setValue(userAgent, forHTTPHeaderField: "User-Agent") }
        let (data, resp) = try await session.data(for: req)
        if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw TranslatorError.http(http.statusCode)
        }
        return (data, resp)
    }

    /// 发送请求并解析 JSON
    static func json(_ request: URLRequest, session: URLSession = HTTP.session) async throws -> JSONValue {
        let data = try await send(request, session: session).data
        guard let obj = try? JSONSerialization.jsonObject(with: data) else { throw TranslatorError.badResponse }
        return JSONValue(obj)
    }

    /// 带 JSON 请求体的 POST
    static func postJSON(_ url: URL, body: Any, headers: [String: String] = [:]) throws -> URLRequest {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        headers.forEach { req.setValue($0.value, forHTTPHeaderField: $0.key) }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        return req
    }

    /// 表单编码的 POST
    static func postForm(_ url: URL, _ form: KeyValuePairs<String, String>) -> URLRequest {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded;charset=UTF-8", forHTTPHeaderField: "Content-Type")
        req.httpBody = form.map { "\($0.key)=\(encodeQueryValue($0.value))" }.joined(separator: "&").data(using: .utf8)
        return req
    }
}

/// NSCache 只能存对象，这里包一层以便缓存结构体、可选值
final class Cache<Value> {
    private final class Box { let value: Value; init(_ v: Value) { value = v } }
    private let storage = NSCache<NSString, Box>()

    subscript(key: String) -> Value? {
        get { storage.object(forKey: key as NSString)?.value }
        set {
            if let newValue { storage.setObject(Box(newValue), forKey: key as NSString) }
            else { storage.removeObject(forKey: key as NSString) }
        }
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
            case NSURLErrorSecureConnectionFailed, NSURLErrorServerCertificateHasBadDate,
                 NSURLErrorServerCertificateUntrusted, NSURLErrorServerCertificateHasUnknownRoot,
                 NSURLErrorServerCertificateNotYetValid: return "服务器证书异常，暂时无法连接"
            default: return "网络错误（\(ns.code)）"
            }
        }
        return ns.localizedDescription
    }
}
