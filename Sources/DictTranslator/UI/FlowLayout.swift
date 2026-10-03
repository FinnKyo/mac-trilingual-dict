import SwiftUI

/// 自动换行的横向排布
struct FlowLayout: Layout {
    var spacing: CGFloat = 0
    var lineSpacing: CGFloat = 2

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0, widest: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0, x + s.width > maxWidth {
                y += lineHeight + lineSpacing
                x = 0
                lineHeight = 0
            }
            x += s.width + spacing
            widest = max(widest, x - spacing)
            lineHeight = max(lineHeight, s.height)
        }
        return CGSize(width: min(widest, maxWidth), height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, lineHeight: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > bounds.minX, x + s.width > bounds.maxX {
                y += lineHeight + lineSpacing
                x = bounds.minX
                lineHeight = 0
            }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            lineHeight = max(lineHeight, s.height)
        }
    }
}

/// 带假名注音的日文（汉字上方显示读音）
struct FuriganaText: View {
    let tokens: [RubyToken]
    var fontSize: CGFloat = 15
    var color: Color = Theme.text
    var showReading = true

    private struct Unit: Identifiable {
        let id: Int
        let surface: String
        let reading: String?
    }

    /// 无注音的部分拆成单字（英文单词保持完整），以便自然换行
    /// 不能出现在行首的标点（日文禁则），与前一个字合并以便一起换行
    private static let noLineStart = Set("。、，．,.！？!?」』）)】〉》…ー〜っゃゅょァィゥェォッャュョ・：；:;")

    private var units: [Unit] {
        var out: [Unit] = []
        var i = 0
        func appendToPrevious(_ ch: Character) -> Bool {
            guard Self.noLineStart.contains(ch), let last = out.last else { return false }
            out[out.count - 1] = Unit(id: last.id, surface: last.surface + String(ch), reading: last.reading)
            return true
        }
        for t in tokens {
            if let r = t.reading, showReading {
                out.append(Unit(id: i, surface: t.surface, reading: r)); i += 1
            } else {
                var latinRun = ""
                for ch in t.surface {
                    if ch.unicodeScalars.allSatisfy({ LanguageDetector.isLatinLetter($0) || ($0.value >= 0x30 && $0.value <= 0x39) }) {
                        latinRun.append(ch)
                    } else {
                        if !latinRun.isEmpty { out.append(Unit(id: i, surface: latinRun, reading: nil)); i += 1; latinRun = "" }
                        if appendToPrevious(ch) { continue }
                        out.append(Unit(id: i, surface: String(ch), reading: nil)); i += 1
                    }
                }
                if !latinRun.isEmpty { out.append(Unit(id: i, surface: latinRun, reading: nil)); i += 1 }
            }
        }
        return out
    }

    /// 读音明显比汉字宽时（如「承(うけたまわ)」）预留部分宽度，避免与相邻注音重叠
    private func minWidth(for u: Unit, rubySize: CGFloat) -> CGFloat {
        guard let r = u.reading else { return 0 }
        let readingWidth = CGFloat(r.count) * rubySize
        return max(0, readingWidth - fontSize * 0.8)
    }

    var body: some View {
        let rubySize = max(fontSize * 0.55, 8)
        FlowLayout(spacing: 0, lineSpacing: 2) {
            ForEach(units) { u in
                VStack(spacing: 0) {
                    // 读音不决定宽度，允许略微伸出汉字两侧（与辞书排版一致）
                    Text(u.reading ?? " ")
                        .font(.system(size: rubySize))
                        .foregroundStyle(Theme.secondary)
                        .opacity(u.reading == nil ? 0 : 1)
                        .fixedSize()
                        .frame(width: 0)
                    Text(u.surface)
                        .font(.system(size: fontSize))
                        .foregroundStyle(color)
                        .fixedSize()
                }
                .frame(minWidth: minWidth(for: u, rubySize: rubySize))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tokens.map(\.surface).joined())
    }
}
