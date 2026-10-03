// 生成 App 图标：swift scripts/make_icon.swift Resources/AppIcon.icns
import AppKit

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.icns"
let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: tmp)
try! FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px)
    let inset = s * 0.09
    let rect = NSRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let path = NSBezierPath(roundedRect: rect, xRadius: s * 0.19, yRadius: s * 0.19)
    NSGradient(colors: [NSColor(calibratedRed: 0.20, green: 0.47, blue: 0.96, alpha: 1),
                        NSColor(calibratedRed: 0.47, green: 0.30, blue: 0.90, alpha: 1)])!
        .draw(in: path, angle: -60)
    let para = NSMutableParagraphStyle(); para.alignment = .center
    func draw(_ t: String, size: CGFloat, x: CGFloat, y: CGFloat, alpha: CGFloat) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: size, weight: .bold),
            .foregroundColor: NSColor.white.withAlphaComponent(alpha),
            .paragraphStyle: para,
        ]
        let str = NSAttributedString(string: t, attributes: attrs)
        let b = str.size()
        str.draw(at: NSPoint(x: x - b.width / 2, y: y - b.height / 2))
    }
    draw("辞", size: s * 0.42, x: s * 0.5, y: s * 0.56, alpha: 1)
    draw("中 · あ · A", size: s * 0.12, x: s * 0.5, y: s * 0.24, alpha: 0.9)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    try! render(base).write(to: tmp.appendingPathComponent("icon_\(base)x\(base).png"))
    try! render(base * 2).write(to: tmp.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", tmp.path, "-o", out]
try! p.run(); p.waitUntilExit()
print("icon written to \(out)")
