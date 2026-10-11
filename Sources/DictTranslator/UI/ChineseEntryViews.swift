import SwiftUI

struct ChineseEnglishView: View {
    let entry: ChineseEnglishEntry
    var follow: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let p = entry.pinyin {
                Text("[\(p)]").font(.system(size: 12)).foregroundStyle(Theme.secondary)
            }
            ForEach(Array(entry.items.prefix(8).enumerated()), id: \.offset) { _, item in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        if !item.pos.isEmpty { POSLabel(text: item.pos) }
                        FlowLayout(spacing: 0, lineSpacing: 2) {
                            ForEach(Array(item.words.enumerated()), id: \.offset) { i, w in
                                HStack(spacing: 0) {
                                    LinkWord(word: w, action: follow)
                                    if i < item.words.count - 1 { Text("; ").font(.system(size: 14)).foregroundStyle(Theme.secondary) }
                                }
                            }
                        }
                    }
                    if !item.explanation.isEmpty {
                        NoteText(item.explanation).lineLimit(3)
                    }
                }
            }
        }
    }
}

/// 中文 → 日语：可能的日语对应词，点击查看完整词条
struct ChineseJapaneseView: View {
    let entry: ChineseJapaneseEntry
    var follow: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(entry.candidates, id: \.id) { c in
                VStack(alignment: .leading, spacing: 1) {
                    HStack(alignment: .lastTextBaseline, spacing: 6) {
                        FuriganaText(tokens: tokens(for: c), fontSize: 15, color: Theme.accent)
                        if let tone = c.tone {
                            Text(tone).font(.system(size: 12)).foregroundStyle(Theme.accent)
                        }
                        ForEach(c.tags.prefix(3), id: \.self) { Tag(text: $0) }
                    }
                    if !c.excerpt.isEmpty { NoteText(c.excerpt).lineLimit(2) }
                }
                .contentShape(Rectangle())
                .onTapGesture { follow(c.spell) }
                .help("查看「\(c.spell)」的完整词条")
            }
        }
    }

    private func tokens(for c: JapaneseCandidate) -> [RubyToken] {
        guard let r = c.reading, !r.contains(" ") else { return [RubyToken(surface: c.spell, reading: nil)] }
        return FuriganaService.splitOkurigana(surface: c.spell, reading: r)
    }
}
