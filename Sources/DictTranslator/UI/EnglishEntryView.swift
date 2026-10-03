import SwiftUI

struct EnglishEntryView: View {
    let entry: EnglishEntry
    var compact = false
    var follow: (String) -> Void = { _ in }
    @State private var showAllPhrases = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(entry.word)
                    .font(.system(size: compact ? 16 : 22, weight: .bold))
                    .textSelection(.enabled)
                if !compact {
                    ForEach(entry.examTypes.prefix(6), id: \.self) { Tag(text: $0) }
                }
            }

            phonetics

            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(entry.definitions.prefix(compact ? 3 : 20).enumerated()), id: \.offset) { _, d in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        if !d.pos.isEmpty { POSLabel(text: d.pos) }
                        Text(d.text)
                            .font(.system(size: 13))
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if !entry.webTranslations.isEmpty {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Tag(text: "网络")
                        Text(entry.webTranslations.joined(separator: "；"))
                            .font(.system(size: 13))
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            if !compact {
                if !entry.wordForms.isEmpty { wordForms }
                if !entry.phrases.isEmpty { phrases }
                if !entry.sentences.isEmpty { sentences }
            }
        }
    }

    @ViewBuilder private var phonetics: some View {
        let uk = entry.ukPhone.flatMap { $0.isEmpty ? nil : $0 }
        let us = entry.usPhone.flatMap { $0.isEmpty ? nil : $0 }
        if uk != nil || us != nil {
            HStack(spacing: 14) {
                if let uk { phoneItem(label: "英", phone: uk, american: false) }
                if let us { phoneItem(label: "美", phone: us, american: true) }
            }
        } else if entry.word.split(separator: " ").count <= 3 {
            HStack(spacing: 14) {
                SpeakerButton(label: "英", url: YoudaoDictService.englishAudioURL(entry.word, american: false))
                SpeakerButton(label: "美", url: YoudaoDictService.englishAudioURL(entry.word, american: true))
            }
        }
    }

    private func phoneItem(label: String, phone: String, american: Bool) -> some View {
        HStack(spacing: 4) {
            Text(label).font(.system(size: 11)).foregroundStyle(Theme.secondary)
            Text("/\(phone)/")
                .font(.system(size: 13, design: .serif))
                .textSelection(.enabled)
            SpeakerButton(label: nil, url: YoudaoDictService.englishAudioURL(entry.word, american: american))
        }
    }

    private var wordForms: some View {
        FlowLayout(spacing: 10, lineSpacing: 4) {
            ForEach(entry.wordForms, id: \.self) { f in
                HStack(spacing: 3) {
                    Text(f.name).font(.system(size: 11)).foregroundStyle(Theme.secondary)
                    Text(f.value)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.accent)
                        .onTapGesture { follow(f.value) }
                        .help("查询「\(f.value)」")
                }
            }
        }
        .padding(.top, 2)
    }

    private var phrases: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("短语").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.secondary)
            let list = showAllPhrases ? entry.phrases : Array(entry.phrases.prefix(4))
            ForEach(list, id: \.self) { p in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(p.phrase)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.accent)
                        .onTapGesture { follow(p.phrase) }
                        .fixedSize()
                    NoteText(p.meaning)
                }
            }
            if entry.phrases.count > 4 {
                Button(showAllPhrases ? "收起" : "更多短语（\(entry.phrases.count)）") { showAllPhrases.toggle() }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.accent)
                    .font(.system(size: 11))
            }
        }
        .padding(.top, 2)
    }

    private var sentences: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("双语例句").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.secondary)
            ForEach(Array(entry.sentences.prefix(3).enumerated()), id: \.offset) { i, s in
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(i + 1). \(s.english)")
                        .font(.system(size: 12))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    NoteText(s.chinese).padding(.leading, 14)
                }
            }
        }
        .padding(.top, 2)
    }
}
