import Foundation

/// 句子翻译服务（单词释义不受影响）：Bing 在线翻译 + 两个本地混元翻译模型
enum TranslationEngine: String, CaseIterable, Identifiable {
    case bing
    case hyMT2_7B
    case hyMT2_1_8B

    var id: String { rawValue }
    var title: String {
        switch self {
        case .bing: return "Bing 翻译（在线）"
        case .hyMT2_7B: return "混元翻译模型 Hy-MT2-7B（本地）"
        case .hyMT2_1_8B: return "混元翻译轻量级模型 Hy-MT2-1.8B（本地）"
        }
    }

    /// 译文旁显示的来源
    var shortName: String {
        switch self {
        case .bing: return "Bing"
        case .hyMT2_7B: return "混元 7B"
        case .hyMT2_1_8B: return "混元 1.8B"
        }
    }

    var localModel: LocalModel? {
        switch self {
        case .bing: return nil
        case .hyMT2_7B: return .hyMT2_7B
        case .hyMT2_1_8B: return .hyMT2_1_8B
        }
    }

    /// 本地模型需要先下载
    var isAvailable: Bool { localModel?.isInstalled ?? true }

    static var current: TranslationEngine {
        let raw = UserDefaults.standard.string(forKey: SettingsKeys.engine) ?? ""
        return TranslationEngine(rawValue: raw) ?? .bing
    }

    /// 旧版本保存的引擎值（已删除的系统翻译 / Google / 腾讯 / 彩云等）迁移到 Bing
    static func migrateLegacySetting() {
        let defaults = UserDefaults.standard
        guard let raw = defaults.string(forKey: SettingsKeys.engine), TranslationEngine(rawValue: raw) == nil else { return }
        defaults.set(TranslationEngine.bing.rawValue, forKey: SettingsKeys.engine)
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
        let text = QueryClassifier.joinSoftWraps(text)
        let engine = TranslationEngine.current
        let fallback = UserDefaults.standard.bool(forKey: SettingsKeys.engineFallback)
        let key = "\(engine.rawValue)|\(fallback)|\(from.rawValue)|\(to.rawValue)|\(text)"
        if let hit = cache[key] { return hit }

        var engines = [engine]
        // 备用服务只用已下载的本地模型
        if fallback { engines += TranslationEngine.allCases.filter { $0 != engine && $0.isAvailable } }

        var errors: [String] = []
        for e in engines {
            if Task.isCancelled { throw CancellationError() }
            do {
                let text = try await translateChunked(text, engine: e, from: from, to: to)
                // 用的不是所选服务（本地模型未下载、出错）时在来源里注明，不让用户误以为是离线翻译的
                let name = e == engine ? e.shortName : "\(e.shortName)（\(engine.shortName) \(engine.isAvailable ? "失败" : "未下载")）"
                let result = MachineTranslation(text: text, engineName: name)
                cache[key] = result
                return result
            } catch {
                if Task.isCancelled { throw CancellationError() }
                errors.append("\(e.shortName)：\(error.friendlyMessage)")
            }
        }
        throw TranslatorError.unavailable(errors.joined(separator: "\n"))
    }

    /// 长文按段落切成不超过 1000 字的片段逐段翻译再拼回（Bing 网页接口单次上限 1000 字；
    /// 本地模型单次最多输出 4K token，整篇一次翻译会被截断，也会长时间占住模型）
    private static func translateChunked(_ text: String, engine: TranslationEngine, from: Lang, to: Lang) async throws -> String {
        var joined = ""
        for (i, chunk) in TextChunker.chunks(of: text).enumerated() {
            try Task.checkCancellation()
            let translated = try await run(engine, chunk.text, from: from, to: to)
            if i > 0 { joined += chunk.startsLine ? "\n" : (to == .en ? " " : "") }
            joined += translated
        }
        // 翻译服务常在换行前留下多余的空格
        let result = joined
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else { throw TranslatorError.empty }
        return result
    }

    private static func run(_ engine: TranslationEngine, _ text: String, from: Lang, to: Lang) async throws -> String {
        switch engine {
        case .bing: return try await BingTranslateService.translate(text, from: from, to: to)
        case .hyMT2_7B, .hyMT2_1_8B:
            return try await HyMTService.translate(text, from: from, to: to, model: engine.localModel!)
        }
    }
}

/// 把长文切成片段：按段落拼成不超过上限的片段；单个段落过长时再按句子切，仍过长就硬切
enum TextChunker {
    static let maxChunk = 1000

    static func chunks(of text: String, limit: Int = maxChunk) -> [(text: String, startsLine: Bool)] {
        guard text.count > limit else { return [(text, true)] }
        // startsLine：片段是否从新的一行开始（同一段落切出来的句子之间不加换行）
        var pieces: [(text: String, startsLine: Bool)] = []
        for line in text.components(separatedBy: "\n") {
            if line.count <= limit { pieces.append((line, true)); continue }
            var sentence = ""
            var first = true
            for ch in line {
                sentence.append(ch)
                if "。．.!?！？".contains(ch) || sentence.count >= limit {
                    pieces.append((sentence, first)); sentence = ""; first = false
                }
            }
            if !sentence.isEmpty { pieces.append((sentence, first)) }
        }
        // 相邻片段能合并就合并，减少请求数；原来的换行保留在片段内
        var out: [(text: String, startsLine: Bool)] = []
        for piece in pieces {
            let separator = piece.startsLine ? "\n" : ""
            if let last = out.last, last.text.count + separator.count + piece.text.count <= limit {
                out[out.count - 1].text += separator + piece.text
            } else {
                out.append(piece)
            }
        }
        return out.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}
