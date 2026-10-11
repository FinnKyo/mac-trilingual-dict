// 生成 README 演示动画的示意场景：虚构的阅读窗口、鼠标、选区、截图框和快捷键提示，
// 再把调试版 App 真实窗口的截图（只截 App 自己的窗口，不含桌面）放进去合成 GIF。
//
// 用法:
//   scene bubble <out.png>              生成截图演示里的对话气泡图片（交给 App 做真实的 OCR）
//   scene compose <工作目录> <输出目录>   用工作目录里的窗口截图合成 demo-*.gif
import AppKit
import ImageIO
import UniformTypeIdentifiers

let W: CGFloat = 960, H: CGFloat = 800   // 场景大小（pt），按 2x 渲染
let outputWidth = 880                     // GIF 宽度（px）

// MARK: - 绘制工具

func color(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

/// 在左上角为原点的坐标系里作画，返回 2x 位图
func render(width: CGFloat = W, height: CGFloat = H, _ draw: () -> Void) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width * 2), pixelsHigh: Int(height * 2), bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: width, height: height)
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx
    let flip = NSAffineTransform()
    flip.translateX(by: 0, yBy: height)
    flip.scaleX(by: 1, yBy: -1)
    flip.concat()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx.cgContext, flipped: true)
    draw()
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func text(_ s: String, size: CGFloat, weight: NSFont.Weight = .regular, color c: NSColor = color(0x1F2328)) -> NSAttributedString {
    NSAttributedString(string: s, attributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: c])
}

func shadowed(_ blur: CGFloat, _ alpha: CGFloat, _ body: () -> Void) {
    NSGraphicsContext.saveGraphicsState()
    let sh = NSShadow()
    sh.shadowBlurRadius = blur
    sh.shadowOffset = NSSize(width: 0, height: -blur / 3)
    sh.shadowColor = NSColor.black.withAlphaComponent(alpha)
    sh.set()
    body()
    NSGraphicsContext.restoreGraphicsState()
}

func background() {
    NSGradient(starting: color(0xD9E2EC), ending: color(0xF1F3F6))!.draw(in: NSRect(x: 0, y: 0, width: W, height: H), angle: 90)
}

/// 虚构的阅读窗口（不模仿任何真实 App）
let windowRect = NSRect(x: 40, y: 40, width: 620, height: 620)
func readerWindow(title: String, content: (NSRect) -> Void) {
    let path = NSBezierPath(roundedRect: windowRect, xRadius: 10, yRadius: 10)
    shadowed(28, 0.22) { NSColor.white.setFill(); path.fill() }
    NSGraphicsContext.saveGraphicsState()
    path.addClip()
    let bar = NSRect(x: windowRect.minX, y: windowRect.minY, width: windowRect.width, height: 36)
    color(0xEEEEF0).setFill(); bar.fill()
    color(0xDADADD).setFill(); NSRect(x: bar.minX, y: bar.maxY - 1, width: bar.width, height: 1).fill()
    for (i, c) in [0xFF5F57, 0xFEBC2E, 0x28C840].enumerated() {
        color(UInt32(c)).setFill()
        NSBezierPath(ovalIn: NSRect(x: bar.minX + 14 + CGFloat(i) * 20, y: bar.midY - 6, width: 12, height: 12)).fill()
    }
    let t = text(title, size: 13, weight: .medium, color: color(0x6B7078))
    t.draw(at: NSPoint(x: bar.midX - t.size().width / 2, y: bar.midY - t.size().height / 2))
    content(NSRect(x: windowRect.minX + 40, y: bar.maxY + 32, width: windowRect.width - 80, height: windowRect.height - 100))
    NSGraphicsContext.restoreGraphicsState()
    color(0x000000, 0.12).setStroke(); path.lineWidth = 1; path.stroke()
}

// 文章：在固定宽度里排版，并能取到某个词的位置
let heading = "春の京都を歩く"
let paragraph = "京都には古いお寺や神社がたくさんあり、歩きながら日本の歴史を勉強することができます。春になると桜が咲き、川沿いの道は多くの人でにぎわいます。朝早く出かければ、静かな庭園をゆっくり楽しめるでしょう。"
let selectedWord = "勉強"

final class Article {
    let storage: NSTextStorage
    let layout = NSLayoutManager()
    let container: NSTextContainer
    let origin: NSPoint

    init(in rect: NSRect) {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 12
        storage = NSTextStorage(string: paragraph, attributes: [
            .font: NSFont.systemFont(ofSize: 18), .foregroundColor: color(0x2B2F36), .paragraphStyle: style,
        ])
        container = NSTextContainer(size: NSSize(width: rect.width, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)
        storage.addLayoutManager(layout)
        origin = NSPoint(x: rect.minX, y: rect.minY + 56)
    }

    /// 选中词的位置（frac：从左往右选中了多少）
    func rect(selecting frac: CGFloat = 1) -> NSRect {
        let r = (paragraph as NSString).range(of: selectedWord)
        let glyphs = layout.glyphRange(forCharacterRange: r, actualCharacterRange: nil)
        var b = layout.boundingRect(forGlyphRange: glyphs, in: container).offsetBy(dx: origin.x, dy: origin.y)
        b.size.width *= frac
        return b
    }

    func draw(selection frac: CGFloat?) {
        text(heading, size: 26, weight: .bold).draw(at: NSPoint(x: origin.x, y: origin.y - 56))
        if let frac, frac > 0 {
            color(0xB3D4FF).setFill()
            NSBezierPath(roundedRect: rect(selecting: frac).insetBy(dx: -1, dy: -2), xRadius: 2, yRadius: 2).fill()
        }
        layout.drawGlyphs(forGlyphRange: layout.glyphRange(for: container), at: origin)
    }
}

// MARK: - 鼠标与提示

enum Cursor { case arrow, ibeam, crosshair }

func cursor(_ kind: Cursor, at p: NSPoint) {
    NSGraphicsContext.saveGraphicsState()
    switch kind {
    case .arrow:
        let path = NSBezierPath()
        let pts: [(CGFloat, CGFloat)] = [(0, 0), (0, 17), (4.2, 13.2), (7, 19.6), (9.6, 18.5), (6.8, 12.2), (12.2, 12.2)]
        path.move(to: NSPoint(x: p.x + pts[0].0, y: p.y + pts[0].1))
        for q in pts.dropFirst() { path.line(to: NSPoint(x: p.x + q.0, y: p.y + q.1)) }
        path.close()
        path.lineWidth = 1.4
        shadowed(3, 0.3) { NSColor.black.setFill(); path.fill() }
        NSColor.white.setStroke(); path.stroke()
    case .ibeam:
        let path = NSBezierPath()
        path.move(to: NSPoint(x: p.x - 4, y: p.y - 10)); path.line(to: NSPoint(x: p.x + 4, y: p.y - 10))
        path.move(to: NSPoint(x: p.x, y: p.y - 10)); path.line(to: NSPoint(x: p.x, y: p.y + 10))
        path.move(to: NSPoint(x: p.x - 4, y: p.y + 10)); path.line(to: NSPoint(x: p.x + 4, y: p.y + 10))
        path.lineWidth = 4; NSColor.white.setStroke(); path.stroke()
        path.lineWidth = 1.6; NSColor.black.setStroke(); path.stroke()
    case .crosshair:
        let path = NSBezierPath()
        path.move(to: NSPoint(x: p.x - 11, y: p.y)); path.line(to: NSPoint(x: p.x + 11, y: p.y))
        path.move(to: NSPoint(x: p.x, y: p.y - 11)); path.line(to: NSPoint(x: p.x, y: p.y + 11))
        path.lineWidth = 3.5; NSColor.white.setStroke(); path.stroke()
        path.lineWidth = 1.4; NSColor.black.setStroke(); path.stroke()
    }
    NSGraphicsContext.restoreGraphicsState()
}

/// 划词后出现的小图标（与 App 里的样式一致）
func selectionIcon(at origin: NSPoint) -> NSRect {
    let r = NSRect(x: origin.x, y: origin.y, width: 26, height: 26)
    shadowed(6, 0.25) { color(0x4A6489).setFill(); NSBezierPath(roundedRect: r, xRadius: 7, yRadius: 7).fill() }
    let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold).applying(.init(paletteColors: [.white]))
    if let img = NSImage(systemSymbolName: "character.book.closed.fill", accessibilityDescription: nil)?.withSymbolConfiguration(config) {
        let s = img.size
        img.draw(in: NSRect(x: r.midX - s.width / 2, y: r.midY - s.height / 2, width: s.width, height: s.height),
                 from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }
    return r
}

/// 屏幕下方的快捷键提示
func keyBadge(_ keys: String, caption: String) {
    let r = NSRect(x: W / 2 - 110, y: H - 120, width: 220, height: 84)
    shadowed(16, 0.25) { color(0x1E1F22, 0.82).setFill(); NSBezierPath(roundedRect: r, xRadius: 16, yRadius: 16).fill() }
    let k = text(keys, size: 30, weight: .semibold, color: .white)
    k.draw(at: NSPoint(x: r.midX - k.size().width / 2, y: r.minY + 12))
    let c = text(caption, size: 13, color: color(0xFFFFFF, 0.75))
    c.draw(at: NSPoint(x: r.midX - c.size().width / 2, y: r.maxY - 28))
}

/// App 窗口（调试版截下来的真实窗口，2x）
func panel(_ path: String, at origin: NSPoint) {
    guard let img = NSImage(contentsOfFile: path), let rep = img.representations.first else { return }
    let size = NSSize(width: CGFloat(rep.pixelsWide) / 2, height: CGFloat(rep.pixelsHigh) / 2)
    shadowed(30, 0.28) {
        img.draw(in: NSRect(origin: origin, size: size), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }
}

let topRight = NSPoint(x: W - 12 - 480, y: 12)

// MARK: - 截图演示里的图片

let photoRect = NSRect(x: windowRect.minX + 40, y: windowRect.minY + 36 + 90, width: windowRect.width - 80, height: 330)
let bubbleText = "今日はいい天気ですね！"

func drawPhoto() {
    let photo = NSBezierPath(roundedRect: photoRect, xRadius: 8, yRadius: 8)
    NSGradient(starting: color(0xBFE0F5), ending: color(0xEAF5FC))!.draw(in: photo, angle: 90)
    // 远山和草地
    color(0x9CC9A0).setFill()
    let hill = NSBezierPath()
    hill.move(to: NSPoint(x: photoRect.minX, y: photoRect.maxY))
    hill.curve(to: NSPoint(x: photoRect.maxX, y: photoRect.maxY - 40),
               controlPoint1: NSPoint(x: photoRect.minX + 160, y: photoRect.maxY - 120),
               controlPoint2: NSPoint(x: photoRect.maxX - 200, y: photoRect.maxY - 10))
    hill.line(to: NSPoint(x: photoRect.maxX, y: photoRect.maxY)); hill.close()
    NSGraphicsContext.saveGraphicsState(); photo.addClip(); hill.fill(); NSGraphicsContext.restoreGraphicsState()
    color(0xFFD86B).setFill()
    NSBezierPath(ovalIn: NSRect(x: photoRect.maxX - 110, y: photoRect.minY + 30, width: 56, height: 56)).fill()
    drawBubble(in: bubbleRect)
}

let bubbleRect = NSRect(x: photoRect.minX + 60, y: photoRect.minY + 70, width: 360, height: 120)
func drawBubble(in r: NSRect) {
    let bubble = NSBezierPath(ovalIn: r)
    let tail = NSBezierPath()
    tail.move(to: NSPoint(x: r.minX + 120, y: r.maxY - 12))
    tail.line(to: NSPoint(x: r.minX + 96, y: r.maxY + 34))
    tail.line(to: NSPoint(x: r.minX + 168, y: r.maxY - 6))
    tail.close()
    NSColor.white.setFill(); tail.fill(); bubble.fill()
    NSColor.black.setStroke(); bubble.lineWidth = 2.5; bubble.stroke()
    let t = text(bubbleText, size: 28, weight: .bold, color: .black)
    t.draw(at: NSPoint(x: r.midX - t.size().width / 2, y: r.midY - t.size().height / 2))
}

/// 截图时的遮罩：选区外变暗，选区描边
func screenshotOverlay(_ sel: NSRect) {
    let dim = NSBezierPath(rect: NSRect(x: 0, y: 0, width: W, height: H))
    dim.append(NSBezierPath(rect: sel))
    dim.windingRule = .evenOdd
    color(0x000000, 0.32).setFill(); dim.fill()
    let border = NSBezierPath(rect: sel)
    border.lineWidth = 1.2
    NSColor.white.setStroke(); border.stroke()
}

// MARK: - 输出

func writeGIF(_ frames: [(NSBitmapImageRep, Int)], to path: String) {
    let outH = Int(CGFloat(outputWidth) * H / W)
    let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, UTType.gif.identifier as CFString, frames.count, nil)!
    CGImageDestinationSetProperties(dest, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
    for (rep, delay) in frames {
        let ctx = CGContext(data: nil, width: outputWidth, height: outH, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.interpolationQuality = .high
        ctx.draw(rep.cgImage!, in: CGRect(x: 0, y: 0, width: outputWidth, height: outH))
        CGImageDestinationAddImage(dest, ctx.makeImage()!, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: Double(delay) / 1000]] as CFDictionary)
    }
    precondition(CGImageDestinationFinalize(dest))
    print("wrote \(path) (\(frames.count) frames)")
}

let args = CommandLine.arguments
switch args[1] {
case "bubble":
    let pad: CGFloat = 30
    let r = bubbleRect.insetBy(dx: -pad, dy: -pad)
    let rep = render(width: r.width, height: r.height + 30) {
        NSColor.white.setFill(); NSRect(x: 0, y: 0, width: r.width, height: r.height + 30).fill()
        drawBubble(in: NSRect(x: pad, y: pad, width: bubbleRect.width, height: bubbleRect.height))
    }
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[2]))

case "compose":
    let work = args[2], out = args[3]
    func p(_ name: String) -> String { "\(work)/\(name).png" }

    // 1. 划词
    let article = Article(in: NSRect(x: windowRect.minX + 40, y: windowRect.minY + 36 + 32, width: windowRect.width - 80, height: 400))
    let word = article.rect()
    let mouseEnd = NSPoint(x: word.maxX, y: word.midY)
    let iconOrigin = NSPoint(x: mouseEnd.x + 10, y: word.maxY + 10)
    let panelOrigin = NSPoint(x: min(iconOrigin.x - 16, W - 4 - 480), y: iconOrigin.y + 26 + 4)
    func page(_ sel: CGFloat?, _ body: () -> Void = {}) -> NSBitmapImageRep {
        render { background(); readerWindow(title: "读物 · 示例") { _ in article.draw(selection: sel) }; body() }
    }
    var selection: [(NSBitmapImageRep, Int)] = [
        (page(nil) { cursor(.ibeam, at: NSPoint(x: word.minX - 30, y: word.midY + 30)) }, 700),
        (page(nil) { cursor(.ibeam, at: NSPoint(x: word.minX, y: word.midY)) }, 400),
    ]
    for f in [0.35, 0.7, 1.0] as [CGFloat] {
        selection.append((page(f) { cursor(.ibeam, at: NSPoint(x: word.minX + word.width * f, y: word.midY)) }, 160))
    }
    selection.append((page(1) { _ = selectionIcon(at: iconOrigin); cursor(.ibeam, at: mouseEnd) }, 700))
    selection.append((page(1) { _ = selectionIcon(at: iconOrigin); cursor(.arrow, at: NSPoint(x: iconOrigin.x + 6, y: iconOrigin.y - 4)) }, 180))
    selection.append((page(1) { _ = selectionIcon(at: iconOrigin); cursor(.arrow, at: NSPoint(x: iconOrigin.x + 12, y: iconOrigin.y + 12)) }, 300))
    selection.append((page(1) { panel(p("sel_loading"), at: panelOrigin) }, 450))
    selection.append((page(1) { panel(p("sel_result"), at: panelOrigin) }, 4200))
    writeGIF(selection, to: "\(out)/demo-selection.gif")

    // 2. 截图
    func shotPage(_ body: () -> Void) -> NSBitmapImageRep {
        render {
            background()
            readerWindow(title: "漫画 · 示例") { r in
                text("第 3 话", size: 15, weight: .semibold, color: color(0x6B7078)).draw(at: NSPoint(x: r.minX, y: r.minY))
                drawPhoto()
            }
            body()
        }
    }
    let selStart = NSPoint(x: bubbleRect.minX - 24, y: bubbleRect.minY - 20)
    let selEnd = NSPoint(x: bubbleRect.maxX + 24, y: bubbleRect.maxY + 44)
    func selRect(_ f: CGFloat) -> NSRect {
        NSRect(x: selStart.x, y: selStart.y, width: (selEnd.x - selStart.x) * f, height: (selEnd.y - selStart.y) * f)
    }
    var screenshot: [(NSBitmapImageRep, Int)] = [
        (shotPage { keyBadge("⌥  S", caption: "截图翻译") }, 900),
        (shotPage { cursor(.crosshair, at: selStart) }, 400),
    ]
    for f in [0.3, 0.6, 1.0] as [CGFloat] {
        let r = selRect(f)
        screenshot.append((shotPage { screenshotOverlay(r); cursor(.crosshair, at: NSPoint(x: r.maxX, y: r.maxY)) }, 180))
    }
    screenshot.append((shotPage { panel(p("ocr_status"), at: topRight) }, 500))
    screenshot.append((shotPage { panel(p("ocr_result"), at: topRight) }, 4200))
    writeGIF(screenshot, to: "\(out)/demo-screenshot.gif")

    // 3. 直接输入
    func inputPage(_ body: () -> Void) -> NSBitmapImageRep {
        render { background(); readerWindow(title: "读物 · 示例") { _ in article.draw(selection: nil) }; body() }
    }
    var input: [(NSBitmapImageRep, Int)] = [
        (inputPage { keyBadge("⌥  A", caption: "输入翻译") }, 900),
        (inputPage { panel(p("input_0"), at: topRight) }, 500),
    ]
    var i = 1
    while FileManager.default.fileExists(atPath: p("input_\(i)")) {
        let name = "input_\(i)"
        input.append((inputPage { panel(p(name), at: topRight) }, 200))
        i += 1
    }
    input.append((inputPage { panel(p("input_result"), at: topRight) }, 4200))
    writeGIF(input, to: "\(out)/demo-input.gif")

default:
    print("用法: scene bubble <out.png> | scene compose <工作目录> <输出目录>")
}
