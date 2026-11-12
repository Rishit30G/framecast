import AppKit
import AVFoundation
import CoreText

/// `Framecast --demos <folder>` renders the feature clips for the website: a made-up dashboard
/// "recording" and an illustrated presenter, run through the real editor pipeline.
enum Demos {
    static let screenSize = CGSize(width: 2560, height: 1600)

    // MARK: Cursor scripts (time, x, y as fractions of the screen, top-left origin)

    typealias Path = [(t: Double, x: Double, y: Double)]

    static func cursor(_ path: Path, at t: Double) -> CGPoint {
        guard let first = path.first else { return .zero }
        var a = first, b = first
        for k in path { if k.t <= t { a = k; b = k } else { b = k; break } }
        let span = b.t - a.t
        var u = span > 0 ? min(max((t - a.t) / span, 0), 1) : 1
        u = u * u * (3 - 2 * u)
        return CGPoint(x: (a.x + (b.x - a.x) * u) * screenSize.width, y: (a.y + (b.y - a.y) * u) * screenSize.height)
    }

    // Named spots on the dashboard.
    static let revenue = (x: 0.28, y: 0.256), users = (x: 0.48, y: 0.256), chart = (x: 0.445, y: 0.53)
    static let liveKey = (x: 0.848, y: 0.447), row2 = (x: 0.582, y: 0.8625), exportButton = (x: 0.918, y: 0.116)
    static let sidebarRevenue = (x: 0.07, y: 0.33)

    // MARK: Drawing helpers

    struct Pen {
        let ctx: CGContext
        let h: CGFloat
        func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ hh: CGFloat) -> CGRect { CGRect(x: x, y: h - y - hh, width: w, height: hh) }
        func fill(_ r: CGRect, _ c: UInt32, radius: CGFloat = 0, alpha: CGFloat = 1) {
            ctx.setFillColor(color(c, alpha))
            ctx.addPath(CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil))
            ctx.fillPath()
        }
        func stroke(_ r: CGRect, _ c: UInt32, radius: CGFloat = 0, width: CGFloat = 2) {
            ctx.setStrokeColor(color(c))
            ctx.setLineWidth(width)
            ctx.addPath(CGPath(roundedRect: r.insetBy(dx: width / 2, dy: width / 2), cornerWidth: radius, cornerHeight: radius, transform: nil))
            ctx.strokePath()
        }
        func color(_ c: UInt32, _ a: CGFloat = 1) -> CGColor {
            CGColor(srgbRed: CGFloat((c >> 16) & 0xff) / 255, green: CGFloat((c >> 8) & 0xff) / 255, blue: CGFloat(c & 0xff) / 255, alpha: a)
        }
        /// `y` is the baseline, measured from the top.
        func text(_ s: String, _ x: CGFloat, _ y: CGFloat, size: CGFloat, weight: NSFont.Weight = .regular, color c: UInt32 = 0x1d1f24, mono: Bool = false, right: Bool = false) {
            let font = mono ? NSFont.monospacedSystemFont(ofSize: size, weight: weight) : NSFont.systemFont(ofSize: size, weight: weight)
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: s, attributes: [
                .font: font, .foregroundColor: NSColor(cgColor: color(c)) ?? .black,
            ]))
            let width = CTLineGetTypographicBounds(line, nil, nil, nil)
            ctx.textMatrix = .identity
            ctx.textPosition = CGPoint(x: right ? x - CGFloat(width) : x, y: h - y)
            CTLineDraw(line, ctx)
        }
    }

    // MARK: The pretend screen

    static func drawDashboard(_ ctx: CGContext, _ size: CGSize, _ t: Double, path: Path) {
        let p = Pen(ctx: ctx, h: size.height)
        p.fill(CGRect(origin: .zero, size: size), 0xffffff)
        // Browser chrome
        p.fill(p.rect(0, 0, 2560, 92), 0xf1f2f4)
        p.fill(p.rect(0, 91, 2560, 2), 0xe2e4e8)
        for (i, c) in [UInt32(0xff5f57), 0xfebc2e, 0x28c840].enumerated() {
            p.fill(p.rect(34 + CGFloat(i) * 42, 32, 26, 26), c, radius: 13)
        }
        p.fill(p.rect(860, 22, 840, 48), 0xffffff, radius: 24)
        p.text("app.northwind.io/overview", 1280 - 190, 56, size: 26, color: 0x5d6270)
        // Sidebar
        p.fill(p.rect(0, 93, 420, 1507), 0xf8f9fb)
        p.fill(p.rect(419, 93, 2, 1507), 0xeceef2)
        p.fill(p.rect(40, 140, 52, 52), 0x3b5bdb, radius: 14)
        p.text("N", 54, 178, size: 32, weight: .bold, color: 0xffffff)
        p.text("Northwind", 110, 178, size: 34, weight: .semibold)
        let nav = ["Overview", "Revenue", "Customers", "Reports", "Integrations", "Settings"]
        for (i, item) in nav.enumerated() {
            let y = 280 + CGFloat(i) * 76
            if i == 0 { p.fill(p.rect(24, y - 46, 372, 64), 0xe8edfb, radius: 14) }
            p.fill(p.rect(48, y - 30, 30, 30), i == 0 ? 0x3b5bdb : 0xc4c8d2, radius: 8)
            p.text(item, 100, y - 6, size: 30, weight: i == 0 ? .semibold : .regular, color: i == 0 ? 0x1d3bb8 : 0x4a4f5c)
        }
        // Header
        p.text("Overview", 480, 200, size: 64, weight: .bold)
        p.text("Last 30 days · updated 2 min ago", 480, 252, size: 28, color: 0x7a7f8c)
        p.fill(p.rect(2220, 150, 260, 72), 0x1d1f24, radius: 16)
        p.text("Export report", 2350 - 88, 196, size: 27, weight: .semibold, color: 0xffffff)
        // KPI cards
        let kpis = [("Revenue", "$84,210", "+12.4%", true), ("Active users", "12,480", "+6.1%", true),
                    ("Churn", "1.8%", "−0.3%", true), ("Avg. response", "1h 42m", "+8m", false)]
        for (i, k) in kpis.enumerated() {
            let x = 480 + CGFloat(i) * 515
            p.fill(p.rect(x, 300, 475, 220), 0xffffff, radius: 22)
            p.stroke(p.rect(x, 300, 475, 220), 0xe4e6eb, radius: 22)
            p.text(k.0, x + 36, 362, size: 28, color: 0x6b7080)
            p.text(k.1, x + 36, 448, size: 60, weight: .bold)
            p.fill(p.rect(x + 36, 470, 120, 38), k.3 ? 0xe3f6ea : 0xfdecec, radius: 19)
            p.text(k.2, x + 52, 498, size: 24, weight: .semibold, color: k.3 ? 0x1e8a4a : 0xc0392b)
        }
        // Chart
        p.fill(p.rect(480, 560, 1320, 580), 0xffffff, radius: 22)
        p.stroke(p.rect(480, 560, 1320, 580), 0xe4e6eb, radius: 22)
        p.text("Monthly recurring revenue", 520, 620, size: 32, weight: .semibold)
        for g in 0..<4 { p.fill(p.rect(520, 700 + CGFloat(g) * 100, 1240, 2), 0xf0f1f4) }
        let values: [CGFloat] = [0.30, 0.34, 0.33, 0.41, 0.46, 0.44, 0.52, 0.58, 0.57, 0.66, 0.72, 0.80]
        let reveal = min(max((t - 0.2) / 2.2, 0), 1)
        let pts = values.enumerated().map { CGPoint(x: 540 + CGFloat($0.offset) * 110, y: size.height - (1080 - $0.element * 380)) }
        let shown = max(2, Int((Double(pts.count - 1) * reveal).rounded(.up)) + 1)
        let line = CGMutablePath()
        line.addLines(between: Array(pts.prefix(shown)))
        ctx.addPath(line)
        ctx.setStrokeColor(p.color(0x3b5bdb))
        ctx.setLineWidth(7)
        ctx.setLineJoin(.round); ctx.setLineCap(.round)
        ctx.strokePath()
        if let last = pts.prefix(shown).last {
            p.fill(CGRect(x: last.x - 12, y: last.y - 12, width: 24, height: 24), 0x3b5bdb, radius: 12)
        }
        for (i, m) in ["Jan", "Mar", "May", "Jul", "Sep", "Nov"].enumerated() {
            p.text(m, 525 + CGFloat(i) * 220, 1110, size: 24, color: 0x8a8f9c)
        }
        // API keys
        p.fill(p.rect(1840, 560, 660, 580), 0xffffff, radius: 22)
        p.stroke(p.rect(1840, 560, 660, 580), 0xe4e6eb, radius: 22)
        p.text("API keys", 1880, 620, size: 32, weight: .semibold)
        let keys = [("Live secret key", "nw_live_51HxQ2mR8aT0p4vZ9fQ2b"), ("Test key", "nw_test_4eC39HqLyjWDarjtT1zdp7dc"), ("Webhook secret", "nwhook_8F2kLm0QpX7vN3bY")]
        for (i, k) in keys.enumerated() {
            let y = 650 + CGFloat(i) * 150
            p.text(k.0, 1880, y + 20, size: 24, color: 0x6b7080)
            p.fill(p.rect(1880, y + 36, 580, 70), 0xf6f7f9, radius: 14)
            p.text(k.1, 1906, y + 82, size: 26, color: 0x2a2d35, mono: true)
        }
        // Table
        p.fill(p.rect(480, 1180, 2020, 380), 0xffffff, radius: 22)
        p.stroke(p.rect(480, 1180, 2020, 380), 0xe4e6eb, radius: 22)
        let rows = [("Customer", "Plan", "Seats", "MRR"), ("Acme Co", "Enterprise", "240", "$12,400"),
                    ("Globex", "Business", "85", "$4,250"), ("Initech", "Business", "60", "$3,000")]
        for (i, r) in rows.enumerated() {
            let y = 1250 + CGFloat(i) * 88
            let head = i == 0
            let c: UInt32 = head ? 0x8a8f9c : 0x1d1f24
            let s: CGFloat = head ? 24 : 30
            p.text(r.0, 530, y, size: s, weight: head ? .medium : .semibold, color: c)
            p.text(r.1, 1150, y, size: s, color: head ? c : 0x4a4f5c)
            p.text(r.2, 1700, y, size: s, color: head ? c : 0x4a4f5c)
            p.text(r.3, 2450, y, size: s, weight: head ? .medium : .semibold, color: c, right: true)
            if i < rows.count - 1 { p.fill(p.rect(510, y + 30, 1960, 2), 0xf0f1f4) }
        }
        drawCursor(ctx, at: cursor(path, at: t), height: size.height)
    }

    static func drawCursor(_ ctx: CGContext, at point: CGPoint, height: CGFloat) {
        let s: CGFloat = 2.6
        let pts: [CGPoint] = [(0, 0), (0, 16.5), (4.2, 12.6), (7, 19), (9.6, 17.9), (6.9, 11.6), (12.3, 11.6)].map {
            CGPoint(x: point.x + $0.0 * s, y: height - point.y - $0.1 * s)
        }
        let path = CGMutablePath()
        path.addLines(between: pts)
        path.closeSubpath()
        ctx.setShadow(offset: CGSize(width: 0, height: -3), blur: 6, color: CGColor(gray: 0, alpha: 0.35))
        ctx.addPath(path); ctx.setFillColor(CGColor(gray: 0.05, alpha: 1)); ctx.fillPath()
        ctx.setShadow(offset: .zero, blur: 0, color: nil)
        ctx.addPath(path); ctx.setStrokeColor(CGColor(gray: 1, alpha: 1)); ctx.setLineWidth(2.6); ctx.setLineJoin(.round); ctx.strokePath()
    }

    // MARK: The pretend presenter

    static func drawPresenter(_ ctx: CGContext, _ size: CGSize, _ t: Double) {
        let p = Pen(ctx: ctx, h: size.height)
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let wall = CGGradient(colorsSpace: cs, colors: [p.color(0xd9d3c9), p.color(0xbfb6a8)] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(wall, start: CGPoint(x: 0, y: size.height), end: CGPoint(x: size.width, y: 0), options: [])
        // A shelf and a plant, out of focus.
        p.fill(p.rect(60, 250, 300, 16), 0x9c8b74, radius: 4, alpha: 0.7)
        for (i, c) in [UInt32(0x6d8a96), 0xc96f4a, 0x8a9a6a, 0xd8b45a].enumerated() {
            p.fill(p.rect(80 + CGFloat(i) * 56, 140 - CGFloat(i % 2) * 18, 44, 110 + CGFloat(i % 2) * 18), c, radius: 5, alpha: 0.65)
        }
        p.fill(p.rect(1060, 360, 110, 140), 0xb5764e, radius: 14, alpha: 0.8)
        for i in 0..<5 {
            let a = CGFloat(i) * 0.5 - 1
            ctx.saveGState()
            ctx.translateBy(x: 1115, y: size.height - 360)
            ctx.rotate(by: a * 0.5)
            p.fill(CGRect(x: -22, y: 0, width: 44, height: 170), 0x4f7a4a, radius: 22, alpha: 0.8)
            ctx.restoreGState()
        }
        let sway = CGFloat(sin(t * 1.3)) * 8
        let nod = CGFloat(sin(t * 2.1)) * 4
        let cx = size.width / 2 + sway
        // Shoulders and collar
        p.fill(CGRect(x: cx - 62, y: 150, width: 124, height: 150), 0xcf9a78, radius: 40)
        p.fill(CGRect(x: cx - 340, y: -150, width: 680, height: 360), 0x34405a, radius: 180)
        p.fill(CGRect(x: cx - 62, y: 186, width: 124, height: 26), 0xcf9a78, radius: 13)
        // Head with ears
        let top = size.height - 120 + nod      // top of the head
        let face = CGRect(x: cx - 128, y: top - 330, width: 256, height: 310)
        p.fill(CGRect(x: cx - 150, y: face.midY - 50, width: 50, height: 74), 0xd8a382, radius: 25)
        p.fill(CGRect(x: cx + 100, y: face.midY - 50, width: 50, height: 74), 0xd8a382, radius: 25)
        p.fill(face, 0xe7b897, radius: 124)
        // Hair: a soft cap with a side sweep
        p.fill(CGRect(x: face.minX - 10, y: face.maxY - 110, width: face.width + 20, height: 140), 0x2b211c, radius: 70)
        ctx.saveGState()
        ctx.translateBy(x: cx + 20, y: face.maxY - 70)
        ctx.rotate(by: -0.28)
        p.fill(CGRect(x: -150, y: -40, width: 200, height: 80), 0x2b211c, radius: 40)
        ctx.restoreGState()
        // Brows, eyes (blinking), nose and a talking smile
        let eyeY = face.minY + 175
        for dx: CGFloat in [-52, 52] {
            p.fill(CGRect(x: cx + dx - 26, y: eyeY + 44, width: 52, height: 11), 0x3a2b24, radius: 5)
            let blink = t.truncatingRemainder(dividingBy: 3.4) < 0.12
            p.fill(CGRect(x: cx + dx - 11, y: eyeY + (blink ? 9 : 0), width: 22, height: blink ? 4 : 24), 0x2a2420, radius: blink ? 2 : 11)
            ctx.setStrokeColor(p.color(0x4a4a4f, 0.9)); ctx.setLineWidth(4.5)
            ctx.addEllipse(in: CGRect(x: cx + dx - 40, y: eyeY - 26, width: 80, height: 74)); ctx.strokePath()
        }
        ctx.setStrokeColor(p.color(0x4a4a4f, 0.9)); ctx.setLineWidth(4.5)
        ctx.move(to: CGPoint(x: cx - 12, y: eyeY + 14)); ctx.addLine(to: CGPoint(x: cx + 12, y: eyeY + 14)); ctx.strokePath()
        p.fill(CGRect(x: cx - 9, y: eyeY - 62, width: 18, height: 34), 0xd9a282, radius: 9)
        let open = CGFloat(max(0, sin(t * 10) * sin(t * 2.3))) * 16
        let mouth = CGRect(x: cx - 36, y: face.minY + 52 - open / 2, width: 72, height: 14 + open)
        p.fill(mouth, 0x8f3f36, radius: 7 + open / 2)
        if open < 6 { p.fill(CGRect(x: cx - 36, y: mouth.maxY - 6, width: 72, height: 6), 0xe7b897) }
    }

    // MARK: Projects

    struct Demo {
        var name: String
        var seconds: Double
        var scene: Scene
        var path: Path
        var resolution: ExportResolution = .p720
        var tweak: (inout Project) -> Void
    }

    /// A macOS wallpaper from this Mac, softened.
    static func wall(_ name: String, blur: Double = 0.35) -> BackgroundStyle {
        guard let paper = MacWallpaper.named(name) else { return BackgroundStyle(mode: .preset, presetID: "aurora") }
        var b = BackgroundStyle(mode: .image, presetID: "aurora")
        b.imagePath = paper.path
        b.blur = blur
        return b
    }

    static func base(_ name: String, seconds: Double) -> Project {
        var p = Project(name: name)
        p.duration = seconds
        p.trimEnd = seconds
        p.screenColor = "sRGB"
        p.clips = [Clip(start: 0, end: seconds)]
        p.cameraFile = "camera.mov"
        p.background = wall("Sonoma Horizon")
        p.screen.padding = 0.06
        p.screen.border = 0.5
        p.zoom = ZoomStyle(enabled: false, scale: 1.8)
        p.camera.size = 0.26
        p.camera.mirrored = false
        return p
    }

    static func box(_ kind: OverlayKind, _ start: Double, _ end: Double, at spot: (x: Double, y: Double), w: Double, h: Double,
                    strength: Double = 0.6, spotlight: Bool = false) -> Overlay {
        var o = Overlay(kind: kind, start: start, end: end)
        o.x = spot.x; o.y = spot.y; o.w = w; o.h = h; o.strength = strength
        o.shadow = 0; o.fade = 0.2
        if kind == .highlight { o.color = RGBA(r: 1, g: 0.86, b: 0.2); o.spotlight = spotlight }
        return o
    }

    static func text(_ s: String, _ start: Double, _ end: Double, y: Double = 0.14, size: Double = 0.7) -> Overlay {
        var o = Overlay(kind: .text, start: start, end: end)
        o.text = s; o.y = y; o.size = size; o.boxColor = RGBA(r: 0.06, g: 0.07, b: 0.09, a: 0.78); o.shadow = 0.3
        return o
    }

    // Spots on the other screens.
    static let appFile = (x: 0.055, y: 0.284), pricingLine = (x: 0.36, y: 0.545), terminal = (x: 0.4, y: 0.82)
    static let createKey = (x: 0.922, y: 0.116), firstKey = (x: 0.484, y: 0.2725), teamRow = (x: 0.582, y: 0.6975)
    static let ctaButton = (x: 0.361, y: 0.536), headline = (x: 0.45, y: 0.33)
    static let backlogCard = (x: 0.1445, y: 0.308), progressSlot = (x: 0.383, y: 0.308)

    static var demos: [Demo] {
        let home = (x: 0.62, y: 0.36)
        let drag: Path = [(0, 0.3, 0.5), (0.9, backlogCard.x, backlogCard.y), (1.0, backlogCard.x, backlogCard.y),
                          (3.2, progressSlot.x, progressSlot.y), (6, progressSlot.x + 0.05, progressSlot.y + 0.1)]
        return [
            // Opens on the presenter full screen, then she shrinks into a rounded corner camera over the product.
            Demo(name: "hero", seconds: 12, scene: .dashboard, path: [(0, home.x, home.y), (2.6, home.x, home.y), (4.0, revenue.x, revenue.y), (5.0, revenue.x, revenue.y),
                 (6.0, users.x, users.y), (8.0, chart.x + 0.15, chart.y), (10.4, chart.x + 0.2, chart.y - 0.05), (12, 0.7, 0.4)],
                 resolution: .p1080) { p in
                p.zoom = ZoomStyle(enabled: true, scale: 1.7)
                p.clicks = [ClickEvent(time: 4.2, x: revenue.x, y: revenue.y), ClickEvent(time: 4.8, x: revenue.x, y: revenue.y)]
                p.manualZooms = [ZoomRegion(start: 8.0, end: 10.6, x: 0.6, y: 0.5, scale: 1.6)]
                p.overlays = [text("Q3 revenue review", 2.7, 4.6), box(.highlight, 6.1, 7.7, at: users, w: 0.2, h: 0.15, spotlight: true)]
                p.camera.shape = .square; p.camera.cornerRadius = 0.45; p.camera.size = 0.3
                p.cameraSections = [CameraSection(start: 0, end: 2.4, mode: .fullscreen), CameraSection(start: 10.8, end: 12, mode: .fullscreen)]
                p.captions = [CaptionSegment(start: 0.2, end: 2.3, text: "Hi! Let me walk you through this quarter"),
                              CaptionSegment(start: 2.6, end: 4.8, text: "Here's where revenue landed"),
                              CaptionSegment(start: 5.0, end: 7.8, text: "and active users are up six percent"),
                              CaptionSegment(start: 8.0, end: 10.8, text: "Recurring revenue keeps climbing")]
            },
            Demo(name: "autozoom", seconds: 6, scene: .code, path: [(0, 0.5, 0.5), (0.9, appFile.x, appFile.y), (1.4, appFile.x, appFile.y),
                 (3.0, pricingLine.x, pricingLine.y), (6, pricingLine.x + 0.02, pricingLine.y)]) { p in
                p.camera.visible = false      // this one is about the screen
                p.background = wall("The Lake")
                p.zoom = ZoomStyle(enabled: true, scale: 2)
                p.clicks = [ClickEvent(time: 1.0, x: appFile.x, y: appFile.y), ClickEvent(time: 3.1, x: pricingLine.x, y: pricingLine.y),
                            ClickEvent(time: 3.6, x: pricingLine.x, y: pricingLine.y)]
            },
            Demo(name: "camera", seconds: 7, scene: .board, path: drag) { p in
                p.background = wall("Monterey Graphic")
                p.cameraSections = [CameraSection(start: 1.6, end: 3.2, mode: .position, anchor: CameraAnchor(col: 0, row: 0)),
                                    CameraSection(start: 3.2, end: 5.0, mode: .fullscreen),
                                    CameraSection(start: 5.0, end: 7, mode: .position, anchor: CameraAnchor(col: 2, row: 2))]
                p.camera.anchor = CameraAnchor(col: 2, row: 2)
            },
            Demo(name: "animations", seconds: 6, scene: .board, path: drag) { p in
                p.camera.visible = false      // this one is about the screen
                p.background = wall("Iridescence")
                p.aspect = .wide
                p.clips = [Clip(start: 0, end: 1.9, entry: .rise), Clip(start: 2.0, end: 3.9, entry: .slideLeft), Clip(start: 4.0, end: 6, entry: .pop)]
            },
            Demo(name: "privacy", seconds: 7, scene: .settings, path: [(0, 0.6, 0.5), (1.2, firstKey.x + 0.1, firstKey.y + 0.03),
                 (3.0, teamRow.x - 0.1, teamRow.y + 0.02), (5.0, createKey.x - 0.02, createKey.y + 0.02), (7, createKey.x - 0.02, createKey.y + 0.02)],
                 resolution: .p1080) { p in
                p.camera.visible = false      // this one is about the screen
                p.background = wall("Peak")
                p.overlays = [box(.blur, 0.3, 7, at: firstKey, w: 0.29, h: 0.05, strength: 0.75),
                              box(.highlight, 2.4, 4.6, at: teamRow, w: 0.78, h: 0.065, strength: 0.45),
                              box(.highlight, 4.8, 7, at: createKey, w: 0.13, h: 0.07, spotlight: true)]
            },
            Demo(name: "captions", seconds: 6, scene: .code, path: [(0, 0.5, 0.5), (6, terminal.x, terminal.y)]) { p in
                p.background = wall("The Desert")
                p.captions = [CaptionSegment(start: 0, end: 2, text: "Captions are made on your Mac"),
                              CaptionSegment(start: 2, end: 4, text: "in your own font and colours"),
                              CaptionSegment(start: 4, end: 6, text: "and you can export them as .srt")]
                p.captionStyle.scale = 1.25
                p.captionStyle.textColor = RGBA(hex: 0xffe066)
                p.captionStyle.boxColor = RGBA(r: 0.08, g: 0.08, b: 0.1, a: 0.85)
            },
            Demo(name: "overlays", seconds: 6, scene: .design, path: [(0, 0.6, 0.7), (2, headline.x, headline.y), (6, ctaButton.x, ctaButton.y)]) { p in
                p.camera.visible = false      // this one is about the screen
                p.background = wall("Sonoma")
                var logo = Overlay(kind: .image, start: 1.2, end: 6, x: 0.86, y: 0.2, size: 0.1, shadow: 0.7, file: "icon.png", cornerRadius: 0.22)
                logo.fade = 0.3
                p.overlays = [text("New launch page, first look", 0.2, 6, y: 0.12, size: 0.8), logo]
            },
            Demo(name: "keystrokes", seconds: 6, scene: .code, path: [(0, 0.5, 0.5), (6, 0.55, 0.5)]) { p in
                p.camera.visible = false      // this one is about the screen
                p.background = wall("Solar Gradients")
                p.keystrokes = [KeyStroke(time: 0.6, label: "⌘ P"), KeyStroke(time: 2.4, label: "⌘ ⇧ F"), KeyStroke(time: 4.2, label: "⌃ `")]
                p.showKeystrokes = true
            },
            Demo(name: "vertical", seconds: 6, scene: .design, path: [(0, 0.6, 0.7), (2, ctaButton.x, ctaButton.y), (6, ctaButton.x + 0.03, ctaButton.y)]) { p in
                p.aspect = .vertical
                p.background = wall("Chroma Blue", blur: 0.45)
                p.camera.anchor = CameraAnchor(col: 1, row: 2); p.camera.size = 0.42; p.camera.shape = .circle
                p.manualZooms = [ZoomRegion(start: 0, end: 6, x: 0.42, y: 0.45, scale: 1.4)]
                if ProcessInfo.processInfo.environment["FC_NO_PRESENTER"] != nil { p.camera.visible = false }
                p.captions = [CaptionSegment(start: 0, end: 3, text: "Reels, Shorts and TikTok"), CaptionSegment(start: 3, end: 6, text: "from the same recording")]
            },
        ]
    }

    /// Short looks for the two montages.
    static var looks: [(String, Scene, (inout Project) -> Void)] {
        [
            ("look-lake", .board, { p in p.camera.visible = false; p.background = wall("The Lake", blur: 0.3); p.screen.padding = 0.08 }),
            ("look-monterey", .board, { p in p.camera.visible = false; p.background = wall("Monterey Graphic", blur: 0.5); p.screen.padding = 0.1; p.screen.cornerRadius = 30 }),
            ("look-colour", .board, { p in p.camera.visible = false; p.background = BackgroundStyle(mode: .color, presetID: "aurora", color: RGBA(hex: 0x6867af)); p.screen.padding = 0.08 }),
            ("look-none", .board, { p in p.camera.visible = false; p.background.mode = .none }),
            ("look-desert", .board, { p in p.camera.visible = false; p.background = wall("The Desert", blur: 0.2); p.screen.padding = 0.12; p.screen.border = 1 }),
            ("shape-circle", .design, { p in p.camera.shape = .circle; p.camera.size = 0.3 }),
            ("shape-rounded", .design, { p in p.camera.shape = .square; p.camera.cornerRadius = 0.45; p.camera.size = 0.4 }),
            ("shape-square", .design, { p in p.camera.shape = .square; p.camera.cornerRadius = 0.12; p.camera.size = 0.34; p.camera.anchor = CameraAnchor(col: 0, row: 2) }),
            ("shape-wide", .design, { p in p.camera.shape = .rectangle; p.camera.cornerRadius = 0.3; p.camera.size = 0.3; p.camera.anchor = CameraAnchor(col: 2, row: 0) }),
        ]
    }

    static func run(in folder: URL) async -> Bool {
        do {
            let fm = FileManager.default
            try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
            let work = folder.appendingPathComponent("work")
            try? fm.createDirectory(at: work, withIntermediateDirectories: true)
            if let icon = NSImage(contentsOf: Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/AppIcon.icns"))
                ?? NSImage(contentsOfFile: "Resources/AppIcon.icns"),
               let tiff = icon.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) {
                try rep.representation(using: .png, properties: [:])?.write(to: work.appendingPathComponent("icon.png"))
            }
            // FC_PRESENTER=<movie> uses real camera footage instead of the illustrated presenter.
            if let real = ProcessInfo.processInfo.environment["FC_PRESENTER"] {
                try? fm.removeItem(at: work.appendingPathComponent("camera.mov"))
                try fm.copyItem(at: URL(fileURLWithPath: real), to: work.appendingPathComponent("camera.mov"))
            } else {
                try await SelfTest.writeVideo(work.appendingPathComponent("camera.mov"), size: CGSize(width: 1280, height: 720),
                                              seconds: 12, fps: 30, draw: drawPresenter)
            }
            var jobs: [(String, Path, Double, ExportResolution, (inout Project) -> Void, Scene)] = demos.map { ($0.name, $0.path, $0.seconds, $0.resolution, $0.tweak, $0.scene) }
            let lookPath: Path = [(0, 0.62, 0.36), (2.4, 0.5, 0.45)]
            jobs += looks.map { ($0.0, lookPath, 2.4, .p720, $0.2, $0.1) }
            if let only = ProcessInfo.processInfo.environment["FC_ONLY"] {
                let names = Set(only.split(separator: ",").map(String.init))
                jobs = jobs.filter { names.contains($0.0) }
            }
            var screenFor: [String: String] = [:]
            for job in jobs {
                let key = job.1.map { "\($0.t),\($0.x),\($0.y)" }.joined(separator: ";") + "|\(job.2)|\(job.5)"
                if screenFor[key] == nil {
                    let file = "screen-\(screenFor.count).mov"
                    let path = job.1, scene = job.5
                    try await SelfTest.writeVideo(work.appendingPathComponent(file), size: screenSize, seconds: job.2, fps: 30) { ctx, size, t in
                        draw(scene, ctx, size, t, path: path)
                    }
                    screenFor[key] = file
                }
                var project = base(job.0, seconds: job.2)
                project.screenFile = screenFor[key]!
                job.4(&project)
                let out = folder.appendingPathComponent("\(job.0).mp4")
                try await Exporter().export(ref: ProjectRef(project: project, folder: work), to: out, resolution: job.3, fps: 30) { _ in }
                print("rendered \(job.0)")
                // Keep the hero as a real project (no camera) so the editor can be shown with it.
                if job.0 == "hero" {
                    let dir = folder.appendingPathComponent("editor-demo")
                    try? fm.removeItem(at: dir)
                    try fm.createDirectory(at: dir, withIntermediateDirectories: true)
                    try fm.copyItem(at: work.appendingPathComponent(project.screenFile), to: dir.appendingPathComponent("screen.mov"))
                    var shown = project
                    shown.name = "Q3 revenue review"
                    shown.screenFile = "screen.mov"
                    shown.cameraFile = nil
                    shown.cameraSections = []
                    ProjectStore.save(ProjectRef(project: shown, folder: dir))
                }
            }
            return true
        } catch {
            print("DEMOS FAILED: \(error)")
            return false
        }
    }
}
