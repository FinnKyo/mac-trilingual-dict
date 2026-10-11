import SwiftUI

/// 日语词条（MOJi 辞書）+ 国语辞典（デジタル大辞泉）
struct JapaneseEntryView: View {
    let entry: JapaneseEntry
    var compact = false
    var kokugo: Loadable<KokugoEntry?> = .idle
    /// 点击相关词条
    var follow: (String) -> Void = { _ in }
    @State private var showJapaneseDefinitions = true
    @State private var showAllExamples = false
    @State private var showAllKokugo = false

    private let examplesPerSense = 2
    private let kokugoPreviewLines = 8

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if compact {
                briefDefinitions
            } else {
                if !entry.senses.isEmpty { details }
                kokugoSection
                if !entry.related.isEmpty { related }
            }
        }
    }

    // MARK: - 词头

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(entry.headword)
                    .font(.system(size: compact ? 16 : 22, weight: .bold))
                    .textSelection(.enabled)
                if let origin = entry.origin {
                    Text("〈\(origin)〉").font(.system(size: 12)).foregroundStyle(Theme.secondary)
                }
                if !compact {
                    ForEach(entry.examTypes, id: \.self) { Tag(text: $0) }
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let reading = entry.reading {
                    Text(reading).font(.system(size: 14)).textSelection(.enabled)
                }
                if let tone = entry.tone {
                    Text(tone)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.accent)
                        .help("声调（重音核位置）")
                }
                if let romaji = entry.romaji, !compact {
                    Text(romaji).font(.system(size: 11, design: .serif)).italic().foregroundStyle(Theme.secondary)
                }
                SpeakerButton(source: entry.audio)
                if compact, !entry.partOfSpeech.isEmpty { Tag(text: entry.partOfSpeech) }
            }
        }
    }

    /// 简明释义（英语单词的日语译词下方用）
    private var briefDefinitions: some View {
        Text(numbered(entry.senses.prefix(3).map(\.chinese)))
            .font(.system(size: 13))
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func numbered(_ items: [String]) -> String {
        guard items.count > 1 else { return items.first ?? "" }
        return items.enumerated().map { "\(circledNumber($0.offset + 1)) \($0.element)" }.joined(separator: "  ")
    }

    // MARK: - 释义与例句

    private var hasMoreExamples: Bool {
        entry.senses.contains { $0.examples.count > examplesPerSense }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if !entry.partOfSpeech.isEmpty { Tag(text: entry.partOfSpeech) }
                Spacer()
                if entry.senses.contains(where: { !$0.japanese.isEmpty }) {
                    Toggle("日文释义", isOn: $showJapaneseDefinitions)
                        .toggleStyle(.checkbox)
                        .font(.system(size: 11))
                        .controlSize(.small)
                }
            }
            ForEach(Array(entry.senses.enumerated()), id: \.offset) { i, sense in
                senseView(sense, index: i)
            }
            if hasMoreExamples {
                Button(showAllExamples ? "收起例句" : "显示全部例句（\(entry.senses.reduce(0) { $0 + $1.examples.count })）") {
                    showAllExamples.toggle()
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.accent)
                .font(.system(size: 11))
            }
        }
        .padding(.top, 2)
    }

    private func senseView(_ sense: JapaneseEntry.Sense, index i: Int) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(entry.senses.count > 1 ? circledNumber(i + 1) : "•")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.accent)
                Text(sense.chinese)
                    .font(.system(size: 13))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if showJapaneseDefinitions, !sense.japanese.isEmpty {
                NoteText(sense.japanese).padding(.leading, 16)
            }
            ForEach(Array(sense.examples.prefix(showAllExamples ? .max : examplesPerSense).enumerated()), id: \.offset) { _, ex in
                exampleView(ex)
            }
        }
    }

    private func exampleView(_ ex: JapaneseEntry.Example) -> some View {
        HStack(alignment: .top, spacing: 4) {
            VStack(alignment: .leading, spacing: 1) {
                FuriganaText(tokens: ex.tokens, fontSize: 13)
                if !ex.translation.isEmpty { NoteText(ex.translation) }
            }
            Spacer(minLength: 0)
            if let audio = ex.audio { SpeakerButton(source: audio) }
        }
        .padding(.leading, 16)
        .padding(.vertical, 2)
        .overlay(alignment: .leading) {
            Rectangle().fill(Theme.rule).frame(width: 2).padding(.leading, 6)
        }
    }

    // MARK: - 国语辞典

    @ViewBuilder private var kokugoSection: some View {
        switch kokugo {
        case .loading:
            RuleLine()
            HStack(spacing: 6) {
                sectionTitle("国語辞典")
                ProgressView().controlSize(.mini)
            }
        case .loaded(let k?):
            RuleLine()
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    sectionTitle("国語辞典")
                    Text("デジタル大辞泉").font(.system(size: 9)).foregroundStyle(Theme.tertiary)
                }
                Text(k.heading).font(.system(size: 13, weight: .semibold)).textSelection(.enabled)
                ForEach(Array(k.lines.prefix(showAllKokugo ? .max : kokugoPreviewLines).enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.system(size: 12.5))
                        .foregroundStyle(isSenseNumber(line) ? Theme.text : Theme.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.leading, isSubSense(line) ? 12 : 0)
                }
                if k.lines.count > kokugoPreviewLines {
                    Button(showAllKokugo ? "收起" : "展开全部（共 \(k.lines.count) 段）") { showAllKokugo.toggle() }
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.accent)
                        .font(.system(size: 11))
                }
            }
        default:
            EmptyView()
        }
    }

    /// 「１ 物を一方から…」这类义项开头
    private func isSenseNumber(_ line: String) -> Bool {
        line.first.map { $0.isNumber } ?? false
    }

    /// 「㋐…」这类下位义项
    private func isSubSense(_ line: String) -> Bool {
        guard let s = line.unicodeScalars.first else { return false }
        return (0x32D0...0x32FE).contains(s.value)
    }

    // MARK: - 相关词条

    private var related: some View {
        VStack(alignment: .leading, spacing: 4) {
            RuleLine()
            sectionTitle("相关词条")
            FlowLayout(spacing: 12, lineSpacing: 6) {
                ForEach(entry.related, id: \.id) { c in
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(c.spell).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.accent)
                        if let r = c.reading {
                            Text(r).font(.system(size: 11)).foregroundStyle(Theme.secondary)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { follow(c.spell) }
                    .help(c.excerpt.isEmpty ? "查询「\(c.spell)」" : c.excerpt)
                }
            }
        }
    }

    private func sectionTitle(_ s: String) -> some View {
        Text(s).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.secondary)
    }
}
