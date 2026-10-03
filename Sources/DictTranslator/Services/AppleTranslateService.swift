import Foundation
#if canImport(Translation)
import Translation
#endif

/// macOS 系统自带的离线翻译（需在「系统设置 › 通用 › 语言与地区 › 翻译语言」下载语言包）
enum AppleTranslateService {
    static var isSupported: Bool {
        if #available(macOS 26.0, *) { return true }
        return false
    }

    static func translate(_ text: String, from: Lang, to: Lang) async throws -> String {
        #if canImport(Translation)
        if #available(macOS 26.0, *) {
            let availability = LanguageAvailability()
            let status = await availability.status(from: from.localeLanguage, to: to.localeLanguage)
            switch status {
            case .installed:
                break
            case .supported:
                throw TranslatorError.unavailable("系统离线翻译未下载\(from.displayName)→\(to.displayName)语言包（系统设置 › 通用 › 语言与地区 › 翻译语言）")
            default:
                throw TranslatorError.unavailable("系统翻译不支持该语言组合")
            }
            let session = TranslationSession(installedSource: from.localeLanguage, target: to.localeLanguage)
            let response = try await session.translate(text)
            return response.targetText
        }
        #endif
        throw TranslatorError.unavailable("系统离线翻译需要 macOS 26 或更高版本")
    }
}
