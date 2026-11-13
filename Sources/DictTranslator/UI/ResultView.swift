import SwiftUI

/// 查询结果：中文输入展示英语和日语，英语 / 日语输入展示中文
struct ResultView: View {
    @ObservedObject var vm: LookupViewModel
    /// 输入窗里原文就在输入框，不重复显示（日语句子仍显示注音）；离屏渲染等场景需要显示原文
    var showSource = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            sourceHeader
            ForEach(vm.sourceLang.targets) { target in
                section(for: target)
            }
        }
    }

    // MARK: - 原文

    @ViewBuilder private var sourceHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if vm.canGoBack {
                    IconButton(systemName: "chevron.left", help: "返回") { vm.goBack() }
                }
                detectedLanguageHint
                Spacer(minLength: 0)
                // 单词的发音在词条里；句子在这里朗读原文（太长的不朗读）
                if !vm.isWord, !vm.isDetecting, let voice = vm.sourceLang.speechVoice, vm.text.count < (vm.sourceLang == .en ? 600 : 300) {
                    IconButton(systemName: "speaker.wave.2", help: "朗读原文") {
                        AudioPlayer.shared.play(.speech(text: vm.text, language: voice))
                    }
                }
                if showSource {
                    IconButton(systemName: "doc.on.doc", help: "复制原文") { Pasteboard.copy(vm.text) }
                }
            }
            sourceBody
        }
    }

    /// 一行小字说明识别出的语言；汉字文本中日可能判错，点击切换
    @ViewBuilder private var detectedLanguageHint: some View {
        if vm.isDetecting {
            Text("正在识别语言…").font(.system(size: 11)).foregroundStyle(Theme.tertiary)
        } else if vm.canToggleChineseJapanese {
            let other: Lang = vm.sourceLang == .ja ? .zh : .ja
            Button { vm.switchLanguage(other) } label: {
                HStack(spacing: 4) {
                    Text("识别为\(vm.sourceLang.chineseName)").foregroundStyle(Theme.tertiary)
                    Text("· 改为\(other.chineseName)").foregroundStyle(Theme.accent)
                }
                .font(.system(size: 11))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("识别错了？按\(other.chineseName)重新查询")
        } else {
            Text("识别为\(vm.sourceLang.chineseName)").font(.system(size: 11)).foregroundStyle(Theme.tertiary)
        }
    }

    // MARK: - 原文

    @ViewBuilder private var sourceBody: some View {
        if vm.sourceLang == .ja, !vm.sourceTokens.isEmpty, (!vm.isWord || showSource) {
            // 日语单词的读音在词条里显示；句子或需要显示原文时用带注音的原文
            // 句子里的实词可以点击，查它的原形
            FuriganaText(tokens: vm.sourceTokens, fontSize: vm.isWord ? 17 : 15,
                         onWordTap: vm.isWord ? nil : { vm.follow($0, as: .ja) })
                .padding(.horizontal, 2)
        } else if showSource {
            Text(vm.text)
                .font(.system(size: vm.isWord ? 17 : 14, weight: vm.isWord ? .semibold : .regular))
                .textSelection(.enabled)
                .lineLimit(8)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 2)
        }
    }

    // MARK: - 目标语言区块

    @ViewBuilder private func section(for target: Lang) -> some View {
        switch (vm.sourceLang, target, vm.isWord) {
        case (.en, .zh, true):
            dictionarySection(target: target, state: vm.englishEntry, badge: "有道词典") {
                // id：换词时重置「更多短语」等展开状态
                EnglishEntryView(entry: $0, follow: { vm.follow($0) }).id($0.word)
            }
        case (.ja, .zh, true):
            dictionarySection(target: target, state: vm.japaneseEntry, badge: "MOJi辞書",
                              whenMissing: AnyView(KokugoView(kokugo: vm.japaneseKokugo).id(vm.text))) {
                JapaneseEntryView(entry: $0, kokugo: vm.japaneseKokugo, follow: { vm.follow($0.spell, as: .ja, entryId: $0.id) }).id($0.id)
            }
        case (.zh, .en, true):
            dictionarySection(target: target, state: vm.chineseEnglish, badge: "有道词典") {
                ChineseEnglishView(entry: $0, follow: { vm.follow($0) })
            }
        case (.zh, .ja, true):
            // 机器翻译在上；MOJi 搜到的日语词（可能只是字面相近）作为参考放在下面
            translationSection(target: target, footer: (vm.chineseJapanese.value ?? nil).map { AnyView(relatedJapanese($0)) })
        default:
            translationSection(target: target)
        }
    }

    /// 辞典结果 + 下方附机器翻译
    /// whenMissing：辞典没有这个词时，在机器翻译下方补充显示的内容
    private func dictionarySection<T, V: View>(target: Lang, state: Loadable<T?>, badge: String, whenMissing: AnyView? = nil,
                                               @ViewBuilder content: @escaping (T) -> V) -> some View {
        // 辞典没有这个词时显示的是机器翻译，标注翻译来源
        let isMissing = if case .loaded(nil) = state { true } else { false }
        let shownBadge = isMissing ? vm.translations[target]?.value?.engineName : badge
        return SectionCard(title: target.displayName, badge: shownBadge) {
            switch state {
            case .idle, .loading:
                LoadingRow()
            case .failed(let msg):
                ErrorRow(message: "词典：\(msg)", retry: vm.retry)
                machineLine(target: target, prominent: true)
            case .loaded(nil):
                machineLine(target: target, prominent: true)
                if let whenMissing { whenMissing }
            case .loaded(let entry?):
                content(entry)
                machineLine(target: target, prominent: false)
            }
        }
    }

    /// 词条模式下的机器翻译补充行；没有词条时作为主结果显示
    @ViewBuilder private func machineLine(target: Lang, prominent: Bool) -> some View {
        switch vm.translations[target] ?? .idle {
        case .idle:
            EmptyView()
        case .loading:
            if prominent { LoadingRow() }
        case .failed(let msg):
            if prominent { ErrorRow(message: msg, retry: vm.retry) }
        case .loaded(let mt):
            if prominent {
                translationBody(target: target, mt: mt)
            } else {
                RuleLine()
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(mt.engineName).font(.system(size: 10)).foregroundStyle(Theme.tertiary)
                    if target == .ja, let tokens = vm.translationTokens[.ja] {
                        FuriganaText(tokens: tokens, fontSize: 13, onWordTap: { vm.follow($0, as: .ja) })
                    } else {
                        Text(mt.text).font(.system(size: 13)).textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    IconButton(systemName: "doc.on.doc", help: "复制") { Pasteboard.copy(mt.text) }
                }
            }
        }
    }

    /// 中文单词的日语：译文下方依次是同形异义提醒、词典对应词、MOJi 搜索到的其他词
    private func relatedJapanese(_ entry: ChineseJapaneseEntry) -> some View {
        let follow: (JapaneseCandidate) -> Void = { vm.follow($0.spell, as: .ja, entryId: $0.id) }
        return VStack(alignment: .leading, spacing: 6) {
            if let ff = vm.japaneseFalseFriend {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Image(systemName: "exclamationmark.triangle").font(.system(size: 11))
                    Text("日语的「\(ff.spell)」\(ff.reading.map { "（\($0)）" } ?? "")意为「\(FalseFriendDetector.senses(of: ff).prefix(3).joined(separator: "；"))」，和中文「\(vm.text)」不同")
                        .font(.system(size: 12))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(Theme.pos)
            }
            if !entry.equivalents.isEmpty {
                RuleLine()
                subheading("词典对应", source: "汉日词典 · MOJi辞書")
                ChineseJapaneseView(candidates: entry.equivalents, follow: follow)
            }
            if !entry.related.isEmpty {
                RuleLine()
                subheading("相关词条", source: "MOJi辞書")
                ChineseJapaneseView(candidates: Array(entry.related.prefix(6)), word: vm.text, follow: follow)
            }
        }
    }

    private func subheading(_ title: String, source: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.secondary)
            Text(source).font(.system(size: 9)).foregroundStyle(Theme.tertiary)
        }
    }

    /// footer：译文下方补充的内容
    private func translationSection(target: Lang, footer: AnyView? = nil) -> some View {
        let state = vm.translations[target] ?? .idle
        let badge = state.value?.engineName
        return SectionCard(title: target.displayName, badge: badge) {
            switch state {
            case .idle, .loading:
                LoadingRow()
            case .failed(let msg):
                ErrorRow(message: msg, retry: vm.retry)
            case .loaded(let mt):
                translationBody(target: target, mt: mt)
            }
            if let footer { footer }
        }
    }

    private func translationBody(target: Lang, mt: MachineTranslation) -> some View {
        HStack(alignment: .top, spacing: 6) {
            VStack(alignment: .leading, spacing: 4) {
                if target == .ja, let tokens = vm.translationTokens[.ja], !tokens.isEmpty {
                    FuriganaText(tokens: tokens, fontSize: 15, onWordTap: { vm.follow($0, as: .ja) })
                } else {
                    Text(mt.text)
                        .font(.system(size: 14))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            VStack(spacing: 2) {
                IconButton(systemName: "doc.on.doc", help: "复制") { Pasteboard.copy(mt.text) }
                // 有道的句子发音时好时坏（单词没问题），译文用系统语音朗读；太长的不朗读
                if let voice = target.speechVoice, mt.text.count < (target == .en ? 300 : 200) {
                    IconButton(systemName: "speaker.wave.2", help: "朗读") {
                        AudioPlayer.shared.play(.speech(text: mt.text, language: voice))
                    }
                }
            }
        }
    }
}
