import AppKit
import AVFoundation
import ScreenCaptureKit

/// `Framecast --colortest <folder>`: shows four known colours, records the screen for a moment,
/// exports it, and writes how far the recorded and exported colours are from the originals.
enum ColorTest {
    static let patches: [(name: String, r: CGFloat, g: CGFloat, b: CGFloat)] = [
        ("red", 1, 0, 0), ("green", 0, 1, 0), ("blue", 0, 0, 1), ("sky", 0.2, 0.45, 0.95), ("grey", 0.5, 0.5, 0.5),
    ]

    @MainActor static func run(in folder: URL) async {
        var lines: [String] = ["mode: \(ColorMode.legacy ? "old" : "new")"]
        func finish() -> Never {
            try? lines.joined(separator: "\n").write(to: folder.appendingPathComponent("report.txt"), atomically: true, encoding: .utf8)
            exit(0)
        }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        guard let screen = NSScreen.main else { lines.append("no screen"); finish() }
        let side: CGFloat = 90
        let frame = CGRect(x: screen.frame.minX + 60, y: screen.frame.maxY - 60 - side - 40,
                           width: side * CGFloat(patches.count), height: side)
        let window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.level = .screenSaver
        window.hasShadow = false
        let content = NSView(frame: CGRect(origin: .zero, size: frame.size))
        content.wantsLayer = true
        for (i, p) in patches.enumerated() {
            let layer = CALayer()
            layer.frame = CGRect(x: CGFloat(i) * side, y: 0, width: side, height: side)
            layer.backgroundColor = CGColor(srgbRed: p.r, green: p.g, blue: p.b, alpha: 1)
            content.layer?.addSublayer(layer)
        }
        window.contentView = content
        window.orderFrontRegardless()
        try? await Task.sleep(nanoseconds: 600_000_000)

        do {
            let shareable = try await SCShareableContent.current
            guard let display = shareable.displays.first(where: { $0.displayID == CGMainDisplayID() }) ?? shareable.displays.first
            else { lines.append("no display"); finish() }
            let scale = screen.backingScaleFactor
            let recorder = ScreenRecorder()
            let movie = folder.appendingPathComponent("screen.mov")
            try? FileManager.default.removeItem(at: movie)
            try await recorder.start(filter: SCContentFilter(display: display, excludingWindows: []),
                                     pixelSize: CGSize(width: CGFloat(display.width) * scale, height: CGFloat(display.height) * scale),
                                     sourceRect: nil, systemAudio: false, url: movie)
            try await Task.sleep(nanoseconds: 1_600_000_000)
            await recorder.stop()
            window.orderOut(nil)

            var project = Project(name: "Colour test")
            project.duration = try await AVURLAsset(url: movie).load(.duration).seconds
            project.trimEnd = project.duration
            project.background.mode = .none
            project.screenColor = ColorMode.legacy ? nil : "sRGB"
            let out = folder.appendingPathComponent("out.mp4")
            try await Exporter().export(ref: ProjectRef(project: project, folder: folder), to: out, resolution: .original, fps: 30) { _ in }

            // Patch centres, as fractions of the screen (top-left origin).
            let points = patches.indices.map { i in
                CGPoint(x: (frame.minX - screen.frame.minX + (CGFloat(i) + 0.5) * side) / screen.frame.width,
                        y: (screen.frame.maxY - frame.midY) / screen.frame.height)
            }
            for (label, url) in [("recorded", movie), ("exported", out)] {
                let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
                let image = try await generator.image(at: CMTime(seconds: 0.8, preferredTimescale: 600)).image
                let w = image.width, h = image.height
                var data = [UInt8](repeating: 0, count: w * h * 4)
                guard let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                          space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { continue }
                ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
                var worst = 0
                for (i, p) in patches.enumerated() {
                    let x = Int(points[i].x * CGFloat(w)), y = Int(points[i].y * CGFloat(h))
                    let o = (y * w + x) * 4
                    let got = [Int(data[o]), Int(data[o + 1]), Int(data[o + 2])]
                    let want = [Int((p.r * 255).rounded()), Int((p.g * 255).rounded()), Int((p.b * 255).rounded())]
                    let off = zip(got, want).map { abs($0 - $1) }.max() ?? 0
                    worst = max(worst, off)
                    lines.append("\(label) \(p.name): want \(want) got \(got) off by \(off)")
                }
                lines.append("\(label): worst channel error \(worst) of 255 (\(w)x\(h))")
            }
            // The capture shows whatever was on screen, so it is not kept.
            try? FileManager.default.removeItem(at: movie)
            try? FileManager.default.removeItem(at: out)
        } catch {
            lines.append("FAILED: \(error)")
        }
        finish()
    }
}
