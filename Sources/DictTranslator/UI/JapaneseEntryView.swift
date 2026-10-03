import SwiftUI

struct JapaneseEntryView: View {
    let entry: JapaneseEntry
    var compact = false
    @State private var showJapaneseDefinitions = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if !entry.brief.isEmpty { briefDefinitions }
            if !compact, !entry.senses.isEmpty { details }
            if compact, entry.brief.isEmpty, let first = entry.senses.first?.meanings.first {
                Text(first.chinese).font(.system(size: 13)).textSelection(.enabled)
            }
        }
    }

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
                if let kana = entry.hiragana, entry.readingDiffersFromHeadword {
                    Text(kana).font(.system(size: 14)).textSelection(.enabled)
                }
                if let kata = entry.katakana, kata != entry.headword, !compact {
                    Text(kata).font(.system(size: 12)).foregroundStyle(Theme.secondary)
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
                SpeakerButton(label: nil, url: YoudaoDictService.japaneseAudioURL(entry.audioText))
            }
        }
    }

    private var briefDefinitions: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(Array(entry.brief.prefix(compact ? 2 : 10).enumerated()), id: \.offset) { _, b in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if !b.pos.isEmpty { Tag(text: b.pos) }
                    Text(numbered(b.meanings))
                        .font(.system(size: 13))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func numbered(_ items: [String]) -> String {
        guard items.count > 1 else { return items.first ?? "" }
        return items.enumerated().map { "\(YoudaoDictService.circled($0.offset + 1)) \($0.element)" }.joined(separator: "  ")
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("详细释义").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.secondary)
                Spacer()
                Toggle("日文释义", isOn: $showJapaneseDefinitions)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 11))
                    .controlSize(.small)
            }
            ForEach(Array(entry.senses.enumerated()), id: \.offset) { _, sense in
                senseView(sense)
            }
        }
        .padding(.top, 2)
    }

    private func senseView(_ sense: JapaneseEntry.Sense) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if !sense.category.isEmpty { Tag(text: sense.category) }
            ForEach(Array(sense.meanings.enumerated()), id: \.offset) { i, m in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(sense.meanings.count > 1 ? YoudaoDictService.circled(i + 1) : "•")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.accent)
                        Text(m.chinese.isEmpty ? m.japanese : m.chinese)
                            .font(.system(size: 13))
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if showJapaneseDefinitions, !m.japanese.isEmpty, !m.chinese.isEmpty {
                        Text(m.japanese)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.secondary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.leading, 16)
                    }
                    ForEach(Array(m.examples.prefix(2).enumerated()), id: \.offset) { _, ex in
                        VStack(alignment: .leading, spacing: 1) {
                            FuriganaText(tokens: ex.tokens, fontSize: 13)
                            if !ex.translation.isEmpty {
                                Text(ex.translation)
                                    .font(.system(size: 12))
                                    .foregroundStyle(Theme.secondary)
                                    .textSelection(.enabled)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(.leading, 16)
                        .padding(.vertical, 2)
                        .overlay(alignment: .leading) {
                            Rectangle().fill(Theme.rule).frame(width: 2).padding(.leading, 6)
                        }
                    }
                }
            }
        }
    }
}
