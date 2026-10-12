import Foundation
import SwiftUI

enum Loadable<T> {
    case idle
    case loading
    case loaded(T)
    case failed(String)

    var value: T? {
        if case .loaded(let v) = self { return v }
        return nil
    }

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }
}

/// 一次查询的完整状态（输入翻译窗持有一个实例）
@MainActor
final class LookupViewModel: ObservableObject {
    @Published var inputText: String = ""

    @Published private(set) var text: String = ""
    @Published private(set) var sourceLang: Lang = .zh
    /// 用户手动指定的源语言；nil 表示由识别结果决定
    @Published private(set) var forcedSourceLang: Lang?
    @Published private(set) var isWord = false
    /// 纯汉字文本正在由识别服务判断中文 / 日语
    @Published private(set) var isDetecting = false
    @Published private(set) var sourceTokens: [RubyToken] = []

    // 辞典
    @Published private(set) var englishEntry: Loadable<EnglishEntry?> = .idle
    @Published private(set) var japaneseEntry: Loadable<JapaneseEntry?> = .idle
    /// 日语单词的国语辞典释义（大辞泉），在日语词条查到之后再查
    @Published private(set) var japaneseKokugo: Loadable<KokugoEntry?> = .idle
    @Published private(set) var chineseEnglish: Loadable<ChineseEnglishEntry?> = .idle
    @Published private(set) var chineseJapanese: Loadable<ChineseJapaneseEntry?> = .idle

    // 机器翻译
    @Published private(set) var translations: [Lang: Loadable<MachineTranslation>] = [:]
    @Published private(set) var translationTokens: [Lang: [RubyToken]] = [:]
    /// 英语单词 → 日语译词的简明词条；日语单词 → 英语译词的简明词条
    @Published private(set) var targetJapaneseEntry: JapaneseEntry?
    @Published private(set) var targetEnglishEntry: EnglishEntry?

    @Published private(set) var history: [(String, Lang?)] = []

    private var generation = 0
    private var tasks: [Task<Void, Never>] = []

    var hasQuery: Bool { !text.isEmpty }

    /// 有查询失败的部分（回车时据此重试）
    var hasFailures: Bool {
        func failed<T>(_ l: Loadable<T>) -> Bool { if case .failed = l { return true }; return false }
        return failed(englishEntry) || failed(japaneseEntry) || failed(japaneseKokugo) || failed(chineseEnglish) || failed(chineseJapanese)
            || translations.values.contains(where: failed)
    }
    var canGoBack: Bool { !history.isEmpty }

    /// 只有文字构成判断不了中日的汉字文本（命令、学习…）才允许手动切换；手动切换过的可以再切回来。
    /// 含「们 东 吃」或「経 駅」这类只有一边用的字时不会判错，不提供切换
    var canToggleChineseJapanese: Bool {
        guard !isDetecting, sourceLang != .en, LanguageDetector.isChineseOrJapaneseCandidate(text) else { return false }
        return forcedSourceLang != nil || LanguageDetector.analyze(text) == .ambiguous
    }

    /// 纯汉字文本由识别服务判断中文 / 日语；forcedLang 为手动指定的源语言
    func lookup(_ raw: String, forcedLang: Lang? = nil, recordHistory: Bool = false) {
        let t = QueryClassifier.normalize(raw)
        if recordHistory, !text.isEmpty, t != text {
            history.append((text, forcedSourceLang))
        }
        cancel()
        generation += 1
        isDetecting = false
        let gen = generation

        text = t
        forcedSourceLang = forcedLang
        if inputText != raw { inputText = t }
        resetResults()
        guard !t.isEmpty else { return }

        if let forcedLang {
            start(t, lang: forcedLang, gen: gen)
            return
        }
        switch LanguageDetector.analyze(t) {
        case .certain(let lang):
            start(t, lang: lang, gen: gen)
        case .ambiguous:
            // 先按中文占位显示加载中，识别出来后再正式查询
            sourceLang = .zh
            isWord = QueryClassifier.isWordLike(t, lang: .zh)
            isDetecting = true
            run { [weak self] in
                let lang = await LanguageIdentifier.resolveAmbiguous(t).lang
                guard let self, gen == self.generation else { return }
                self.isDetecting = false
                self.start(t, lang: lang, gen: gen)
            }
        }
    }

    private func start(_ t: String, lang: Lang, gen: Int) {
        sourceLang = lang
        isWord = QueryClassifier.isWordLike(t, lang: lang)
        sourceTokens = lang == .ja ? FuriganaService.tokens(for: t) : []

        for target in lang.others {
            translations[target] = .loading
            run { [weak self] in
                let r: Loadable<MachineTranslation>
                do { r = .loaded(try await MachineTranslator.translate(t, from: lang, to: target)) }
                catch { r = .failed(error.friendlyMessage) }
                self?.apply(gen) {
                    $0.translations[target] = r
                    if case .loaded(let mt) = r, target == .ja {
                        $0.translationTokens[.ja] = FuriganaService.tokens(for: mt.text)
                    }
                }
                if case .loaded(let mt) = r, self?.isWord == true {
                    await self?.lookupTargetEntry(mt.text, target: target, gen: gen)
                }
            }
        }

        guard isWord else { return }
        switch lang {
        case .en:
            load(\.englishEntry, gen: gen) { try await YoudaoDictService.lookupEnglish(t) }
        case .ja:
            load(\.japaneseEntry, gen: gen, { try await MojiDictService.lookup(t) }) { vm, r in
                // 国语辞典按词条的原形查；MOJi 没有这个词时用原文再试一次
                switch r {
                case .loaded(let entry?): vm.load(\.japaneseKokugo, gen: gen) { try await WeblioService.daijisen(entry.headword) }
                case .loaded(nil): vm.load(\.japaneseKokugo, gen: gen) { try await WeblioService.daijisen(t) }
                default: break
                }
            }
        case .zh:
            load(\.chineseEnglish, gen: gen) { try await YoudaoDictService.lookupChineseEnglish(t) }
            load(\.chineseJapanese, gen: gen) {
                let candidates = try await MojiDictService.search(t)
                return candidates.isEmpty ? nil : ChineseJapaneseEntry(candidates: Array(candidates.prefix(6)))
            }
        }
    }

    func switchLanguage(_ lang: Lang) {
        guard lang != sourceLang, !text.isEmpty else { return }
        lookup(text, forcedLang: lang)
    }

    /// 点击释义中的单词跳转查询；lang 指定时不再识别语言（如点击日语词条，避免「学校」被当成中文）
    func follow(_ word: String, as lang: Lang? = nil) {
        lookup(word, forcedLang: lang, recordHistory: true)
    }

    func goBack() {
        guard let (t, lang) = history.popLast() else { return }
        lookup(t, forcedLang: lang)
    }

    func retry() {
        lookup(text, forcedLang: forcedSourceLang)
    }

    func clear() {
        cancel()
        generation += 1
        isDetecting = false
        forcedSourceLang = nil
        text = ""
        inputText = ""
        history = []
        resetResults()
    }

    func cancel() {
        tasks.forEach { $0.cancel() }
        tasks = []
    }

    // MARK: - private

    private func resetResults() {
        sourceTokens = []
        englishEntry = .idle
        japaneseEntry = .idle
        japaneseKokugo = .idle
        chineseEnglish = .idle
        chineseJapanese = .idle
        translations = [:]
        translationTokens = [:]
        targetJapaneseEntry = nil
        targetEnglishEntry = nil
    }

    private func run(_ body: @escaping @MainActor () async -> Void) {
        tasks.append(Task { @MainActor in await body() })
    }

    private func apply(_ gen: Int, _ change: (LookupViewModel) -> Void) {
        guard gen == generation else { return }
        change(self)
    }

    /// 查一项辞典结果写入对应属性（先显示加载中）；then 在结果写入后执行（仍属于本次查询时）
    private func load<T>(_ keyPath: ReferenceWritableKeyPath<LookupViewModel, Loadable<T?>>, gen: Int,
                         _ op: @escaping () async throws -> T?,
                         then: ((LookupViewModel, Loadable<T?>) -> Void)? = nil) {
        apply(gen) { $0[keyPath: keyPath] = .loading }
        run { [weak self] in
            let r: Loadable<T?>
            do { r = .loaded(try await op()) } catch { r = .failed(error.friendlyMessage) }
            self?.apply(gen) {
                $0[keyPath: keyPath] = r
                then?($0, r)
            }
        }
    }

    /// 单词查询时，为译出的日语/英语词补充简明词条（读音、词性等）
    private func lookupTargetEntry(_ word: String, target: Lang, gen: Int) async {
        let w = word.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        guard !w.isEmpty, QueryClassifier.isWordLike(w, lang: target) else { return }
        switch target {
        case .ja where sourceLang == .en:
            if let e = try? await MojiDictService.lookup(w) {
                apply(gen) { $0.targetJapaneseEntry = e }
            }
        case .en where sourceLang == .ja:
            // 只在词典词头与译文一致时显示，避免「i ate」被匹配成缩写「IATE」这类误配
            if let e = try? await YoudaoDictService.lookupEnglish(w),
               e.word.lowercased() == w.lowercased() {
                apply(gen) { $0.targetEnglishEntry = e }
            }
        default:
            break
        }
    }
}
