import SwiftUI
import AppKit

/// 统一的低饱和配色，浅色 / 深色模式分别取值，保证对比度
enum Theme {
    private static func dynamic(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        })
    }

    static func hex(_ v: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255,
                green: CGFloat((v >> 8) & 0xFF) / 255,
                blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }

    /// 主强调色：可点击的词、发音按钮、序号（灰蓝）
    static let accent = dynamic(light: hex(0x3E5C82), dark: hex(0xA9BCD6))
    /// 词性（英语 v. n. 等）：低饱和的赭石色
    static let pos = dynamic(light: hex(0x8A6A3F), dark: hex(0xCDB894))
    /// 正文
    static let text = dynamic(light: hex(0x1F2328), dark: hex(0xE6E6E3))
    /// 次要文字（释义补充、译文）
    static let secondary = dynamic(light: hex(0x5C6370), dark: hex(0xA3A7AD))
    /// 更弱的文字（来源、标签说明）
    static let tertiary = dynamic(light: hex(0x8B9099), dark: hex(0x7D828A))
    /// 标签的文字与底色
    static let tagText = dynamic(light: hex(0x4A4F57), dark: hex(0xC4C7CC))
    static let tagFill = dynamic(light: NSColor.black.withAlphaComponent(0.06), dark: NSColor.white.withAlphaComponent(0.09))
    /// 卡片底色与分隔
    static let cardFill = dynamic(light: NSColor.black.withAlphaComponent(0.035), dark: NSColor.white.withAlphaComponent(0.05))
    static let rule = dynamic(light: NSColor.black.withAlphaComponent(0.12), dark: NSColor.white.withAlphaComponent(0.16))
    /// 面板底色（叠在毛玻璃上，降低透明度提高可读性）
    static let panelTint = dynamic(light: hex(0xF7F7F5).withAlphaComponent(0.88), dark: hex(0x1E1F22).withAlphaComponent(0.9))
    /// 划词小图标
    static let iconFill = hex(0x4A6489)
}
