import AppKit

struct AreaSelection: Equatable {
    /// In AppKit global coordinates (origin bottom-left of the main screen).
    var rect: CGRect
    var displayID: CGDirectDisplayID
    /// In points relative to the display's top-left corner — what ScreenCaptureKit wants.
    var localRect: CGRect
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? CGMainDisplayID()
    }
}

private final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

/// Dims every screen and lets the user drag out a dashed rectangle.
final class AreaSelector {
    private var windows: [NSWindow] = []
    private var completion: ((AreaSelection?) -> Void)?

    func begin(completion: @escaping (AreaSelection?) -> Void) {
        self.completion = completion
        for screen in NSScreen.screens {
            let window = OverlayWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.isOpaque = false
            window.backgroundColor = .clear
            window.level = .screenSaver
            window.hasShadow = false
            window.isReleasedWhenClosed = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            let view = SelectionView(frame: CGRect(origin: .zero, size: screen.frame.size))
            view.onFinish = { [weak self] rect in
                guard let self else { return }
                guard let rect else { self.finish(nil); return }
                let global = rect.offsetBy(dx: screen.frame.minX, dy: screen.frame.minY)
                let local = CGRect(x: rect.minX, y: screen.frame.height - rect.maxY, width: rect.width, height: rect.height)
                self.finish(AreaSelection(rect: global.integral, displayID: screen.displayID, localRect: local.integral))
            }
            window.contentView = view
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(view)
            windows.append(window)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    private func finish(_ selection: AreaSelection?) {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        let done = completion
        completion = nil
        done?(selection)
    }
}

private final class SelectionView: NSView {
    var onFinish: ((CGRect?) -> Void)?
    private var origin: CGPoint?
    private var selection: CGRect?

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }

    override func mouseDown(with event: NSEvent) {
        origin = convert(event.locationInWindow, from: nil)
        selection = nil
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let origin else { return }
        let p = convert(event.locationInWindow, from: nil)
        selection = CGRect(x: min(origin.x, p.x), y: min(origin.y, p.y),
                           width: abs(p.x - origin.x), height: abs(p.y - origin.y)).intersection(bounds)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if let s = selection, s.width >= 40, s.height >= 40 { onFinish?(s) }
        else { origin = nil; selection = nil; needsDisplay = true }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onFinish?(nil) } else { super.keyDown(with: event) }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.35).setFill()
        bounds.fill()
        guard let s = selection else {
            drawHint("Drag to select an area  ·  Esc to cancel", at: CGPoint(x: bounds.midX, y: bounds.midY))
            return
        }
        NSColor.clear.setFill()
        s.fill(using: .copy)
        let path = NSBezierPath(rect: s.insetBy(dx: -0.5, dy: -0.5))
        path.lineWidth = 1.5
        path.setLineDash([6, 4], count: 2, phase: 0)
        NSColor.white.setStroke()
        path.stroke()
        let labelY = s.minY > 34 ? s.minY - 18 : s.maxY + 18
        drawHint("\(Int(s.width)) × \(Int(s.height))", at: CGPoint(x: s.midX, y: labelY))
    }

    private func drawHint(_ text: String, at center: CGPoint) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let size = (text as NSString).size(withAttributes: attrs)
        let box = CGRect(x: center.x - size.width / 2 - 10, y: center.y - size.height / 2 - 5,
                         width: size.width + 20, height: size.height + 10)
        NSColor.black.withAlphaComponent(0.7).setFill()
        NSBezierPath(roundedRect: box, xRadius: 7, yRadius: 7).fill()
        (text as NSString).draw(at: CGPoint(x: box.minX + 10, y: box.minY + 5), withAttributes: attrs)
    }
}

/// A click-through dashed outline that stays around the chosen area.
final class AreaFrameWindow {
    private var window: NSWindow?

    func show(_ rect: CGRect) {
        hide()
        let frame = rect.insetBy(dx: -4, dy: -4)
        let w = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = false
        w.ignoresMouseEvents = true
        w.level = .floating
        w.isReleasedWhenClosed = false
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        w.contentView = DashedView(frame: CGRect(origin: .zero, size: frame.size))
        w.orderFrontRegardless()
        window = w
    }

    func hide() {
        window?.orderOut(nil)
        window = nil
    }
}

private final class DashedView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(rect: bounds.insetBy(dx: 2, dy: 2))
        path.lineWidth = 2
        NSColor.black.withAlphaComponent(0.5).setStroke()
        path.stroke()
        path.setLineDash([7, 5], count: 2, phase: 0)
        NSColor.white.setStroke()
        path.stroke()
    }
}
