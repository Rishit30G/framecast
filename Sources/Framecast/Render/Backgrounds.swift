import AppKit
import CoreGraphics

struct BackgroundPreset: Identifiable {
    enum Kind {
        /// Colours along a line at `angle` degrees (0 = left→right, 90 = bottom→top).
        case linear(angle: CGFloat)
        /// First colour is the base; the rest are soft blobs.
        case mesh
    }
    var id: String
    var name: String
    var kind: Kind
    var colors: [UInt32]

    static let all: [BackgroundPreset] = [
        .init(id: "aurora", name: "Aurora", kind: .mesh, colors: [0x1b1f4b, 0x5b5bf0, 0xe26bb5, 0x2bb3c0, 0xf2a65a]),
        .init(id: "dawn", name: "Dawn", kind: .mesh, colors: [0xf6d5c2, 0xf7a58b, 0xc9a7eb, 0xfbe3a1, 0x9cc7f2]),
        .init(id: "ocean", name: "Ocean", kind: .linear(angle: 60), colors: [0x0b3a67, 0x1d7fc4, 0x7fd3e6]),
        .init(id: "ember", name: "Ember", kind: .linear(angle: 45), colors: [0xb3261e, 0xf0652f, 0xf9c15c]),
        .init(id: "moss", name: "Moss", kind: .linear(angle: 50), colors: [0x123c35, 0x2f8f6b, 0xbfe3a6]),
        .init(id: "orchid", name: "Orchid", kind: .mesh, colors: [0x2a1846, 0x8a4fd3, 0xe58ac6, 0x4f6fe0, 0x35205c]),
        .init(id: "graphite", name: "Graphite", kind: .linear(angle: 90), colors: [0x16171a, 0x34373d]),
        .init(id: "paper", name: "Paper", kind: .linear(angle: 90), colors: [0xe4e1da, 0xf6f4ef]),
    ]

    static func find(_ id: String) -> BackgroundPreset { all.first { $0.id == id } ?? all[0] }
}

/// The wallpapers that ship with macOS, read from this Mac (nothing is bundled with the app).
/// Only full-size files are listed; more appear once they are downloaded in
/// System Settings › Wallpaper.
struct MacWallpaper: Identifiable {
    var name: String
    var path: String
    var id: String { path }

    static let all: [MacWallpaper] = {
        let fm = FileManager.default
        let system = "/System/Library/Desktop Pictures"
        var folders = [system, fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/com.apple.mobileAssetDesktop").path]
        if let extra = try? fm.contentsOfDirectory(atPath: system + "/.wallpapers") {
            folders += extra.map { system + "/.wallpapers/" + $0 }
        }
        var found: [String: MacWallpaper] = [:]
        for folder in folders {
            for file in (try? fm.contentsOfDirectory(atPath: folder)) ?? [] where file.lowercased().hasSuffix(".heic") || file.lowercased().hasSuffix(".jpg") {
                let name = (file as NSString).deletingPathExtension
                if found[name] == nil { found[name] = MacWallpaper(name: name, path: folder + "/" + file) }
            }
        }
        // The well-loved landscape and graphic ones first, plain colour washes last.
        let favourites = ["Sonoma Horizon", "Sonoma", "Sequoia", "Tahoe", "Ventura Graphic", "Monterey Graphic", "Big Sur", "Big Sur Graphic",
                          "The Lake", "The Desert", "The Beach", "The Cliffs", "Valley", "Tree", "Peak", "Dome", "Iridescence",
                          "Solar Gradients", "Chroma Blue", "Chroma Red", "Radial Sky Blue", "Grid Green", "Grid Magenta"]
        func rank(_ w: MacWallpaper) -> Int { favourites.firstIndex(of: w.name) ?? favourites.count }
        return found.values.sorted { rank($0) != rank($1) ? rank($0) < rank($1) : $0.name < $1.name }
    }()

    static func named(_ name: String) -> MacWallpaper? {
        all.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    private static var thumbnails: [String: NSImage] = [:]

    /// A small preview, decoded once.
    static func thumbnail(_ path: String) -> NSImage? {
        if let hit = thumbnails[path] { return hit }
        guard let cg = load(path, maxPixel: 360) else { return nil }
        let image = NSImage(cgImage: cg, size: CGSize(width: cg.width, height: cg.height))
        thumbnails[path] = image
        return image
    }

    /// Decodes a picture no larger than needed (the system wallpapers are 6K).
    static func load(_ path: String, maxPixel: Int) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(src, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ] as CFDictionary)
    }
}

/// The solid colours macOS itself offers as wallpapers.
enum MacColors {
    static let all: [(name: String, hex: UInt32)] = [
        ("Black", 0x000000), ("Stone", 0x545554), ("Space Gray Pro", 0x7a7b80), ("Space Gray", 0xbebfc4), ("Silver", 0xe3e4e5),
        ("Soft Pink", 0xfcdde5), ("Rose Gold", 0xf6d3ce), ("Gold", 0xf2dec9), ("Ocher", 0xd4a656), ("Yellow", 0xfdb813),
        ("Red Orange", 0xea3e24), ("Dusty Rose", 0xe16e79), ("Plum", 0xcd4b93), ("Blue Violet", 0x6867af), ("Electric Blue", 0x4154d6),
        ("Cyan", 0x14afd0), ("Teal", 0x007973), ("Turquoise Green", 0x6ac4a2),
    ]
}

enum BackgroundPainter {
    static func image(_ style: BackgroundStyle, size: CGSize) -> CGImage? {
        let w = max(Int(size.width), 2), h = max(Int(size.height), 2)
        guard let cs = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return nil }
        let rect = CGRect(x: 0, y: 0, width: w, height: h)

        switch style.mode {
        case .none:
            ctx.setFillColor(CGColor(gray: 0, alpha: 1))
            ctx.fill(rect)
        case .color:
            ctx.setFillColor(style.color.cgColor)
            ctx.fill(rect)
        case .image:
            ctx.setFillColor(CGColor(gray: 0.1, alpha: 1))
            ctx.fill(rect)
            if let path = style.imagePath, let img = MacWallpaper.load(path, maxPixel: max(w, h) * 2) {
                let iw = CGFloat(img.width), ih = CGFloat(img.height)
                let scale = max(rect.width / iw, rect.height / ih)
                let dw = iw * scale, dh = ih * scale
                ctx.interpolationQuality = .high
                ctx.draw(img, in: CGRect(x: (rect.width - dw) / 2, y: (rect.height - dh) / 2, width: dw, height: dh))
            }
        case .preset:
            paint(BackgroundPreset.find(style.presetID), in: ctx, rect: rect, colorSpace: cs)
        }
        return ctx.makeImage()
    }

    private static func paint(_ preset: BackgroundPreset, in ctx: CGContext, rect: CGRect, colorSpace: CGColorSpace) {
        let colors = preset.colors.map { RGBA(hex: $0) }
        switch preset.kind {
        case .linear(let angle):
            let cg = colors.map { $0.cgColor } as CFArray
            guard let gradient = CGGradient(colorsSpace: colorSpace, colors: cg, locations: nil) else { return }
            let rad = angle * .pi / 180
            let dx = cos(rad) * rect.width / 2, dy = sin(rad) * rect.height / 2
            ctx.drawLinearGradient(gradient,
                                   start: CGPoint(x: rect.midX - dx, y: rect.midY - dy),
                                   end: CGPoint(x: rect.midX + dx, y: rect.midY + dy),
                                   options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        case .mesh:
            ctx.setFillColor(colors[0].cgColor)
            ctx.fill(rect)
            // Fixed blob positions keep the look identical at every resolution.
            let spots: [(CGFloat, CGFloat, CGFloat)] = [(0.12, 0.85, 0.75), (0.9, 0.9, 0.7), (0.85, 0.1, 0.8), (0.2, 0.1, 0.65)]
            let reach = max(rect.width, rect.height)
            for (i, color) in colors.dropFirst().enumerated() {
                let spot = spots[i % spots.count]
                var clear = color
                clear.a = 0
                guard let gradient = CGGradient(colorsSpace: colorSpace,
                                                colors: [color.cgColor, clear.cgColor] as CFArray,
                                                locations: [0, 1]) else { continue }
                let center = CGPoint(x: rect.width * spot.0, y: rect.height * spot.1)
                ctx.drawRadialGradient(gradient, startCenter: center, startRadius: 0,
                                       endCenter: center, endRadius: reach * spot.2, options: [])
            }
        }
    }

    static func thumbnail(_ style: BackgroundStyle) -> NSImage {
        let size = CGSize(width: 160, height: 100)
        guard let cg = image(style, size: size) else { return NSImage(size: size) }
        return NSImage(cgImage: cg, size: size)
    }
}
