import SwiftUI

/// 查询结果：输入任一语言，展示另外两种语言
struct ResultView: View {
    @ObservedObject var vm: LookupViewModel
    /// 划词卡片中显示原文；输入窗里原文就在输入框，不重复显示（日语句子仍显示注音）
    var showSource = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            sourceHeader
            ForEach(vm.sourceLang.others) { target in
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
                Picker("", selection: Binding(get: { vm.sourceLang }, set: { vm.switchLanguage($0) })) {
                    ForEach(Lang.allCases) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .controlSize(.small)
                .help("识别的源语言（可手动切换）")
                if vm.canToggleChineseJapanese {
                    let target: Lang = vm.sourceLang == .ja ? .zh : .ja
                    Button(target == .ja ? "按日语查" : "按中文查") { vm.switchLanguage(target) }
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.accent)
                        .font(.system(size: 11))
                }
                Spacer(minLength: 0)
                if showSource {
                    IconButton(systemName: "doc.on.doc", help: "复制原文") { Pasteboard.copy(vm.text) }
                }
            }

            // 日语单词的读音在词条里显示；句子或划词卡片中显示带注音的原文
            if vm.sourceLang == .ja, !vm.sourceTokens.isEmpty, (!vm.isWord || showSource) {
                FuriganaText(tokens: vm.sourceTokens, fontSize: vm.isWord ? 17 : 15)
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
    }

    // MARK: - 目标语言区块

    @ViewBuilder private func section(for target: Lang) -> some View {
        switch (vm.sourceLang, target, vm.isWord) {
        case (.en, .zh, true):
            dictionarySection(target: target, state: vm.englishEntry) { EnglishEntryView(entry: $0, follow: vm.follow) }
        case (.ja, .zh, true):
            dictionarySection(target: target, state: vm.japaneseEntry) { JapaneseEntryView(entry: $0) }
        case (.zh, .en, true):
            dictionarySection(target: target, state: vm.chineseEnglish) { ChineseEnglishView(entry: $0, follow: vm.follow) }
        case (.zh, .ja, true):
            dictionarySection(target: target, state: vm.chineseJapanese) { ChineseJapaneseView(entry: $0, follow: vm.follow) }
        default:
            translationSection(target: target)
        }
    }

    /// 辞典结果 + 下方附机器翻译
    private func dictionarySection<T, V: View>(target: Lang, state: Loadable<T?>, @ViewBuilder content: @escaping (T) -> V) -> some View {
        SectionCard(title: target.displayName, badge: "有道词典") {
            switch state {
            case .idle, .loading:
                LoadingRow()
            case .failed(let msg):
                ErrorRow(message: "词典：\(msg)", retry: vm.retry)
                machineLine(target: target, prominent: true)
            case .loaded(nil):
                machineLine(target: target, prominent: true)
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
                        FuriganaText(tokens: tokens, fontSize: 13)
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

    private func translationSection(target: Lang) -> some View {
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
            if vm.isWord {
                if target == .ja, let e = vm.targetJapaneseEntry {
                    RuleLine()
                    JapaneseEntryView(entry: e, compact: true)
                } else if target == .en, let e = vm.targetEnglishEntry {
                    RuleLine()
                    EnglishEntryView(entry: e, compact: true, follow: vm.follow)
                }
            }
        }
    }

    private func translationBody(target: Lang, mt: MachineTranslation) -> some View {
        HStack(alignment: .top, spacing: 6) {
            VStack(alignment: .leading, spacing: 4) {
                if target == .ja, let tokens = vm.translationTokens[.ja], !tokens.isEmpty {
                    FuriganaText(tokens: tokens, fontSize: 15)
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
                if target == .en, mt.text.count < 300 {
                    IconButton(systemName: "speaker.wave.2", help: "朗读") {
                        AudioPlayer.shared.play(YoudaoDictService.englishAudioURL(mt.text, american: true))
                    }
                } else if target == .ja, mt.text.count < 200 {
                    IconButton(systemName: "speaker.wave.2", help: "朗读") {
                        AudioPlayer.shared.play(YoudaoDictService.japaneseAudioURL(mt.text))
                    }
                }
            }
        }
    }
}
