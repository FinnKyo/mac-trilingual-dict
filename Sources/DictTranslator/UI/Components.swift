import SwiftUI
import AppKit

enum Pasteboard {
    static func copy(_ s: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
    }
}

struct SectionCard<Content: View>: View {
    let title: String
    var badge: String? = nil
    var trailing: AnyView? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.secondary)
                if let badge {
                    Text(badge)
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.tertiary)
                }
                Spacer(minLength: 0)
                if let trailing { trailing }
            }
            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.cardFill))
    }
}

/// 区块内的细分隔线
struct RuleLine: View {
    var body: some View {
        Rectangle().fill(Theme.rule).frame(height: 0.5).padding(.vertical, 3)
    }
}

/// 次要说明文字（释义的补充、例句译文），可选中复制
struct NoteText: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(Theme.secondary)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct Tag: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(Theme.tagText)
            .background(RoundedRectangle(cornerRadius: 4).fill(Theme.tagFill))
            .fixedSize()
    }
}

struct POSLabel: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .serif))
            .italic()
            .foregroundStyle(Theme.pos)
            .fixedSize()
    }
}

struct IconButton: View {
    let systemName: String
    var help: String = ""
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .medium))
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
                .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(hovering ? 0.1 : 0)))
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.secondary)
        .help(help)
        .onHover { hovering = $0 }
    }
}

struct SpeakerButton: View {
    let label: String?
    let url: URL?

    var body: some View {
        Button {
            AudioPlayer.shared.play(url)
        } label: {
            HStack(spacing: 2) {
                if let label { Text(label).font(.system(size: 10)).foregroundStyle(Theme.secondary) }
                Image(systemName: "speaker.wave.2.fill").font(.system(size: 10))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.accent)
        .help("发音")
    }
}

struct LoadingRow: View {
    var body: some View {
        HStack(spacing: 6) {
            ProgressView().controlSize(.small)
            Text("查询中…").font(.system(size: 12)).foregroundStyle(Theme.secondary)
        }
    }
}

struct ErrorRow: View {
    let message: String
    var retry: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle").foregroundStyle(Theme.secondary).font(.system(size: 11))
            Text(message).font(.system(size: 12)).foregroundStyle(Theme.secondary).textSelection(.enabled)
            Spacer(minLength: 0)
            if let retry {
                Button("重试", action: retry).controlSize(.small)
            }
        }
    }
}

/// 可点击查词的单词
struct LinkWord: View {
    let word: String
    let action: (String) -> Void
    @State private var hovering = false

    var body: some View {
        Text(word)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(Theme.accent)
            .underline(hovering)
            .onHover { hovering = $0 }
            .onTapGesture { action(word) }
            .help("查询「\(word)」")
    }
}
