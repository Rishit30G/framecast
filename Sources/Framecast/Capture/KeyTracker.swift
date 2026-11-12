import AppKit
import CoreGraphics

/// A keyboard shortcut pressed during a recording. `time` is seconds from the first frame.
struct KeyStroke: Codable, Equatable {
    var time: Double
    var label: String
}

/// Notes keyboard shortcuts while recording, so they can be shown in the video.
/// Only shortcuts (keys pressed with ⌘, ⌃ or ⌥) and navigation keys are kept —
/// ordinary typing is never recorded, so passwords and messages stay private.
final class KeyTracker {
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var raw: [(time: Double, label: String)] = []

    static var hasAccess: Bool { CGPreflightListenEventAccess() }
    /// Shows the macOS "Input Monitoring" prompt the first time.
    static func requestAccess() { CGRequestListenEventAccess() }

    func start() {
        stop()
        raw = []
        guard Self.hasAccess else { return }
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .tailAppendEventTap, options: .listenOnly,
                                          eventsOfInterest: mask, callback: { _, type, event, info in
            if type == .keyDown, let info, event.getIntegerValueField(.keyboardEventAutorepeat) == 0,
               let label = KeyTracker.label(for: event) {
                let tracker = Unmanaged<KeyTracker>.fromOpaque(info).takeUnretainedValue()
                tracker.raw.append((Double(event.timestamp) / 1_000_000_000, label))
            }
            return Unmanaged.passUnretained(event)
        }, userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return }
        self.tap = tap
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
    }

    func events(relativeTo start: TimeInterval, duration: Double, clock: PauseClock) -> [KeyStroke] {
        raw.compactMap { key -> KeyStroke? in
            guard let t = clock.recordedSeconds(host: key.time, start: start), t >= 0, t <= duration else { return nil }
            return KeyStroke(time: t, label: key.label)
        }
    }

    private static let named: [Int64: String] = [
        36: "↩", 76: "↩", 48: "⇥", 49: "Space", 51: "⌫", 117: "⌦", 53: "Esc",
        123: "←", 124: "→", 125: "↓", 126: "↑", 115: "Home", 119: "End", 116: "Page Up", 121: "Page Down",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
    ]

    /// "⌘ ⇧ P" for a shortcut, or nil for anything that is just typing.
    static func label(for event: CGEvent) -> String? {
        let flags = event.flags
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        let shortcut = flags.contains(.maskCommand) || flags.contains(.maskControl) || flags.contains(.maskAlternate)
        var key = named[code]
        if key == nil {
            guard shortcut else { return nil }
            key = NSEvent(cgEvent: event)?.charactersIgnoringModifiers?.uppercased()
        } else if !shortcut, [49, 51, 117].contains(code) {
            return nil      // space and delete on their own are typing
        }
        guard let key, !key.isEmpty else { return nil }
        var parts: [String] = []
        if flags.contains(.maskControl) { parts.append("⌃") }
        if flags.contains(.maskAlternate) { parts.append("⌥") }
        if flags.contains(.maskShift), shortcut || named[code] != nil { parts.append("⇧") }
        if flags.contains(.maskCommand) { parts.append("⌘") }
        parts.append(key)
        return parts.joined(separator: " ")
    }
}
