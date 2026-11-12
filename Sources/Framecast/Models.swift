import AVFoundation
import Foundation
import CoreGraphics

// MARK: - Styles

enum CanvasAspect: String, Codable, CaseIterable, Identifiable {
    /// Follows the recording's own shape, so the background shows evenly on every side.
    case auto = "Auto"
    case wide = "16:9", standard = "4:3", square = "1:1", vertical = "9:16"
    var id: String { rawValue }

    /// Width / height.
    var ratio: CGFloat {
        switch self {
        case .auto, .wide: return 16.0 / 9.0
        case .standard: return 4.0 / 3.0
        case .square: return 1
        case .vertical: return 9.0 / 16.0
        }
    }

    /// Canvas size whose short side is `shortSide` pixels (rounded to even numbers).
    func size(shortSide: CGFloat) -> CGSize {
        func even(_ v: CGFloat) -> CGFloat { (v / 2).rounded() * 2 }
        if ratio >= 1 { return CGSize(width: even(shortSide * ratio), height: even(shortSide)) }
        return CGSize(width: even(shortSide), height: even(shortSide / ratio))
    }
}

enum BackgroundMode: String, Codable {
    case preset, color, image
    /// No wallpaper at all: the video is exactly the recording, edge to edge.
    case none
}

struct RGBA: Codable, Equatable {
    var r: Double, g: Double, b: Double, a: Double = 1
    init(r: Double, g: Double, b: Double, a: Double = 1) { self.r = r; self.g = g; self.b = b; self.a = a }
    init(hex: UInt32) {
        r = Double((hex >> 16) & 0xff) / 255
        g = Double((hex >> 8) & 0xff) / 255
        b = Double(hex & 0xff) / 255
    }
    var cgColor: CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: a) }
}

struct BackgroundStyle: Codable, Equatable {
    var mode: BackgroundMode = .preset
    var presetID: String = "aurora"
    var color = RGBA(hex: 0x1f2937)
    var imagePath: String?
    /// Softens a wallpaper so it doesn't compete with the recording. 0 (or nil) = sharp, 1 = very soft.
    var blur: Double?
}

struct ScreenStyle: Codable, Equatable {
    /// Fraction of the canvas' short side left empty around the recording.
    var padding: Double = 0.07
    /// Corner radius in pixels at 1080p.
    var cornerRadius: Double = 18
    /// 0 = no shadow, 1 = strongest.
    var shadow: Double = 0.6
    /// The part of the recording to show (normalised, top-left origin). nil = everything.
    var crop: CGRect?
    /// A thin translucent white line around the recording. 0 (or nil) = none, 1 = strongest.
    var border: Double?
}

enum CameraShape: String, Codable, CaseIterable, Identifiable {
    case circle, square, rectangle
    var id: String { rawValue }
    var label: String { self == .square ? "Rounded" : rawValue.capitalized }
    var symbol: String {
        switch self {
        case .circle: return "circle"
        case .square: return "app"
        case .rectangle: return "rectangle"
        }
    }
}

/// 3x3 grid position. `col` and `row` are 0, 1 or 2 (left→right, top→bottom).
struct CameraAnchor: Codable, Equatable, Hashable {
    var col: Int
    var row: Int
}

struct CameraStyle: Codable, Equatable {
    var visible = true
    var shape: CameraShape = .square
    /// 0 = sharp corners, 1 = fully round. Ignored for the circle.
    var cornerRadius: Double = 0.45
    /// Height as a fraction of the canvas' short side.
    var size: Double = 0.24
    var anchor = CameraAnchor(col: 2, row: 2)
    /// Set when the user drags the camera somewhere freely (normalised, top-left origin).
    var customCenter: CGPoint?
    var mirrored = true
    var shadow = true
    /// 0…1. Absent in older projects, where `shadow` was just on or off.
    var shadowAmount: Double?
    var shadowStrength: Double {
        get { shadowAmount ?? (shadow ? 0.6 : 0) }
        set { shadowAmount = newValue; shadow = newValue > 0.01 }
    }
}

enum CameraSectionMode: String, Codable, CaseIterable, Identifiable {
    case position, fullscreen, hidden
    var id: String { rawValue }
    var label: String {
        switch self {
        case .position: return "Corner"
        case .fullscreen: return "Fullscreen"
        case .hidden: return "Hidden"
        }
    }
}

/// A stretch of the recording (source seconds) where the camera is laid out differently.
struct CameraSection: Codable, Equatable, Identifiable {
    var id = UUID()
    var start: Double
    var end: Double
    var mode: CameraSectionMode = .position
    var anchor = CameraAnchor(col: 0, row: 2)
}

struct CaptionSegment: Codable, Equatable, Identifiable {
    var id = UUID()
    var start: Double
    var end: Double
    var text: String
}

struct CaptionStyle: Codable, Equatable {
    var visible = true
    /// Multiplier on the default text size.
    var scale: Double = 1
    /// A font file the user picked (absolute path). nil = the system font.
    var fontPath: String?
    var textColor: RGBA?
    /// The box behind the text; its alpha is the box opacity.
    var boxColor: RGBA?
}

/// A kept stretch of the recording, in source seconds. The timeline is these, back to back.
enum ClipAnimation: String, Codable, CaseIterable, Identifiable {
    case fade, rise, slideLeft, slideRight, slideUp, slideDown, zoomIn, zoomOut, blur, pop
    var id: String { rawValue }
    var label: String {
        switch self {
        case .fade: return "Fade"
        case .rise: return "Fade Up"
        case .slideLeft: return "Slide Left"
        case .slideRight: return "Slide Right"
        case .slideUp: return "Slide Up"
        case .slideDown: return "Slide Down"
        case .zoomIn: return "Zoom In"
        case .zoomOut: return "Zoom Out"
        case .blur: return "Blur"
        case .pop: return "Pop"
        }
    }
    var symbol: String {
        switch self {
        case .fade: return "circle.lefthalf.filled"
        case .rise: return "arrow.up.circle"
        case .slideLeft: return "arrow.left"
        case .slideRight: return "arrow.right"
        case .slideUp: return "arrow.up"
        case .slideDown: return "arrow.down"
        case .zoomIn: return "arrow.up.left.and.arrow.down.right"
        case .zoomOut: return "arrow.down.right.and.arrow.up.left"
        case .blur: return "drop"
        case .pop: return "sparkle"
        }
    }
}

struct Clip: Codable, Equatable, Identifiable {
    var id = UUID()
    var start: Double
    var end: Double
    /// How the clip arrives and leaves. nil = a plain cut.
    var entry: ClipAnimation?
    var exit: ClipAnimation?
    /// Playback speed: 2 = twice as fast, 0.5 = half speed. nil = normal.
    var speed: Double?
    var rate: Double { min(max(speed ?? 1, 0.1), 16) }
    /// Seconds of the raw recording this clip covers.
    var sourceLength: Double { max(end - start, 0) }
    /// Seconds it takes up in the finished video.
    var length: Double { sourceLength / rate }
}

/// Converts between "source" time (the raw recording) and "output" time (after cuts).
struct TimeMap: Equatable {
    var clips: [Clip]
    var duration: Double { clips.reduce(0) { $0 + $1.length } }

    func source(_ output: Double) -> Double {
        var t = max(output, 0)
        for clip in clips {
            if t <= clip.length { return clip.start + t * clip.rate }
            t -= clip.length
        }
        return clips.last?.end ?? 0
    }

    /// Source times that were cut away land on the cut itself.
    func output(_ source: Double) -> Double {
        var acc = 0.0
        for clip in clips {
            if source < clip.start { return acc }
            if source <= clip.end { return acc + (source - clip.start) / clip.rate }
            acc += clip.length
        }
        return acc
    }

    func outputStart(of index: Int) -> Double { clips.prefix(index).reduce(0) { $0 + $1.length } }

    /// The entry/exit animation playing at output time `t`, with how much of the picture
    /// is "there" (0 = gone, 1 = fully in place).
    func animation(atOutput t: Double, duration: Double) -> (kind: ClipAnimation, presence: Double)? {
        var acc = 0.0
        for clip in clips {
            if t < acc + clip.length {
                let local = t - acc
                let d = min(duration, clip.length / 2)
                guard d > 0.01 else { return nil }
                if let entry = clip.entry, local < d { return (entry, local / d) }
                if let exit = clip.exit, clip.length - local < d { return (exit, (clip.length - local) / d) }
                return nil
            }
            acc += clip.length
        }
        return nil
    }

    func index(atOutput t: Double) -> Int? {
        var acc = 0.0
        for (i, clip) in clips.enumerated() {
            if t < acc + clip.length || i == clips.count - 1 { return i }
            acc += clip.length
        }
        return nil
    }
}

enum OverlayKind: String, Codable {
    case text, image
    /// Blurs part of the recording (to hide something private).
    case blur
    /// Draws attention to part of the recording: a marker tint, or a spotlight that dims the rest.
    case highlight

    /// Blur and highlight boxes are pinned to the recording itself, so zooms carry them along.
    var isRegion: Bool { self == .blur || self == .highlight }
}

/// How colours are stored. Recordings and exports use sRGB so they look the same as the screen did.
enum ColorMode {
    /// `FC_COLOR=old` restores the previous behaviour, for comparing.
    static let legacy = ProcessInfo.processInfo.environment["FC_COLOR"] == "old"
    /// The tone curve written into video files.
    static var transfer: String {
        legacy ? AVVideoTransferFunction_ITU_R_709_2 : (kCVImageBufferTransferFunction_sRGB as String)
    }
}

/// A piece of text or a picture placed on top of the video for a while.
/// Times are on the edited timeline; `x`/`y` is the centre (normalised, top-left origin).
struct Overlay: Codable, Equatable, Identifiable {
    var id = UUID()
    var kind: OverlayKind
    var start: Double
    var end: Double
    var x: Double = 0.5
    var y: Double = 0.5
    /// Text: a multiplier on the default size. Image: width as a fraction of the frame.
    var size: Double = 1
    var opacity: Double = 1
    /// 0 = no shadow, 1 = strongest.
    var shadow: Double = 0.4
    /// Seconds to fade in and out.
    var fade: Double = 0.25

    var text = "Your text"
    var fontPath: String?
    var color = RGBA(r: 1, g: 1, b: 1)
    /// A box behind the text; nil = none.
    var boxColor: RGBA?

    /// Image file inside the project folder.
    var file: String?
    /// 0 = square corners, 0.5 = fully round.
    var cornerRadius: Double = 0

    /// Blur / highlight boxes: size as a fraction of the recording (`x`/`y` is then the
    /// centre within the recording rather than the whole frame).
    var w: Double?
    var h: Double?
    /// Blur amount, marker strength or how dark the spotlight makes the rest. 0…1.
    var strength: Double?
    /// Highlight only: dim everything outside the box instead of tinting inside it.
    var spotlight: Bool?

    var boxWidth: Double { min(max(w ?? 0.3, 0.02), 1) }
    var boxHeight: Double { min(max(h ?? 0.12, 0.02), 1) }
    var amount: Double { min(max(strength ?? 0.6, 0), 1) }
}

/// Music or a sound effect on the edited timeline.
struct AudioClip: Codable, Equatable, Identifiable {
    var id = UUID()
    /// File name inside the project folder, or an absolute path.
    var file: String
    var name: String
    var start: Double
    /// Where in the file playback begins.
    var offset: Double = 0
    var duration: Double
    var fileDuration: Double
    var volume: Double = 0.6
    var fadeIn: Double = 0
    var fadeOut: Double = 0
}

struct VoiceClip: Codable, Equatable, Identifiable {
    var id = UUID()
    var file: String
    /// Where the clip starts on the edited timeline, in seconds.
    var start: Double
}

struct AudioSettings: Codable, Equatable {
    var micVolume: Double = 1
    var systemVolume: Double = 1
    var musicVolume: Double = 0.35
    var voiceVolume: Double = 1
    /// Absolute path of an imported audio file.
    var musicPath: String?
    var voiceClips: [VoiceClip] = []
    /// Use the noise-reduced copy of the microphone recording.
    var voiceCleanup: Bool?
}

// MARK: - Project

struct Project: Codable, Equatable, Identifiable {
    var id = UUID()
    var name: String
    var createdAt = Date()

    var screenFile = "screen.mov"
    var cameraFile: String?
    var micFile: String?
    /// Seconds between the first screen frame and the first camera frame / mic sample.
    var cameraOffset: Double = 0
    var micOffset: Double = 0

    var duration: Double = 0
    var trimStart: Double = 0
    var trimEnd: Double = 0

    var aspect: CanvasAspect = .auto
    var background = BackgroundStyle()
    var screen = ScreenStyle()
    var camera = CameraStyle()
    var audio = AudioSettings()
    var captions: [CaptionSegment] = []
    var captionStyle = CaptionStyle()

    /// Clicks captured while recording (absent in recordings made before auto-zoom existed).
    var clicks: [ClickEvent]?
    var zoom: ZoomStyle?
    var zoomStyle: ZoomStyle {
        get { zoom ?? ZoomStyle() }
        set { zoom = newValue }
    }
    /// Zooms the user placed by hand.
    var manualZooms: [ZoomRegion]?
    var cameraSections: [CameraSection]?
    /// Seconds each entry/exit animation lasts.
    var animationDuration: Double?
    var overlays: [Overlay]?
    var audioClips: [AudioClip]?
    /// Keyboard shortcuts pressed while recording (source seconds).
    var keystrokes: [KeyStroke]?
    var showKeystrokes: Bool?
    /// Pixel size of the screen recording, filled in the first time it is opened.
    var sourceSize: CGSize?
    /// "sRGB" for recordings made with accurate colour. Older ones (nil) hold the display's
    /// wide-colour values under a standard-video label and are corrected when drawn.
    var screenColor: String?

    /// The output frame for a given short side. With no background it follows the
    /// (cropped) recording; otherwise it follows the chosen canvas shape.
    func canvasSize(shortSide: CGFloat) -> CGSize {
        guard background.mode == .none || aspect == .auto,
              let source = sourceSize, source.width > 0, source.height > 0 else {
            return aspect.size(shortSide: shortSide)
        }
        let crop = screen.crop ?? CGRect(x: 0, y: 0, width: 1, height: 1)
        let w = source.width * crop.width, h = source.height * crop.height
        func even(_ v: CGFloat) -> CGFloat { max((v / 2).rounded() * 2, 2) }
        var ratio = w / max(h, 1)
        if background.mode != .none {
            // Pick the frame whose margin around the recording is the same on all four sides.
            let pad = CGFloat(min(max(screen.padding, 0), 0.45))
            ratio = ratio >= 1 ? ratio * (1 - 2 * pad) + 2 * pad
                               : 1 / ((1 / ratio) * (1 - 2 * pad) + 2 * pad)
        }
        return ratio >= 1 ? CGSize(width: even(shortSide * ratio), height: even(shortSide))
                          : CGSize(width: even(shortSide), height: even(shortSide / ratio))
    }

    /// Short side of the recording as shown (after cropping), in pixels.
    var sourceShortSide: CGFloat {
        guard let source = sourceSize else { return 1080 }
        let crop = screen.crop ?? CGRect(x: 0, y: 0, width: 1, height: 1)
        return min(source.width * crop.width, source.height * crop.height)
    }

    /// Kept pieces of the recording. Absent in projects that only had a start/end trim.
    var clips: [Clip]?
    var timeline: [Clip] {
        get {
            if let clips, !clips.isEmpty { return clips }
            return [Clip(start: max(trimStart, 0), end: trimEnd > trimStart ? trimEnd : duration)]
        }
        set { clips = newValue }
    }
    var timeMap: TimeMap { TimeMap(clips: timeline) }
}

/// A project plus the folder it lives in.
struct ProjectRef: Identifiable, Equatable {
    var project: Project
    var folder: URL
    var id: UUID { project.id }
    func url(_ file: String) -> URL {
        file.hasPrefix("/") ? URL(fileURLWithPath: file) : folder.appendingPathComponent(file)
    }
}

enum ProjectStore {
    static var root: URL {
        let movies = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Movies")
        let dir = movies.appendingPathComponent("Framecast", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func newFolder() throws -> (URL, String) {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let name = "Recording " + f.string(from: Date())
        let dir = root.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return (dir, name)
    }

    static func save(_ ref: ProjectRef) {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        guard let data = try? enc.encode(ref.project) else { return }
        try? data.write(to: ref.folder.appendingPathComponent("project.json"), options: .atomic)
    }

    static func load(folder: URL) -> ProjectRef? {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: folder.appendingPathComponent("project.json")),
              let project = try? dec.decode(Project.self, from: data) else { return nil }
        return ProjectRef(project: project, folder: folder)
    }

    static func all() -> [ProjectRef] {
        let dirs = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        return dirs.compactMap { load(folder: $0) }.sorted { $0.project.createdAt > $1.project.createdAt }
    }

    /// Renames the project's folder to match its name (when that name is free), so the
    /// recordings folder in Finder is readable. Returns the folder to use from now on.
    @discardableResult
    static func renameFolder(_ ref: ProjectRef) -> URL {
        let illegal = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let clean = ref.project.name.components(separatedBy: illegal).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, clean != ref.folder.lastPathComponent else { return ref.folder }
        let target = ref.folder.deletingLastPathComponent().appendingPathComponent(clean, isDirectory: true)
        guard !FileManager.default.fileExists(atPath: target.path) else { return ref.folder }
        do { try FileManager.default.moveItem(at: ref.folder, to: target); return target }
        catch { return ref.folder }
    }

    static func delete(_ ref: ProjectRef) {
        try? FileManager.default.trashItem(at: ref.folder, resultingItemURL: nil)
    }
}

// MARK: - Layout shared by the renderer and the editor

enum Layout {
    /// Where the screen recording sits on the canvas (top-left origin).
    static func screenRect(canvas: CGSize, source: CGSize, style: ScreenStyle) -> CGRect {
        guard source.width > 0, source.height > 0 else { return CGRect(origin: .zero, size: canvas) }
        let pad = CGFloat(style.padding) * min(canvas.width, canvas.height)
        let avail = CGSize(width: max(canvas.width - 2 * pad, 10), height: max(canvas.height - 2 * pad, 10))
        let scale = min(avail.width / source.width, avail.height / source.height)
        let size = CGSize(width: source.width * scale, height: source.height * scale)
        return CGRect(x: (canvas.width - size.width) / 2, y: (canvas.height - size.height) / 2,
                      width: size.width, height: size.height)
    }

    /// Where the camera sits on the canvas (top-left origin).
    static func cameraRect(canvas: CGSize, style: CameraStyle) -> CGRect {
        let aspect: CGFloat = style.shape == .rectangle ? 16.0 / 9.0 : 1
        // Sized against the short side so it looks the same on wide and vertical canvases.
        var h = CGFloat(style.size) * min(canvas.width, canvas.height)
        h = min(h, canvas.width * 0.92 / aspect, canvas.height * 0.92)
        let w = h * aspect
        let margin = 0.035 * min(canvas.width, canvas.height)
        if let c = style.customCenter {
            let x = min(max(c.x * canvas.width - w / 2, 0), canvas.width - w)
            let y = min(max(c.y * canvas.height - h / 2, 0), canvas.height - h)
            return CGRect(x: x, y: y, width: w, height: h)
        }
        let xs = [margin, (canvas.width - w) / 2, canvas.width - w - margin]
        let ys = [margin, (canvas.height - h) / 2, canvas.height - h - margin]
        return CGRect(x: xs[min(max(style.anchor.col, 0), 2)], y: ys[min(max(style.anchor.row, 0), 2)],
                      width: w, height: h)
    }

    static func cameraRadius(rect: CGRect, style: CameraStyle) -> CGFloat {
        let half = min(rect.width, rect.height) / 2
        return style.shape == .circle ? half : half * CGFloat(min(max(style.cornerRadius, 0), 1))
    }
}
