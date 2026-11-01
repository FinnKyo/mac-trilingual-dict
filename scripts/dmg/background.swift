// 生成 DMG 窗口背景：两个图标位之间的箭头和「拖到应用程序」提示（低饱和配色，与 App 一致）。
// 用法: background <输出目录>  → background.png（1x）、background@2x.png
import AppKit

let W: CGFloat = 600, H: CGFloat = 380

func color(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

func render(scale: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W * scale), pixelsHigh: Int(H * scale), bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: W, height: H)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    // 坐标原点在左下
    NSGradient(starting: color(0xF1F3F6), ending: color(0xE3E9F0))!.draw(in: NSRect(x: 0, y: 0, width: W, height: H), angle: 90)

    // 两个图标中心在 (150, 190) 和 (450, 190)（Finder 坐标自上而下，这里换算成自下而上）
    let y = H - 190
    let arrow = NSBezierPath()
    arrow.move(to: NSPoint(x: 245, y: y))
    arrow.line(to: NSPoint(x: 338, y: y))   // 不伸进箭头：半透明叠在一起会出现深色点
    arrow.lineWidth = 3
    arrow.lineCapStyle = .round
    color(0x3E5C82, 0.55).setStroke()
    arrow.stroke()
    let head = NSBezierPath()
    head.move(to: NSPoint(x: 355, y: y))
    head.line(to: NSPoint(x: 340, y: y + 9))
    head.line(to: NSPoint(x: 340, y: y - 9))
    head.close()
    color(0x3E5C82, 0.55).setFill()
    head.fill()

    let title = NSAttributedString(string: "将 DictTranslator 拖到「应用程序」文件夹", attributes: [
        .font: NSFont.systemFont(ofSize: 15, weight: .medium), .foregroundColor: color(0x3A3F47),
    ])
    title.draw(at: NSPoint(x: (W - title.size().width) / 2, y: 62))
    let note = NSAttributedString(string: "首次打开如提示无法验证开发者，请在「系统设置 › 隐私与安全性」中点击「仍要打开」", attributes: [
        .font: NSFont.systemFont(ofSize: 11), .foregroundColor: color(0x6B7078),
    ])
    note.draw(at: NSPoint(x: (W - note.size().width) / 2, y: 38))
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let out = CommandLine.arguments[1]
for (scale, name) in [(1.0, "background.png"), (2.0, "background@2x.png")] as [(CGFloat, String)] {
    try! render(scale: scale).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(out)/\(name)"))
}
