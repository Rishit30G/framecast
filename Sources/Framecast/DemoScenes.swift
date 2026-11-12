import AppKit

/// More pretend screens for the website clips, so every clip isn't the same dashboard.
extension Demos {
    enum Scene { case dashboard, code, settings, design, board }

    static func draw(_ scene: Scene, _ ctx: CGContext, _ size: CGSize, _ t: Double, path: Path) {
        switch scene {
        case .dashboard: drawDashboard(ctx, size, t, path: path); return
        case .code: drawCode(ctx, size, t)
        case .settings: drawSettings(ctx, size, t)
        case .design: drawDesign(ctx, size, t)
        case .board: drawBoard(ctx, size, t, path: path)
        }
        drawCursor(ctx, at: cursor(path, at: t), height: size.height)
    }

    static func chrome(_ p: Pen, dark: Bool, url: String) {
        p.fill(p.rect(0, 0, 2560, 92), dark ? 0x202126 : 0xf1f2f4)
        p.fill(p.rect(0, 91, 2560, 2), dark ? 0x2c2d33 : 0xe2e4e8)
        for (i, c) in [UInt32(0xff5f57), 0xfebc2e, 0x28c840].enumerated() { p.fill(p.rect(34 + CGFloat(i) * 42, 32, 26, 26), c, radius: 13) }
        p.fill(p.rect(860, 22, 840, 48), dark ? 0x2a2b31 : 0xffffff, radius: 24)
        p.text(url, 1110, 56, size: 26, color: dark ? 0x9a9ea8 : 0x5d6270)
    }

    // MARK: Code editor

    static func drawCode(_ ctx: CGContext, _ size: CGSize, _ t: Double) {
        let p = Pen(ctx: ctx, h: size.height)
        p.fill(CGRect(origin: .zero, size: size), 0x1b1c21)
        p.fill(p.rect(0, 0, 2560, 92), 0x202126)
        for (i, c) in [UInt32(0xff5f57), 0xfebc2e, 0x28c840].enumerated() { p.fill(p.rect(34 + CGFloat(i) * 42, 32, 26, 26), c, radius: 13) }
        p.text("northwind-web — App.tsx", 1100, 58, size: 26, color: 0x9a9ea8)
        // File tree
        p.fill(p.rect(0, 92, 420, 1508), 0x17181c)
        p.text("EXPLORER", 40, 150, size: 22, weight: .semibold, color: 0x6f737d)
        let files = [("src", 0, true), ("components", 1, true), ("Header.tsx", 2, false), ("Pricing.tsx", 2, false), ("App.tsx", 1, false),
                     ("api.ts", 1, false), ("styles.css", 1, false), ("package.json", 0, false), ("README.md", 0, false)]
        for (i, f) in files.enumerated() {
            let y = 220 + CGFloat(i) * 62
            if f.0 == "App.tsx" { p.fill(p.rect(16, y - 40, 388, 56), 0x2a2d3a, radius: 10) }
            p.fill(p.rect(44 + CGFloat(f.1) * 34, y - 26, 22, 22), f.2 ? 0x7f8fa6 : (f.0.hasSuffix("tsx") ? 0x4fa8e0 : 0xd9a514), radius: 5)
            p.text(f.0, 80 + CGFloat(f.1) * 34, y - 6, size: 27, color: f.0 == "App.tsx" ? 0xffffff : 0xb8bcc6)
        }
        // Tabs
        p.fill(p.rect(420, 92, 2140, 72), 0x1f2025)
        p.fill(p.rect(420, 92, 300, 72), 0x1b1c21)
        p.text("App.tsx", 470, 140, size: 26, color: 0xffffff)
        p.text("api.ts", 790, 140, size: 26, color: 0x7d818b)
        // Code
        typealias Tok = (String, UInt32)
        let K: UInt32 = 0xc678dd, S: UInt32 = 0x98c379, F: UInt32 = 0x61afef, T: UInt32 = 0xe5c07b, D: UInt32 = 0xd7dae0, C: UInt32 = 0x6b717d
        let lines: [[Tok]] = [
            [("import", K), (" { useState } ", D), ("from", K), (" \"react\";", S)],
            [("import", K), (" { Pricing } ", D), ("from", K), (" \"./components/Pricing\";", S)],
            [],
            [("// Show yearly prices by default", C)],
            [("export default function", K), (" App", F), ("() {", D)],
            [("  const", K), (" [yearly, setYearly] = ", D), ("useState", F), ("(", D), ("true", T), (");", D)],
            [("  const", K), (" plans = ", D), ("usePlans", F), ("({ yearly });", D)],
            [],
            [("  return", K), (" (", D)],
            [("    <", D), ("main", T), (" className=", D), ("\"page\"", S), (">", D)],
            [("      <", D), ("Header", T), (" />", D)],
            [("      <", D), ("Pricing", T), (" plans={plans} onToggle={setYearly} />", D)],
            [("    </", D), ("main", T), (">", D)],
            [("  );", D)],
            [("}", D)],
        ]
        let typed = min(max((t - 0.4) / 3.0, 0), 1)
        for (i, line) in lines.enumerated() {
            let y = 240 + CGFloat(i) * 58
            if i == 6 { p.fill(p.rect(420, y - 42, 2140, 58), 0x262832) }
            p.text("\(i + 1)", 520, y, size: 26, color: 0x4d515b, mono: true, right: true)
            var x: CGFloat = 580
            var chars = Int.max
            if i == 11 { chars = Int(Double(line.map { $0.0.count }.reduce(0, +)) * typed) }
            for tok in line {
                guard chars > 0 else { break }
                let s = String(tok.0.prefix(chars))
                chars -= tok.0.count
                p.text(s, x, y, size: 30, color: tok.1, mono: true)
                x += CGFloat(s.count) * 18.06
            }
        }
        // Terminal
        p.fill(p.rect(420, 1150, 2140, 450), 0x141519)
        p.fill(p.rect(420, 1150, 2140, 2), 0x2c2d33)
        p.text("TERMINAL", 470, 1205, size: 22, weight: .semibold, color: 0x8a8f9c)
        let out = [("$ npm run dev", 0xd7dae0), ("  ready  started server on http://localhost:3000", 0x98c379), ("  event  compiled client and server successfully in 412 ms", 0x7d818b)] as [(String, UInt32)]
        for (i, o) in out.enumerated() where t > 0.6 + Double(i) * 0.7 {
            p.text(o.0, 470, 1270 + CGFloat(i) * 52, size: 27, color: o.1, mono: true)
        }
    }

    // MARK: Settings with secrets

    static func drawSettings(_ ctx: CGContext, _ size: CGSize, _ t: Double) {
        let p = Pen(ctx: ctx, h: size.height)
        p.fill(CGRect(origin: .zero, size: size), 0xffffff)
        chrome(p, dark: false, url: "app.northwind.io/settings/api")
        p.fill(p.rect(0, 93, 420, 1507), 0xf8f9fb)
        p.text("Settings", 48, 180, size: 36, weight: .bold)
        for (i, item) in ["Profile", "Team", "Billing", "API keys", "Webhooks", "Security"].enumerated() {
            let y = 280 + CGFloat(i) * 76
            if i == 3 { p.fill(p.rect(24, y - 46, 372, 64), 0xe8edfb, radius: 14) }
            p.text(item, 56, y - 6, size: 30, weight: i == 3 ? .semibold : .regular, color: i == 3 ? 0x1d3bb8 : 0x4a4f5c)
        }
        p.text("API keys", 480, 200, size: 60, weight: .bold)
        p.text("Keys give full access to your account. Keep them secret.", 480, 252, size: 28, color: 0x7a7f8c)
        p.fill(p.rect(2200, 150, 280, 72), 0x3b5bdb, radius: 16)
        p.text("+ Create key", 2240, 196, size: 27, weight: .semibold, color: 0xffffff)
        // Keys
        p.fill(p.rect(480, 290, 2020, 470), 0xffffff, radius: 22); p.stroke(p.rect(480, 290, 2020, 470), 0xe4e6eb, radius: 22)
        let keys = [("Production", "nw_live_51HxQ2mR8aT0p4vZ9fQ2b", "Used 2 min ago"), ("Staging", "nw_test_4eC39HqLyjWDarjtT1zdp7", "Used yesterday"), ("CI pipeline", "nw_live_7Tq0mXb2Lr9Kd5Vw3Nc8", "Used 3 days ago")]
        p.text("Name", 530, 352, size: 24, weight: .medium, color: 0x8a8f9c); p.text("Secret", 900, 352, size: 24, weight: .medium, color: 0x8a8f9c)
        p.text("Last used", 2440, 352, size: 24, weight: .medium, color: 0x8a8f9c, right: true)
        for (i, k) in keys.enumerated() {
            let y = 450 + CGFloat(i) * 100
            p.fill(p.rect(510, y - 68, 1960, 2), 0xf0f1f4)
            p.text(k.0, 530, y, size: 30, weight: .semibold)
            p.fill(p.rect(890, y - 46, 700, 64), 0xf6f7f9, radius: 12)
            p.text(k.1, 914, y - 2, size: 27, color: 0x2a2d35, mono: true)
            p.text(k.2, 2440, y, size: 27, color: 0x6b7080, right: true)
        }
        // Team
        p.fill(p.rect(480, 820, 2020, 690), 0xffffff, radius: 22); p.stroke(p.rect(480, 820, 2020, 690), 0xe4e6eb, radius: 22)
        p.text("Who can see these keys", 530, 890, size: 32, weight: .semibold)
        let people = [("Alex Moreno", "alex.moreno@northwind.io", "Owner", 0x3b5bdb), ("Priya Shah", "priya.shah@northwind.io", "Admin", 0xe2852b),
                      ("Sam Lee", "sam.lee@northwind.io", "Developer", 0x15998f), ("Jordan Kim", "jordan.kim@northwind.io", "Developer", 0xc0392b)] as [(String, String, String, UInt32)]
        for (i, m) in people.enumerated() {
            let y = 1010 + CGFloat(i) * 120
            p.fill(p.rect(530, y - 52, 72, 72), m.3, radius: 36)
            p.text(String(m.0.prefix(1)), 552, y - 4, size: 32, weight: .bold, color: 0xffffff)
            p.text(m.0, 640, y - 4, size: 30, weight: .semibold)
            p.text(m.1, 1150, y - 4, size: 28, color: 0x4a4f5c)
            p.fill(p.rect(2280, y - 46, 170, 56), 0xf1f2f6, radius: 28)
            p.text(m.2, 2365 - CGFloat(m.2.count) * 7.5, y - 8, size: 24, weight: .medium, color: 0x4a4f5c)
        }
    }

    // MARK: Design tool

    static func drawDesign(_ ctx: CGContext, _ size: CGSize, _ t: Double) {
        let p = Pen(ctx: ctx, h: size.height)
        p.fill(CGRect(origin: .zero, size: size), 0xe8e8eb)
        p.fill(p.rect(0, 0, 2560, 92), 0x2b2c31)
        for (i, c) in [UInt32(0xff5f57), 0xfebc2e, 0x28c840].enumerated() { p.fill(p.rect(34 + CGFloat(i) * 42, 32, 26, 26), c, radius: 13) }
        p.text("Launch page — Draft", 1110, 58, size: 26, weight: .medium, color: 0xd0d2d8)
        p.fill(p.rect(2290, 22, 200, 50), 0x3b5bdb, radius: 12); p.text("Share", 2350, 56, size: 26, weight: .semibold, color: 0xffffff)
        // Layers
        p.fill(p.rect(0, 92, 380, 1508), 0x2b2c31)
        p.text("Layers", 36, 160, size: 26, weight: .semibold, color: 0xd0d2d8)
        for (i, l) in ["Hero", "Headline", "Subhead", "Button", "Product shot", "Logos", "Footer"].enumerated() {
            let y = 230 + CGFloat(i) * 60
            if i == 3 { p.fill(p.rect(16, y - 40, 348, 54), 0x3b5bdb, radius: 10, alpha: 0.35) }
            p.fill(p.rect(40, y - 26, 22, 22), 0x7f8396, radius: 4)
            p.text(l, 80, y - 6, size: 26, color: 0xd0d2d8)
        }
        // Properties
        p.fill(p.rect(2180, 92, 380, 1508), 0x2b2c31)
        p.text("Button", 2216, 160, size: 28, weight: .semibold, color: 0xffffff)
        for (i, row) in [("Fill", "#3B5BDB"), ("Radius", "16"), ("Padding", "20 32"), ("Font", "Inter 600"), ("Size", "28")].enumerated() {
            let y = 250 + CGFloat(i) * 90
            p.text(row.0, 2216, y, size: 24, color: 0x9a9ea8)
            p.fill(p.rect(2340, y - 40, 190, 56), 0x37383e, radius: 10)
            p.text(row.1, 2360, y - 2, size: 24, color: 0xe6e7eb)
        }
        p.fill(p.rect(2360, 256 - 34, 30, 30), 0x3b5bdb, radius: 6)
        // Artboard
        p.text("Desktop · 1440", 620, 190, size: 22, color: 0x7b7f89)
        p.fill(p.rect(620, 210, 1500, 1300), 0xffffff, radius: 6)
        p.fill(p.rect(680, 260, 120, 40), 0x111113, radius: 8)
        for i in 0..<4 { p.fill(p.rect(1500 + CGFloat(i) * 130, 270, 90, 20), 0xd6d8de, radius: 10) }
        p.text("Ship your next", 760, 520, size: 92, weight: .bold)
        p.text("launch in a day.", 760, 630, size: 92, weight: .bold)
        p.fill(p.rect(760, 690, 820, 26), 0xd6d8de, radius: 13); p.fill(p.rect(760, 736, 620, 26), 0xd6d8de, radius: 13)
        let pulse = CGFloat(0.5 + 0.5 * sin(t * 3))
        p.fill(p.rect(760, 810, 330, 96), 0x3b5bdb, radius: 16)
        p.stroke(p.rect(752, 802, 346, 112), 0x3b5bdb, radius: 20, width: 3 + 2 * pulse)
        p.text("Start free trial", 800, 870, size: 34, weight: .semibold, color: 0xffffff)
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let g = CGGradient(colorsSpace: cs, colors: [p.color(0x8a4fd3), p.color(0xe58ac6), p.color(0xf9c15c)] as CFArray, locations: nil)!
        ctx.saveGState()
        ctx.addPath(CGPath(roundedRect: p.rect(680, 980, 1380, 470), cornerWidth: 24, cornerHeight: 24, transform: nil)); ctx.clip()
        ctx.drawLinearGradient(g, start: CGPoint(x: 680, y: size.height - 980), end: CGPoint(x: 2060, y: size.height - 1450), options: [])
        ctx.restoreGState()
        p.fill(p.rect(840, 1060, 1060, 330), 0xffffff, radius: 18, alpha: 0.85)
    }

    // MARK: Project board

    static func drawBoard(_ ctx: CGContext, _ size: CGSize, _ t: Double, path: Path) {
        let p = Pen(ctx: ctx, h: size.height)
        p.fill(CGRect(origin: .zero, size: size), 0xf6f7f9)
        chrome(p, dark: false, url: "app.northwind.io/board/q3-launch")
        p.text("Q3 launch", 80, 200, size: 60, weight: .bold)
        p.text("24 tasks · 6 people", 80, 252, size: 28, color: 0x7a7f8c)
        for i in 0..<5 { p.fill(p.rect(2080 + CGFloat(i) * 62, 160, 76, 76), [0x3b5bdb, 0xe2852b, 0x15998f, 0xc0392b, 0x8a4fd3][i], radius: 38); p.stroke(p.rect(2080 + CGFloat(i) * 62, 160, 76, 76), 0xf6f7f9, radius: 38, width: 5) }
        let cols = ["Backlog", "In progress", "Review", "Done"]
        let tags: [(String, UInt32, UInt32)] = [("Design", 0xf3e8ff, 0x7c3aed), ("Web", 0xe0ecff, 0x2563eb), ("Copy", 0xfff1db, 0xb45309), ("Bug", 0xfde2e2, 0xc0392b)]
        let cards = [["Pricing page hero", "Write launch email", "Onboarding checklist"], ["Signup flow polish", "Changelog post"],
                     ["Analytics events", "Mobile nav fix"], ["Brand refresh", "Docs search", "Status page"]]
        // A card being dragged from Backlog to In progress, following the pointer.
        let drag = t >= 1.0 && t <= 3.2
        let moved = t > 3.2
        for (c, title) in cols.enumerated() {
            let x = 80 + CGFloat(c) * 610
            p.fill(p.rect(x, 300, 580, 1230), 0xeef0f3, radius: 24)
            p.text(title, x + 30, 362, size: 30, weight: .semibold)
            var list = cards[c]
            if moved && c == 0 { list.removeFirst() }
            if moved && c == 1 { list.insert(cards[0][0], at: 0) }
            if drag && c == 0 { list.removeFirst() }
            p.text("\(list.count)", x + 540, 362, size: 26, color: 0x8a8f9c, right: true)
            for (i, name) in list.enumerated() {
                let y = 400 + CGFloat(i) * 210
                drawBoardCard(p, x: x + 20, y: y, name: name, tag: tags[(c + i) % tags.count], seed: c * 3 + i)
            }
        }
        if drag {
            let at = cursor(path, at: t)
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0, height: -18), blur: 40, color: CGColor(gray: 0, alpha: 0.25))
            drawBoardCard(p, x: at.x - 200, y: at.y - 60, name: cards[0][0], tag: tags[0], seed: 0)
            ctx.restoreGState()
        }
    }

    static func drawBoardCard(_ p: Pen, x: CGFloat, y: CGFloat, name: String, tag: (String, UInt32, UInt32), seed: Int) {
        p.fill(p.rect(x, y, 540, 186), 0xffffff, radius: 18)
        p.stroke(p.rect(x, y, 540, 186), 0xe4e6eb, radius: 18)
        p.fill(p.rect(x + 28, y + 28, CGFloat(tag.0.count) * 15 + 40, 44), tag.1, radius: 22)
        p.text(tag.0, x + 48, y + 59, size: 23, weight: .semibold, color: tag.2)
        p.text(name, x + 28, y + 122, size: 31, weight: .semibold)
        p.fill(p.rect(x + 28, y + 140, 160, 14), 0xeceef2, radius: 7)
        p.fill(p.rect(x + 468, y + 118, 48, 48), [0x3b5bdb, 0xe2852b, 0x15998f, 0xc0392b, 0x8a4fd3][seed % 5], radius: 24)
    }
}
