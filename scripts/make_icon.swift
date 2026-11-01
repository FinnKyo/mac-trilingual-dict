// 生成 App 图标：swift scripts/make_icon.swift Resources/AppIcon.icns [预览.png]
//
// 靛蓝（藍色）底上一个米白色明朝体「辞」，右下角朱印「典」，合起来是「辞典」。
// 外形和尺寸按 macOS 图标网格：1024 画布里 824 的连续圆角主体，带投影
import AppKit

func color(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

/// 连续圆角外形（超椭圆）
func squircle(_ r: NSRect, n: CGFloat = 4.4) -> NSBezierPath {
    let p = NSBezierPath()
    let a = r.width / 2, b = r.height / 2
    for i in 0...720 {
        let t = CGFloat(i) / 720 * 2 * .pi
        let c = cos(t), s = sin(t)
        let pt = NSPoint(x: r.midX + a * (c >= 0 ? 1 : -1) * pow(abs(c), 2 / n),
                         y: r.midY + b * (s >= 0 ? 1 : -1) * pow(abs(s), 2 / n))
        i == 0 ? p.move(to: pt) : p.line(to: pt)
    }
    p.close()
    return p
}

/// 按字形的实际轮廓居中绘制（按行高居中时汉字会偏上）
func glyph(_ s: String, font: String, size: CGFloat, color c: NSColor, center: NSPoint) {
    let cg = NSGraphicsContext.current!.cgContext
    let str = NSAttributedString(string: s, attributes: [.font: NSFont(name: font, size: size)!, .foregroundColor: c])
    let line = CTLineCreateWithAttributedString(str)
    cg.textPosition = .zero   // 上一次绘制后的位置会影响轮廓的计算
    let bounds = CTLineGetImageBounds(line, cg)
    cg.textPosition = CGPoint(x: center.x - bounds.midX, y: center.y - bounds.midY)
    CTLineDraw(line, cg)
}

func render(_ px: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current!.cgContext.scaleBy(x: CGFloat(px) / 1024, y: CGFloat(px) / 1024)

    let body = NSRect(x: 100, y: 100, width: 824, height: 824)
    let shape = squircle(body)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowBlurRadius = 28
    shadow.shadowOffset = NSSize(width: 0, height: -12)
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
    shadow.set()
    color(0x1B2742).setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    shape.addClip()
    NSGradient(starting: color(0x34476E), ending: color(0x1B2742))!.draw(in: body, angle: -90)
    NSGradient(starting: color(0xFFFFFF, 0.10), ending: color(0xFFFFFF, 0))!.draw(in: NSRect(x: 100, y: 524, width: 824, height: 400), angle: -90)
    glyph("辞", font: "YuMin-Extrabold", size: 470, color: color(0xF4EEE2), center: NSPoint(x: 478, y: 548))
    // 朱印「典」
    let seal = NSRect(x: 676, y: 214, width: 118, height: 118)
    color(0xC24A36).setFill()
    NSBezierPath(roundedRect: seal, xRadius: 19, yRadius: 19).fill()
    glyph("典", font: "HiraMinProN-W6", size: 80, color: color(0xFFF6EC), center: NSPoint(x: seal.midX, y: seal.midY))
    NSGraphicsContext.restoreGraphicsState()

    color(0x000000, 0.10).setStroke()
    shape.lineWidth = 2
    shape.stroke()
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let args = CommandLine.arguments
let out = args.count > 1 ? args[1] : "AppIcon.icns"
let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: tmp)
try! FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
func png(_ px: Int) -> Data { render(px).representation(using: .png, properties: [:])! }

for base in [16, 32, 128, 256, 512] {
    try! png(base).write(to: tmp.appendingPathComponent("icon_\(base)x\(base).png"))
    try! png(base * 2).write(to: tmp.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", tmp.path, "-o", out]
try! p.run(); p.waitUntilExit()
print("icon written to \(out)")
if args.count > 2 {
    try! png(512).write(to: URL(fileURLWithPath: args[2]))
    print("preview written to \(args[2])")
}
