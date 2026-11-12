import AppKit

/// A mouse click captured while recording. `x`/`y` are normalised to the recorded
/// region with a top-left origin; `time` is seconds from the first screen frame.
struct ClickEvent: Codable, Equatable {
    var time: Double
    var x: Double
    var y: Double
}

struct ZoomStyle: Codable, Equatable {
    var enabled = true
    /// How far automatic zooms go in: 1 = none, 2 = twice as large.
    var scale: Double = 1.8
}

/// A zoom placed by hand. Times are source seconds; `x`/`y` is the focus point.
struct ZoomRegion: Codable, Equatable, Identifiable {
    var id = UUID()
    var start: Double
    var end: Double
    var x: Double = 0.5
    var y: Double = 0.5
    var scale: Double = 2
}

/// Turns clicks and hand-placed regions into a smooth camera move.
struct ZoomPlan {
    struct AutoSegment {
        var clicks: [ClickEvent]
        var start: Double { clicks[0].time - ZoomPlan.lead }
        var end: Double { clicks[clicks.count - 1].time + ZoomPlan.hold }
    }

    static let lead = 0.15      // start moving just before the click lands
    static let easeIn = 0.7
    static let easeOut = 0.8
    static let hold = 1.6       // stay zoomed this long after the last click
    static let pan = 0.7        // time to glide between two click points

    let autoSegments: [AutoSegment]
    let manual: [ZoomRegion]
    private let scale: Double
    var isEmpty: Bool { autoSegments.isEmpty && manual.isEmpty }

    init(clicks: [ClickEvent], style: ZoomStyle, manual: [ZoomRegion]) {
        var segments: [AutoSegment] = []
        if style.enabled, style.scale > 1.01 {
            for click in clicks.sorted(by: { $0.time < $1.time }) {
                // A click that lands before the previous zoom has fully eased out joins it.
                if let last = segments.last, click.time - Self.lead < last.end + Self.easeOut {
                    segments[segments.count - 1].clicks.append(click)
                } else {
                    segments.append(AutoSegment(clicks: [click]))
                }
            }
        }
        autoSegments = segments
        self.manual = manual
        scale = style.scale
    }

    private static func smooth(_ x: Double) -> Double {
        let t = min(max(x, 0), 1)
        return t * t * t * (t * (t * 6 - 15) + 10)
    }

    /// Zoom factor and focus point (normalised, top-left origin) at source time `time`.
    func state(at time: Double) -> (scale: CGFloat, focus: CGPoint)? {
        var best: (scale: CGFloat, focus: CGPoint)?
        if let s = autoSegments.first(where: { time >= $0.start && time <= $0.end + Self.easeOut }) {
            let amount = time <= s.end ? Self.smooth((time - s.start) / Self.easeIn)
                                       : 1 - Self.smooth((time - s.end) / Self.easeOut)
            var focus = CGPoint(x: s.clicks[0].x, y: s.clicks[0].y)
            for click in s.clicks.dropFirst() {
                let k = CGFloat(Self.smooth((time - (click.time - Self.lead)) / Self.pan))
                focus.x += (CGFloat(click.x) - focus.x) * k
                focus.y += (CGFloat(click.y) - focus.y) * k
            }
            best = (CGFloat(1 + (scale - 1) * amount), focus)
        }
        // A hand-placed zoom wins whenever it is the stronger of the two.
        for region in manual where time >= region.start && time <= region.end {
            let ramp = min(0.6, (region.end - region.start) / 2)
            let amount = min(Self.smooth((time - region.start) / ramp), Self.smooth((region.end - time) / ramp))
            let z = CGFloat(1 + (region.scale - 1) * amount)
            if z >= (best?.scale ?? 1) { best = (z, CGPoint(x: region.x, y: region.y)) }
        }
        return best
    }

    /// The part of the (possibly cropped) image that should fill the frame at `time`.
    /// `full` is the uncropped frame, which focus points are measured against.
    func crop(of extent: CGRect, full: CGRect, at time: Double) -> CGRect? {
        guard let (zoom, focus) = state(at: time), zoom > 1.001 else { return nil }
        let w = extent.width / zoom, h = extent.height / zoom
        let cx = full.minX + focus.x * full.width
        let cy = full.minY + (1 - focus.y) * full.height
        let x = min(max(cx - w / 2, extent.minX), extent.maxX - w)
        let y = min(max(cy - h / 2, extent.minY), extent.maxY - h)
        return CGRect(x: x, y: y, width: w, height: h)
    }
}

/// Listens for mouse clicks anywhere on screen while a recording is running.
final class ClickTracker {
    private var monitor: Any?
    private var region: CGRect = .zero
    private var raw: [(time: TimeInterval, x: Double, y: Double)] = []

    /// `region` is the recorded area in AppKit global coordinates.
    func start(region: CGRect) {
        stop()
        self.region = region
        raw = []
        guard region.width > 0, region.height > 0 else { return }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
            guard let self else { return }
            let p = NSEvent.mouseLocation
            let x = (p.x - self.region.minX) / self.region.width
            let y = (self.region.maxY - p.y) / self.region.height
            guard (0...1).contains(x), (0...1).contains(y) else { return }
            self.raw.append((event.timestamp, Double(x), Double(y)))
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    /// Clicks relative to the moment the first frame was captured (both use system uptime).
    func events(relativeTo start: TimeInterval, duration: Double, clock: PauseClock) -> [ClickEvent] {
        raw.compactMap { click -> ClickEvent? in
            guard let t = clock.recordedSeconds(host: click.time, start: start) else { return nil }
            return ClickEvent(time: t, x: click.x, y: click.y)
        }
        .filter { $0.time >= 0 && $0.time <= duration }
    }
}
