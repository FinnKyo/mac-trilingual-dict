import SwiftUI

/// 自动换行的横向排布
struct FlowLayout: Layout {
    var spacing: CGFloat = 0
    var lineSpacing: CGFloat = 2

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(subviews, maxWidth: proposal.width ?? .infinity).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let offsets = arrange(subviews, maxWidth: bounds.width).offsets
        for (v, p) in zip(subviews, offsets) {
            v.place(at: CGPoint(x: bounds.minX + p.x, y: bounds.minY + p.y), proposal: ProposedViewSize(v.sizeThatFits(.unspecified)))
        }
    }

    /// 基线取首行第一个 / 末行最后一个子视图的，和同一行的其他文字对齐
    func explicitAlignment(of guide: VerticalAlignment, in bounds: CGRect, proposal: ProposedViewSize,
                           subviews: Subviews, cache: inout ()) -> CGFloat? {
        guard guide == .firstTextBaseline || guide == .lastTextBaseline, !subviews.isEmpty else { return nil }
        let offsets = arrange(subviews, maxWidth: bounds.width).offsets
        let i = guide == .firstTextBaseline ? 0 : subviews.count - 1
        return bounds.minY + offsets[i].y + subviews[i].dimensions(in: .unspecified)[guide]
    }

    /// 逐个从左往右排，放不下就换行；返回每个子视图相对左上角的位置和整体大小
    private func arrange(_ subviews: Subviews, maxWidth: CGFloat) -> (offsets: [CGPoint], size: CGSize) {
        var offsets: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0, widest: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0, x + s.width > maxWidth {
                y += lineHeight + lineSpacing
                x = 0
                lineHeight = 0
            }
            offsets.append(CGPoint(x: x, y: y))
            x += s.width + spacing
            widest = max(widest, x - spacing)
            lineHeight = max(lineHeight, s.height)
        }
        return (offsets, CGSize(width: min(widest, maxWidth), height: y + lineHeight))
    }
}

/// 带假名注音的日文（汉字上方显示读音），保留原文换行和空行
struct FuriganaText: View {
    let tokens: [RubyToken]
    var fontSize: CGFloat = 15
    var color: Color = Theme.text
    var showReading = true

    /// 按换行符把注音片段拆成多行（换行只会出现在无注音的片段里）
    private var lines: [[RubyToken]] {
        var out: [[RubyToken]] = [[]]
        for t in tokens {
            guard t.reading == nil, t.surface.contains("\n") else { out[out.count - 1].append(t); continue }
            for (i, part) in t.surface.components(separatedBy: "\n").enumerated() {
                if i > 0 { out.append([]) }
                if !part.isEmpty { out[out.count - 1].append(RubyToken(surface: part, reading: nil)) }
            }
        }
        return out
    }

    var body: some View {
        let lines = self.lines
        VStack(alignment: .leading, spacing: 2) {
            ForEach(lines.indices, id: \.self) { i in
                if lines[i].isEmpty {
                    // 空行：高度与一行正文相同
                    Text(" ").font(.system(size: fontSize))
                } else {
                    FuriganaLine(tokens: lines[i], fontSize: fontSize, color: color, showReading: showReading)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tokens.map(\.surface).joined())
    }
}

/// 单行（自动折行）的注音文本
private struct FuriganaLine: View {
    let tokens: [RubyToken]
    let fontSize: CGFloat
    let color: Color
    let showReading: Bool

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

    /// 读音明显比汉字宽时（如「承(うけたまわ)」）预留部分宽度，避免与相邻的注音重叠。
    /// 旁边是不带注音的字时读音可以直接伸到它上方，不预留（否则「月給で」会显示成「月給 で」）
    private func minWidth(at i: Int, in units: [Unit], rubySize: CGFloat) -> CGFloat {
        guard let r = units[i].reading else { return 0 }
        let neighborHasRuby = (i > 0 && units[i - 1].reading != nil) || (i + 1 < units.count && units[i + 1].reading != nil)
        guard neighborHasRuby else { return 0 }
        let readingWidth = CGFloat(r.count) * rubySize
        return max(0, readingWidth - fontSize * 0.8)
    }

    var body: some View {
        let rubySize = max(fontSize * 0.55, 8)
        let units = self.units
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
                // 基线取正文的，而不是上方注音的
                .alignmentGuide(.firstTextBaseline) { $0[.lastTextBaseline] }
                .frame(minWidth: minWidth(at: u.id, in: units, rubySize: rubySize))
            }
        }
    }
}
