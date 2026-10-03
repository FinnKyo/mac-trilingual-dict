import Foundation

/// 有道返回的 JSON 结构多变（同一字段可能是字符串、数组或对象），用宽松的方式读取。
struct JSONValue {
    let raw: Any?

    init(_ raw: Any?) { self.raw = raw }

    subscript(key: String) -> JSONValue {
        JSONValue((raw as? [String: Any])?[key])
    }

    subscript(index: Int) -> JSONValue {
        guard let arr = raw as? [Any], index >= 0, index < arr.count else { return JSONValue(nil) }
        return JSONValue(arr[index])
    }

    var exists: Bool { raw != nil && !(raw is NSNull) }

    var array: [JSONValue] {
        if let arr = raw as? [Any] { return arr.map(JSONValue.init) }
        if raw is [String: Any] { return [self] }
        return []
    }

    var string: String? {
        if let s = raw as? String { return s }
        if let n = raw as? NSNumber { return n.stringValue }
        return nil
    }

    var nonEmptyString: String? {
        guard let s = string?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        return s
    }

    var stringArray: [String] {
        array.compactMap { $0.nonEmptyString }
    }

    /// 把任意嵌套结构里的文本拼接起来（字符串、数组、{"#text": ...}）
    var flattenedText: String {
        JSONValue.flatten(raw).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func flatten(_ any: Any?) -> String {
        switch any {
        case let s as String:
            return s
        case let n as NSNumber:
            return n.stringValue
        case let arr as [Any]:
            return arr.map { flatten($0) }.joined()
        case let dict as [String: Any]:
            if let t = dict["#text"] { return flatten(t) }
            if let i = dict["i"] { return flatten(i) }
            if let l = dict["l"] { return flatten(l) }
            return ""
        default:
            return ""
        }
    }
}

extension String {
    /// 去掉有道返回中的 <b> 等 HTML 标签
    var strippingHTML: String {
        replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
    }
}
