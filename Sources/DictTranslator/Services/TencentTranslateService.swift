import Foundation

/// 腾讯交互翻译（TranSmart）网页接口，国内网络直连可用
enum TencentTranslateService {
    private static let clientKey: String = {
        let key = "tencentClientKey"
        if let k = UserDefaults.standard.string(forKey: key) { return k }
        let k = "browser-chrome-120.0.0-Mac OS-\(UUID().uuidString)-1-\(Int(Date().timeIntervalSince1970 * 1000))"
        UserDefaults.standard.set(k, forKey: key)
        return k
    }()

    private static func code(_ lang: Lang) -> String {
        switch lang {
        case .zh: return "zh"
        case .en: return "en"
        case .ja: return "ja"
        }
    }

    /// 腾讯的语言检测对纯汉字短词基本都判为中文，主要对句子有用
    static func detect(_ text: String) async throws -> Lang? {
        let body: [String: Any] = [
            "header": ["fn": "text_analysis", "client_key": clientKey],
            "type": "plain",
            "text": text,
            "normalize": ["source": ["lang": "auto"]],
        ]
        var req = URLRequest(url: URL(string: "https://transmart.qq.com/api/imt")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(HTTP.userAgent, forHTTPHeaderField: "User-Agent")
        req.setValue("https://transmart.qq.com/", forHTTPHeaderField: "Referer")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await HTTP.detectSession.data(for: req)
        if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw TranslatorError.http(http.statusCode)
        }
        guard let obj = try? JSONSerialization.jsonObject(with: data) else { throw TranslatorError.badResponse }
        let root = JSONValue(obj)
        guard root["header"]["ret_code"].string == "succ" else { throw TranslatorError.badResponse }
        return Lang(rawValue: root["language"].string ?? "")
    }

    static func translate(_ text: String, from: Lang, to: Lang) async throws -> String {
        // 按段落拆分，保留原文换行
        let paragraphs = text.components(separatedBy: "\n")
        let body: [String: Any] = [
            "header": ["fn": "auto_translation", "client_key": clientKey],
            "type": "plain",
            "model_category": "normal",
            "source": ["lang": code(from), "text_list": paragraphs],
            "target": ["lang": code(to)],
        ]
        var req = URLRequest(url: URL(string: "https://transmart.qq.com/api/imt")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(HTTP.userAgent, forHTTPHeaderField: "User-Agent")
        req.setValue("https://transmart.qq.com/", forHTTPHeaderField: "Referer")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await HTTP.session.data(for: req)
        if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw TranslatorError.http(http.statusCode)
        }
        guard let obj = try? JSONSerialization.jsonObject(with: data) else { throw TranslatorError.badResponse }
        let root = JSONValue(obj)
        guard root["header"]["ret_code"].string == "succ" else { throw TranslatorError.badResponse }
        let parts = root["auto_translation"].array.map { $0.string ?? "" }
        let result = parts.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else { throw TranslatorError.empty }
        return result
    }
}
