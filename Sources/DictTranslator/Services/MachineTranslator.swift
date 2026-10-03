import Foundation

enum TranslationEngine: String, CaseIterable, Identifiable {
    case googleWithFallback   // 自动：Google → 腾讯 → 系统离线
    case tencentFirst         // 腾讯 → Google → 系统离线
    case appleOnly

    var id: String { rawValue }
    var title: String {
        switch self {
        case .googleWithFallback: return "自动：Google 优先，失败时依次用腾讯交互翻译、系统离线翻译"
        case .tencentFirst: return "腾讯交互翻译优先（国内网络更稳定）"
        case .appleOnly: return "仅使用系统离线翻译"
        }
    }
}

struct MachineTranslation: Hashable {
    var text: String
    var engineName: String
}

@MainActor
enum MachineTranslator {
    private final class CacheEntry {
        let result: MachineTranslation
        init(_ r: MachineTranslation) { result = r }
    }
    private static let cache = NSCache<NSString, CacheEntry>()
    /// Google 被限流（429 / 人机验证）或连不上（超时等）后暂停使用一段时间，避免每次都等它失败
    private static var googleBlockedUntil = Date.distantPast

    static var isGoogleBlocked: Bool { Date() < googleBlockedUntil }

    /// Google 的任何调用（翻译、语言检测）失败时都在这里登记
    static func noteGoogleFailure(_ error: Error) {
        if isRateLimited(error) {
            googleBlockedUntil = Date().addingTimeInterval(600)
        } else if isUnreachable(error) {
            googleBlockedUntil = Date().addingTimeInterval(120)
        }
    }

    private enum Provider {
        case google, tencent, apple
        var name: String {
            switch self {
            case .google: return "Google"
            case .tencent: return "腾讯翻译"
            case .apple: return "系统翻译"
            }
        }
    }

    static func translate(_ text: String, from: Lang, to: Lang) async throws -> MachineTranslation {
        let engine = TranslationEngine(rawValue: UserDefaults.standard.string(forKey: SettingsKeys.engine) ?? "") ?? .googleWithFallback
        let key = "\(from.rawValue)|\(to.rawValue)|\(text)" as NSString
        if let hit = cache.object(forKey: key) { return hit.result }

        var providers: [Provider]
        switch engine {
        case .googleWithFallback: providers = [.google, .tencent, .apple]
        case .tencentFirst: providers = [.tencent, .google, .apple]
        case .appleOnly: providers = [.apple]
        }
        if Date() < googleBlockedUntil, providers.count > 1 {
            providers.removeAll { $0 == .google }
        }

        var errors: [String] = []
        for p in providers {
            if Task.isCancelled { throw CancellationError() }
            do {
                let text = try await run(p, text, from: from, to: to)
                let result = MachineTranslation(text: text, engineName: p.name)
                cache.setObject(CacheEntry(result), forKey: key)
                return result
            } catch {
                if Task.isCancelled { throw CancellationError() }
                if p == .google { noteGoogleFailure(error) }
                errors.append("\(p.name)：\(error.friendlyMessage)")
            }
        }
        throw TranslatorError.unavailable(errors.joined(separator: "\n"))
    }

    private static func run(_ p: Provider, _ text: String, from: Lang, to: Lang) async throws -> String {
        switch p {
        case .google: return try await GoogleTranslateService.translate(text, from: from, to: to)
        case .tencent: return try await TencentTranslateService.translate(text, from: from, to: to)
        case .apple: return try await AppleTranslateService.translate(text, from: from, to: to)
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
