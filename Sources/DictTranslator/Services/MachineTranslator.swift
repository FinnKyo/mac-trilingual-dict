import Foundation

/// 句子翻译服务（单词释义不受影响）
enum TranslationEngine: String, CaseIterable, Identifiable {
    case bing
    case apple

    var id: String { rawValue }
    var title: String {
        switch self {
        case .bing: return "Bing 翻译（在线）"
        case .apple: return "系统离线翻译（macOS 26+，需下载语言包）"
        }
    }

    /// 译文旁显示的来源
    var shortName: String {
        switch self {
        case .bing: return "Bing"
        case .apple: return "系统翻译"
        }
    }

    static var current: TranslationEngine {
        let raw = UserDefaults.standard.string(forKey: SettingsKeys.engine) ?? ""
        return TranslationEngine(rawValue: raw) ?? .bing
    }

    /// 旧版本保存的引擎值（已删除的 Google / 腾讯 / 彩云等）迁移到新选项
    static func migrateLegacySetting() {
        let defaults = UserDefaults.standard
        guard let raw = defaults.string(forKey: SettingsKeys.engine), TranslationEngine(rawValue: raw) == nil else { return }
        if raw == "appleOnly" {
            defaults.set(TranslationEngine.apple.rawValue, forKey: SettingsKeys.engine)
            defaults.set(false, forKey: SettingsKeys.engineFallback)
        } else {
            defaults.set(TranslationEngine.bing.rawValue, forKey: SettingsKeys.engine)
        }
    }
}

struct MachineTranslation: Hashable {
    var text: String
    var engineName: String
}

@MainActor
enum MachineTranslator {
    private static let cache = Cache<MachineTranslation>()

    static func translate(_ text: String, from: Lang, to: Lang) async throws -> MachineTranslation {
        let engine = TranslationEngine.current
        let fallback = UserDefaults.standard.bool(forKey: SettingsKeys.engineFallback)
        let key = "\(engine.rawValue)|\(fallback)|\(from.rawValue)|\(to.rawValue)|\(text)"
        if let hit = cache[key] { return hit }

        var engines = [engine]
        if fallback { engines += TranslationEngine.allCases.filter { $0 != engine } }

        var errors: [String] = []
        for e in engines {
            if Task.isCancelled { throw CancellationError() }
            do {
                let text = try await run(e, text, from: from, to: to)
                let result = MachineTranslation(text: text, engineName: e.shortName)
                cache[key] = result
                return result
            } catch {
                if Task.isCancelled { throw CancellationError() }
                errors.append("\(e.shortName)：\(error.friendlyMessage)")
            }
        }
        throw TranslatorError.unavailable(errors.joined(separator: "\n"))
    }

    private static func run(_ engine: TranslationEngine, _ text: String, from: Lang, to: Lang) async throws -> String {
        switch engine {
        case .bing: return try await BingTranslateService.translate(text, from: from, to: to)
        case .apple: return try await AppleTranslateService.translate(text, from: from, to: to)
        }
    }
}
