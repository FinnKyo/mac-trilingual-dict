// 把逐帧截图合成为 GIF：每帧放在纯色画布顶部居中（和真实窗口一样向下长）
// 用法: mkgif <frames.txt> <out.gif> <背景色 hex> <输出宽度>；frames.txt 每行「png 路径 毫秒」
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
let lines = try! String(contentsOfFile: args[1], encoding: .utf8).split(separator: "\n").map { $0.split(separator: " ") }
let frames: [(CGImage, Int)] = lines.map { parts in
    let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: String(parts[0])) as CFURL, nil)!
    return (CGImageSourceCreateImageAtIndex(src, 0, nil)!, Int(parts[1])!)
}
let bg = UInt32(args[3], radix: 16)!, targetWidth = CGFloat(Double(args[4])!)
let margin: CGFloat = 56
let canvasW = CGFloat(frames.map { $0.0.width }.max()!) + margin * 2
let canvasH = CGFloat(frames.map { $0.0.height }.max()!) + margin * 2
let scale = targetWidth / canvasW
let outW = Int(canvasW * scale), outH = Int(canvasH * scale)

let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: args[2]) as CFURL, UTType.gif.identifier as CFString, frames.count, nil)!
CGImageDestinationSetProperties(dest, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
for (img, delay) in frames {
    let ctx = CGContext(data: nil, width: outW, height: outH, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(CGColor(red: CGFloat((bg >> 16) & 0xFF) / 255, green: CGFloat((bg >> 8) & 0xFF) / 255, blue: CGFloat(bg & 0xFF) / 255, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: outW, height: outH))
    ctx.interpolationQuality = .high
    let w = CGFloat(img.width) * scale, h = CGFloat(img.height) * scale
    ctx.draw(img, in: CGRect(x: margin * scale, y: CGFloat(outH) - margin * scale - h, width: w, height: h))
    CGImageDestinationAddImage(dest, ctx.makeImage()!, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: Double(delay) / 1000]] as CFDictionary)
}
precondition(CGImageDestinationFinalize(dest))
print("wrote \(args[2]) \(outW)x\(outH), \(frames.count) frames")
