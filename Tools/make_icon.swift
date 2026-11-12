import AppKit
// Draws the app icon and writes an .iconset folder. Usage: swift make_icon.swift <out.iconset>
let out = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
func draw(_ px: Int) -> Data {
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let s = CGFloat(px)
    let inset = s * 0.1
    let rect = CGRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let path = CGPath(roundedRect: rect, cornerWidth: rect.width * 0.225, cornerHeight: rect.width * 0.225, transform: nil)
    ctx.saveGState()
    ctx.addPath(path); ctx.clip()
    let colors = [CGColor(srgbRed: 0.11, green: 0.12, blue: 0.29, alpha: 1), CGColor(srgbRed: 0.36, green: 0.36, blue: 0.94, alpha: 1),
                  CGColor(srgbRed: 0.89, green: 0.42, blue: 0.71, alpha: 1)] as CFArray
    let g = CGGradient(colorsSpace: cs, colors: colors, locations: [0, 0.55, 1])!
    ctx.drawLinearGradient(g, start: CGPoint(x: rect.minX, y: rect.minY), end: CGPoint(x: rect.maxX, y: rect.maxY), options: [])
    // A small "screen" card with a camera bubble.
    let card = rect.insetBy(dx: rect.width * 0.2, dy: rect.height * 0.27)
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.015), blur: s * 0.04, color: CGColor(gray: 0, alpha: 0.35))
    ctx.addPath(CGPath(roundedRect: card, cornerWidth: s * 0.035, cornerHeight: s * 0.035, transform: nil))
    ctx.setFillColor(CGColor(gray: 1, alpha: 0.96)); ctx.fillPath()
    let d = rect.width * 0.24
    ctx.setFillColor(CGColor(srgbRed: 1, green: 0.27, blue: 0.3, alpha: 1))
    ctx.fillEllipse(in: CGRect(x: card.maxX - d * 0.62, y: card.minY - d * 0.38, width: d, height: d))
    ctx.restoreGState()
    return NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!
}
for (name, px) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128), ("128x128@2x", 256),
                   ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
    try draw(px).write(to: out.appendingPathComponent("icon_\(name).png"))
}
