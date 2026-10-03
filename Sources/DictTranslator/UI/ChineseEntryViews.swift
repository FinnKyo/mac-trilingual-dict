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

struct ChineseJapaneseView: View {
    let entry: ChineseJapaneseEntry
    var follow: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            FlowLayout(spacing: 12, lineSpacing: 6) {
                ForEach(entry.words, id: \.self) { w in
                    FuriganaText(tokens: FuriganaService.tokens(for: w), fontSize: 15, color: Theme.accent)
                        .contentShape(Rectangle())
                        .onTapGesture { follow(w) }
                        .help("查询「\(w)」")
                }
            }
            if !entry.examples.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("例句").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.secondary)
                    ForEach(Array(entry.examples.enumerated()), id: \.offset) { _, ex in
                        VStack(alignment: .leading, spacing: 1) {
                            FuriganaText(tokens: ex.japaneseTokens, fontSize: 13)
                            NoteText(ex.chinese)
                        }
                    }
                }
            }
        }
    }
}
