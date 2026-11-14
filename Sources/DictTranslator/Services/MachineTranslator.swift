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

    /// 不可用时的原因（译文来源里注明）
    var unavailableReason: String { "未下载" }

    /// 用户排好的顺序（包含未启用的），新增的服务排在最后
    static var order: [TranslationEngine] {
        let saved = (UserDefaults.standard.stringArray(forKey: SettingsKeys.engineOrder) ?? []).compactMap(TranslationEngine.init)
        var seen = Set<TranslationEngine>()
        let unique = saved.filter { seen.insert($0).inserted }
        return unique + allCases.filter { !unique.contains($0) }
    }

    static var disabled: Set<TranslationEngine> {
        Set((UserDefaults.standard.stringArray(forKey: SettingsKeys.engineDisabled) ?? []).compactMap(TranslationEngine.init))
    }

    /// 依次尝试的服务：按顺序、去掉未启用的
    static var chain: [TranslationEngine] {
        let off = disabled
        return order.filter { !off.contains($0) }
    }

    static func save(order: [TranslationEngine], disabled: Set<TranslationEngine>) {
        let d = UserDefaults.standard
        d.set(order.map(\.rawValue), forKey: SettingsKeys.engineOrder)
        d.set(order.filter(disabled.contains).map(\.rawValue), forKey: SettingsKeys.engineDisabled)
        // 排在最前的本地模型留着，其余已加载的马上释放内存（备用的用到时再加载）
        HyMTService.unloadAll(except: chain.first(where: { $0.isAvailable })?.localModel)
    }

    /// 旧版本是「单选一个服务 + 失败时换用其他服务」：转成顺序列表，所选的排第一；没开备用就只启用所选的。
    /// 更早版本保存的引擎值（已删除的系统翻译 / Google / 腾讯 / 彩云等）当作 Bing
    static func migrateLegacySetting() {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: SettingsKeys.engineOrder) == nil else { return }
        let primary = defaults.string(forKey: SettingsKeys.engine).flatMap(TranslationEngine.init) ?? .bing
        let fallback = defaults.object(forKey: SettingsKeys.engineFallback) as? Bool ?? true
        let order = [primary] + allCases.filter { $0 != primary }
        defaults.set(order.map(\.rawValue), forKey: SettingsKeys.engineOrder)
        defaults.set(fallback ? [] : order.dropFirst().map(\.rawValue), forKey: SettingsKeys.engineDisabled)
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
        let chain = TranslationEngine.chain
        guard let first = chain.first else {
            throw TranslatorError.unavailable("没有启用任何句子翻译服务（设置 › 通用 › 句子翻译服务）")
        }
        let key = "\(chain.map(\.rawValue).joined(separator: ","))|\(from.rawValue)|\(to.rawValue)|\(text)"
        if let hit = cache[key] { return hit }

        var errors: [String] = []
        for e in chain {
            if Task.isCancelled { throw CancellationError() }
            guard e.isAvailable else {
                errors.append("\(e.shortName)：\(e.unavailableReason)")
                continue
            }
            do {
                let text = try await translateChunked(text, engine: e, from: from, to: to)
                // 用的不是排在第一的服务（未下载 / 出错）时在来源里注明，不让用户误以为是首选服务翻译的
                let name = e == first ? e.shortName : "\(e.shortName)（\(first.shortName) \(first.isAvailable ? "失败" : first.unavailableReason)）"
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
