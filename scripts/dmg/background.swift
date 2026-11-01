// 生成 DMG 窗口背景：上方两个图标位之间的拖动箭头，下方是分步安装引导（首次打开的「仍要打开」、授权）。
// 收到 DMG 的人不一定看过 README，安装步骤要直接写在窗口里。
// 用法: background <输出目录>  → background.png（1x）、background@2x.png
import AppKit

/// 窗口内容区大小，与 package.sh 里的窗口尺寸、图标位置对应
let W: CGFloat = 640, H: CGFloat = 520
/// 图标中心的 y（自上而下，与 Finder 坐标一致）
let iconY: CGFloat = 130

func color(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

let accent = color(0x3E5C82)
let textColor = color(0x2B2F36)
let secondary = color(0x6B7078)

func attributed(_ s: String, size: CGFloat, weight: NSFont.Weight = .regular, color c: NSColor = textColor,
                bold: [String] = [], mono: Bool = false) -> NSAttributedString {
    let font = mono ? NSFont.monospacedSystemFont(ofSize: size, weight: weight) : NSFont.systemFont(ofSize: size, weight: weight)
    let style = NSMutableParagraphStyle()
    style.lineSpacing = 3
    let a = NSMutableAttributedString(string: s, attributes: [.font: font, .foregroundColor: c, .paragraphStyle: style])
    for b in bold {
        let r = (s as NSString).range(of: b)
        if r.location != NSNotFound { a.addAttributes([.font: NSFont.systemFont(ofSize: size, weight: .semibold), .foregroundColor: textColor], range: r) }
    }
    return a
}

func render(scale: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W * scale), pixelsHigh: Int(H * scale), bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: W, height: H)
    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = ctx
    // 换成左上角为原点，和 Finder 的图标坐标一致
    let flip = NSAffineTransform()
    flip.translateX(by: 0, yBy: H)
    flip.scaleX(by: 1, yBy: -1)
    flip.concat()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx.cgContext, flipped: true)

    NSGradient(starting: color(0xF3F5F8), ending: color(0xE4EAF1))!.draw(in: NSRect(x: 0, y: 0, width: W, height: H), angle: -90)

    // 两个图标（中心 x = 170 / 470）之间的箭头
    let arrow = NSBezierPath()
    arrow.move(to: NSPoint(x: 262, y: iconY))
    arrow.line(to: NSPoint(x: 366, y: iconY))
    arrow.lineWidth = 3
    arrow.lineCapStyle = .round
    accent.withAlphaComponent(0.55).setStroke()
    arrow.stroke()
    let head = NSBezierPath()
    head.move(to: NSPoint(x: 380, y: iconY))
    head.line(to: NSPoint(x: 364, y: iconY - 9))
    head.line(to: NSPoint(x: 364, y: iconY + 9))
    head.close()
    accent.withAlphaComponent(0.55).setFill()
    head.fill()

    // 安装引导卡片
    let card = NSRect(x: 28, y: 236, width: W - 56, height: 262)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowBlurRadius = 10
    shadow.shadowOffset = NSSize(width: 0, height: 2)
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.08)
    shadow.set()
    NSColor.white.withAlphaComponent(0.85).setFill()
    NSBezierPath(roundedRect: card, xRadius: 12, yRadius: 12).fill()
    NSGraphicsContext.restoreGraphicsState()

    attributed("安装步骤", size: 14, weight: .semibold).draw(at: NSPoint(x: card.minX + 20, y: card.minY + 16))

    let steps: [(String, [String])] = [
        ("把上方左边的 DictTranslator 拖到右边的「应用程序」文件夹", ["DictTranslator", "「应用程序」"]),
        ("打开「应用程序」里的 DictTranslator。如果提示「无法验证开发者」或「已损坏」，先点「完成」或「取消」——文件没有问题，只是没有经过 Apple 公证",
         ["「完成」", "「取消」"]),
        ("打开「系统设置 › 隐私与安全性」，滚到页面最底部，点击「仍要打开」，按提示输入密码确认。之后就能正常打开了",
         ["「系统设置 › 隐私与安全性」", "「仍要打开」"]),
        ("按 App 的引导授予「辅助功能」（划词翻译）和「屏幕与系统音频录制」（截图翻译）权限", ["「辅助功能」", "「屏幕与系统音频录制」"]),
    ]
    var y = card.minY + 46
    let textX = card.minX + 50
    let textWidth = card.maxX - 20 - textX
    for (i, (s, bold)) in steps.enumerated() {
        let badge = NSRect(x: card.minX + 20, y: y + 1, width: 20, height: 20)
        accent.setFill()
        NSBezierPath(ovalIn: badge).fill()
        let n = attributed("\(i + 1)", size: 11.5, weight: .bold, color: .white)
        n.draw(at: NSPoint(x: badge.midX - n.size().width / 2, y: badge.midY - n.size().height / 2))
        let t = attributed(s, size: 12.5, color: secondary, bold: bold)
        let h = ceil(t.boundingRect(with: NSSize(width: textWidth, height: 200), options: [.usesLineFragmentOrigin]).height)
        t.draw(with: NSRect(x: textX, y: y + 2, width: textWidth, height: h), options: [.usesLineFragmentOrigin])
        y += max(h, 20) + 12
    }

    let tip = attributed("仍然打不开时，可在「终端」中运行：", size: 11, color: secondary)
    tip.draw(at: NSPoint(x: textX, y: card.maxY - 40))
    attributed("xattr -dr com.apple.quarantine /Applications/DictTranslator.app", size: 11, weight: .medium, color: accent, mono: true)
        .draw(at: NSPoint(x: textX, y: card.maxY - 24))

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let out = CommandLine.arguments[1]
for (scale, name) in [(1.0, "background.png"), (2.0, "background@2x.png")] as [(CGFloat, String)] {
    try! render(scale: scale).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(out)/\(name)"))
}
