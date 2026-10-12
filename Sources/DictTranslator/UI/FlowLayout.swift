import SwiftUI
import AppKit

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
    /// 点击句子中的实词时，传入它的原形（「行った」→「行く」）；nil 时不可点击
    var onWordTap: ((String) -> Void)? = nil

    /// 按换行符把注音片段拆成多行（换行只会出现在无注音的片段里）
    private var lines: [[RubyToken]] {
        var out: [[RubyToken]] = [[]]
        for t in tokens {
            guard t.reading == nil, t.surface.contains("\n") else { out[out.count - 1].append(t); continue }
            for (i, part) in t.surface.components(separatedBy: "\n").enumerated() {
                if i > 0 { out.append([]) }
                if !part.isEmpty { out[out.count - 1].append(RubyToken(surface: part, reading: nil, lemma: t.lemma, word: t.word)) }
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
                    FuriganaLine(tokens: lines[i], fontSize: fontSize, color: color, showReading: showReading, onWordTap: onWordTap)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tokens.map(\.surface).joined())
    }
}

/// 单行（自动折行）的注音文本
private struct FuriganaLine: View {
    let fontSize: CGFloat
    let color: Color
    let onWordTap: ((String) -> Void)?
    /// 在 init 里算好：悬停改变 hoveredWord 时只重绘，不重新拆分和测量
    private let units: [Unit]
    @State private var hoveredWord: Int?

    private var rubySize: CGFloat { Self.rubySize(fontSize) }
    private static func rubySize(_ fontSize: CGFloat) -> CGFloat { max(fontSize * 0.55, 8) }

    init(tokens: [RubyToken], fontSize: CGFloat, color: Color, showReading: Bool, onWordTap: ((String) -> Void)?) {
        self.fontSize = fontSize
        self.color = color
        self.onWordTap = onWordTap
        var units = Self.makeUnits(tokens, showReading: showReading)
        Self.layoutRuby(&units, fontSize: fontSize)
        self.units = units
    }

    private struct Unit: Identifiable {
        let id: Int
        var surface: String
        let reading: String?
        let lemma: String?
        let word: Int?
        /// 为避免行首禁则并进来的、属于下一个词或不属于任何词的标点，不随单词高亮
        var trailing = ""
        /// 读音比正文宽、需要加宽时的宽度
        var width: CGFloat?
        /// 读音的水平偏移
        var rubyOffset: CGFloat = 0
    }

    /// 无注音的部分拆成单字（英文单词保持完整），以便自然换行
    /// 不能出现在行首的标点（日文禁则），与前一个字合并以便一起换行
    private static let noLineStart = Set("。、，．,.！？!?」』）)】〉》…ー〜っゃゅょァィゥェォッャュョ・：；:;")

    private static func makeUnits(_ tokens: [RubyToken], showReading: Bool) -> [Unit] {
        var out: [Unit] = []
        for t in tokens {
            func add(_ surface: String, reading: String? = nil) {
                out.append(Unit(id: out.count, surface: surface, reading: reading, lemma: t.lemma, word: t.word))
            }
            if let r = t.reading, showReading {
                add(t.surface, reading: r)
                continue
            }
            var latinRun = ""
            for ch in t.surface {
                if ch.unicodeScalars.allSatisfy({ LanguageDetector.isLatinLetter($0) || ($0.value >= 0x30 && $0.value <= 0x39) }) {
                    latinRun.append(ch)
                    continue
                }
                if !latinRun.isEmpty { add(latinRun); latinRun = "" }
                if noLineStart.contains(ch), let last = out.last {
                    if last.word == t.word, last.trailing.isEmpty {
                        out[out.count - 1].surface.append(ch)
                    } else {
                        out[out.count - 1].trailing.append(ch)
                    }
                } else {
                    add(String(ch))
                }
            }
            if !latinRun.isEmpty { add(latinRun) }
        }
        return out
    }

    /// 读音比正文宽时怎么摆：旁边是不带注音的字，读音可以伸到它上方（最多半个字，否则「月給で」会显示成「月給 で」）；
    /// 旁边也有注音时不能伸过去，并留一点间隙，否则两边的读音会连成一串（「一日中雨」的 いちにちじゅうあめ）。
    /// 两边都没有注音时按辞书排版直接伸出两侧，不加宽
    private static func layoutRuby(_ units: inout [Unit], fontSize: CGFloat) {
        let rubyFont = NSFont.systemFont(ofSize: rubySize(fontSize))
        let bodyFont = NSFont.systemFont(ofSize: fontSize)
        // 实际量出宽度（按字数估算会偏宽，汉字之间出现空隙）
        func measure(_ s: String, _ font: NSFont) -> CGFloat { ceil((s as NSString).size(withAttributes: [.font: font]).width) }
        let gap = rubySize(fontSize) * 0.25
        for i in units.indices {
            guard let r = units[i].reading else { continue }
            let leftFree = i == 0 || units[i - 1].reading == nil
            let rightFree = i + 1 >= units.count || units[i + 1].reading == nil
            if leftFree && rightFree { continue }
            let bodyWidth = measure(units[i].surface + units[i].trailing, bodyFont)
            // 读音允许超出正文框的距离；负数表示要往里收
            let left = leftFree ? fontSize * 0.5 : -gap / 2
            let right = rightFree ? fontSize * 0.5 : -gap / 2
            let width = measure(r, rubyFont) - left - right
            if width > bodyWidth {
                units[i].width = width
                units[i].rubyOffset = (right - left) / 2
            }
        }
    }

    var body: some View {
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
                        .offset(x: u.rubyOffset)
                    HStack(spacing: 0) {
                        let hovered = u.word != nil && u.word == hoveredWord
                        Text(u.surface)
                            .foregroundStyle(hovered ? Theme.accent : color)
                            .underline(hovered)
                        if !u.trailing.isEmpty {
                            Text(u.trailing).foregroundStyle(color)
                        }
                    }
                    .font(.system(size: fontSize))
                    .fixedSize()
                }
                // 基线取正文的，而不是上方注音的
                .alignmentGuide(.firstTextBaseline) { $0[.lastTextBaseline] }
                .frame(minWidth: u.width)
                .modifier(WordTap(unit: u, onTap: onWordTap, hoveredWord: $hoveredWord))
            }
        }
    }

    /// 实词可点击：悬停时整个词（含送假名）一起高亮
    private struct WordTap: ViewModifier {
        let unit: Unit
        let onTap: ((String) -> Void)?
        @Binding var hoveredWord: Int?

        func body(content: Content) -> some View {
            if let onTap, let lemma = unit.lemma, let word = unit.word {
                content
                    .contentShape(Rectangle())
                    .onHover { inside in
                        if inside { hoveredWord = word } else if hoveredWord == word { hoveredWord = nil }
                    }
                    .onTapGesture { onTap(lemma) }
                    .help("查询「\(lemma)」")
            } else {
                content
            }
        }
    }
}
