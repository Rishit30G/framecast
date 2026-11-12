import AppKit
import AVFoundation

/// Command-line entry points that let an assistant (or a script) inspect, edit and export a
/// recording without the editor window:
///   Framecast --info <folder>                 facts about the recording, as JSON
///   Framecast --apply <folder> <edits.json>   apply a list of edits
///   Framecast --frame <folder> <seconds> <png> one frame of the edited video
///   Framecast --export <folder> [out.mp4] [--res 4K|1080p|720p|Original] [--fps 30|60]
enum ClaudeTools {
    static func handle(_ args: [String]) -> Bool {
        func value(after flag: String, _ offset: Int = 1) -> String? {
            guard let i = args.firstIndex(of: flag), args.count > i + offset else { return nil }
            let v = args[i + offset]
            return v.hasPrefix("--") ? nil : v
        }
        func run(_ work: @escaping () async throws -> Void) {
            Task.detached {
                do { try await work(); exit(0) } catch {
                    FileHandle.standardError.write("ERROR: \(error.localizedDescription)\n".data(using: .utf8)!)
                    exit(1)
                }
            }
            dispatchMain()
        }
        func load(_ path: String) throws -> ProjectRef {
            guard let ref = ProjectStore.load(folder: URL(fileURLWithPath: path)) else {
                throw Problem("No Framecast recording found at \(path) (it needs a readable project.json).")
            }
            return ref
        }
        if let folder = value(after: "--info") {
            run { print(try await info(try load(folder))) }
        }
        if let folder = value(after: "--apply"), let edits = value(after: "--apply", 2) {
            run { print(try await apply(try load(folder), editsFile: URL(fileURLWithPath: edits))) }
        }
        if let folder = value(after: "--frame"), let t = value(after: "--frame", 2).flatMap(Double.init), let out = value(after: "--frame", 3) {
            run { try await frame(try load(folder), at: t, to: URL(fileURLWithPath: out)); print("wrote \(out)") }
        }
        if let folder = value(after: "--export") {
            run {
                let ref = try load(folder)
                let out = value(after: "--export", 2).map { URL(fileURLWithPath: $0) }
                    ?? ProjectStore.root.deletingLastPathComponent().appendingPathComponent(ref.project.name + ".mp4")
                let resolution = value(after: "--res").flatMap { r in ExportResolution.allCases.first { $0.rawValue.lowercased() == r.lowercased() } } ?? .p1080
                let fps = Int32(value(after: "--fps") ?? "") ?? 60
                try await Exporter().export(ref: ref, to: out, resolution: resolution, fps: fps == 30 ? 30 : 60) { _ in }
                print("exported \(out.path)")
            }
        }
        return false
    }

    struct Problem: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }

    // MARK: Facts

    private static func round2(_ v: Double) -> Double { (v * 100).rounded() / 100 }

    /// Quiet stretches of the recording's voice track, in source seconds.
    static func silences(_ ref: ProjectRef, minimum: Double) async -> [(start: Double, end: Double)] {
        let p = ref.project
        let url: URL, offset: Double
        if let mic = p.micFile { url = ref.url(mic); offset = p.micOffset } else { url = ref.url(p.screenFile); offset = 0 }
        let length = (try? await AVURLAsset(url: url).load(.duration).seconds) ?? 0
        guard length > 0 else { return [] }
        let peaks = await EditorModel.peaks(of: url, buckets: max(Int(length * 50), 50))
        guard !peaks.isEmpty else { return [] }
        let step = length / Double(peaks.count)
        var out: [(Double, Double)] = []
        var run: Int?
        for i in 0...peaks.count {
            let quiet = i < peaks.count && peaks[i] < 0.07
            if quiet, run == nil { run = i }
            if !quiet, let s = run {
                let a = max(offset + Double(s) * step, 0), b = min(offset + Double(i) * step, p.duration)
                if b - a >= minimum { out.append((a, b)) }
                run = nil
            }
        }
        return out
    }

    /// Stretches (source seconds) where nothing on the recorded screen changes, found by
    /// comparing one small frame per second. Cached, since the recording never changes.
    static func stillStretches(_ ref: ProjectRef, minimum: Double = 4) async -> [(start: Double, end: Double)] {
        let cache = ref.folder.appendingPathComponent("activity.json")
        var moving: [Bool] = (try? Data(contentsOf: cache)).flatMap { try? JSONDecoder().decode([Bool].self, from: $0) } ?? []
        if moving.isEmpty {
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: ref.url(ref.project.screenFile)))
            generator.maximumSize = CGSize(width: 240, height: 240)
            generator.requestedTimeToleranceBefore = CMTime(seconds: 0.4, preferredTimescale: 600)
            generator.requestedTimeToleranceAfter = CMTime(seconds: 0.4, preferredTimescale: 600)
            let w = 96, h = 60
            var last: [UInt8]?
            var t = 0.0
            while t < ref.project.duration {
                var now = [UInt8](repeating: 0, count: w * h)
                if let image = try? await generator.image(at: CMTime(seconds: t, preferredTimescale: 600)).image,
                   let ctx = CGContext(data: &now, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                                       space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) {
                    ctx.interpolationQuality = .medium
                    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
                }
                if let last {
                    var changed = 0
                    for i in 0..<(w * h) where abs(Int(now[i]) - Int(last[i])) > 10 { changed += 1 }
                    moving.append(Double(changed) / Double(w * h) > 0.003)
                } else {
                    moving.append(false)
                }
                last = now
                t += 1
            }
            if let data = try? JSONEncoder().encode(moving) { try? data.write(to: cache, options: .atomic) }
        }
        var out: [(Double, Double)] = []
        var run: Int?
        for i in 0...moving.count {
            let still = i < moving.count && !moving[i]
            if still, run == nil { run = i }
            if !still, let s = run {
                // Second i compares frames i-1 and i, so the still stretch began one second earlier.
                let a = Double(max(s - 1, 0)), b = min(Double(i - 1), ref.project.duration)
                if b - a >= minimum { out.append((a, b)) }
                run = nil
            }
        }
        return out
    }

    private static func transcript(_ ref: ProjectRef) async -> (segments: [CaptionSegment], note: String?) {
        if !ref.project.captions.isEmpty { return (ref.project.captions, nil) }
        let cache = ref.folder.appendingPathComponent("transcript.json")
        if let data = try? Data(contentsOf: cache), let saved = try? JSONDecoder().decode([CaptionSegment].self, from: data) {
            return (saved, nil)
        }
        do {
            let made = try await CaptionGenerator.generate(for: ref)
            if let data = try? JSONEncoder().encode(made) { try? data.write(to: cache, options: .atomic) }
            return (made, nil)
        } catch {
            return ([], "No transcript: \(error.localizedDescription)")
        }
    }

    static func info(_ ref: ProjectRef) async throws -> String {
        let p = ref.project
        let words = await transcript(ref)
        let quiet = await silences(ref, minimum: 0.5)
        let still = await stillStretches(ref)
        var size = p.sourceSize ?? .zero
        if size == .zero, let track = try? await AVURLAsset(url: ref.url(p.screenFile)).loadTracks(withMediaType: .video).first {
            size = (try? await track.load(.naturalSize)) ?? .zero
        }
        var out: [String: Any] = [
            "name": p.name,
            "folder": ref.folder.path,
            "recordedSeconds": round2(p.duration),
            "editedSeconds": round2(p.timeMap.duration),
            "screenPixels": [Int(size.width), Int(size.height)],
            "hasCamera": p.cameraFile != nil,
            "hasMicrophone": p.micFile != nil,
            "keptClips": p.timeline.map { c -> [String: Any] in
                var d: [String: Any] = ["from": round2(c.start), "to": round2(c.end), "speed": c.rate]
                if let e = c.entry { d["entry"] = e.rawValue }
                if let e = c.exit { d["exit"] = e.rawValue }
                return d
            },
            "transcript": words.segments.map { ["from": round2($0.start), "to": round2($0.end), "text": $0.text] },
            "silences": quiet.map { ["from": round2($0.start), "to": round2($0.end), "seconds": round2($0.end - $0.start)] },
            "stillScreen": still.map { ["from": round2($0.start), "to": round2($0.end), "seconds": round2($0.end - $0.start)] },
            "stillScreenNote": "Stretches of 4s or more where nothing on the recorded screen changes (checked once a second).",
            "clicks": (p.clicks ?? []).map { ["time": round2($0.time), "x": round2($0.x), "y": round2($0.y)] },
            "shortcutsPressed": (p.keystrokes ?? []).map { ["time": round2($0.time), "keys": $0.label] },
            "look": [
                "aspect": p.aspect.rawValue,
                "background": p.background.mode == .preset ? p.background.presetID : p.background.mode.rawValue,
                "padding": p.screen.padding, "corners": p.screen.cornerRadius, "shadow": p.screen.shadow,
                "autoZoom": p.zoomStyle.enabled, "autoZoomScale": p.zoomStyle.scale,
                "captionsShown": p.captionStyle.visible && !p.captions.isEmpty,
                "voiceCleanup": p.audio.voiceCleanup == true,
            ] as [String: Any],
            "placed": [
                "zooms": (p.manualZooms ?? []).count, "cameraSections": (p.cameraSections ?? []).count,
                "overlays": (p.overlays ?? []).map { "\($0.kind.rawValue) at \(round2($0.start))s of the edited video" },
                "audioClips": (p.audioClips ?? []).map { $0.name },
            ] as [String: Any],
            "wallpapers": MacWallpaper.all.map { $0.name },
            "timeNote": "All times are seconds of the raw recording (source time), not of the edited video.",
        ]
        if let note = words.note { out["transcriptNote"] = note }
        let data = try JSONSerialization.data(withJSONObject: out, options: [.prettyPrinted, .sortedKeys])
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    // MARK: Edits

    private static func remove(_ from: Double, _ to: Double, in clips: [Clip]) -> [Clip] {
        var out: [Clip] = []
        for c in clips {
            if to <= c.start || from >= c.end { out.append(c); continue }
            if from - c.start >= 0.05 { var a = c; a.id = UUID(); a.end = from; a.exit = nil; out.append(a) }
            if c.end - to >= 0.05 { var b = c; b.id = UUID(); b.start = to; b.entry = nil; out.append(b) }
        }
        return out
    }

    /// Splits clips at `t` so a later change can apply to one side only.
    private static func split(at t: Double, in clips: [Clip]) -> [Clip] {
        var out: [Clip] = []
        for c in clips {
            if t - c.start > 0.05, c.end - t > 0.05 {
                var a = c, b = c
                a.end = t; a.exit = nil
                b.id = UUID(); b.start = t; b.entry = nil
                out += [a, b]
            } else { out.append(c) }
        }
        return out
    }

    static func apply(_ ref: ProjectRef, editsFile: URL) async throws -> String {
        guard let data = try? Data(contentsOf: editsFile),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let ops = root["edits"] as? [[String: Any]] else {
            throw Problem("The edits file must be JSON of the form {\"edits\": [ {\"do\": ...}, ... ]}.")
        }
        var p = ref.project
        var log: [String] = []
        func num(_ op: [String: Any], _ key: String) -> Double? { (op[key] as? NSNumber)?.doubleValue }
        func span(_ op: [String: Any]) throws -> (Double, Double) {
            guard let a = num(op, "from"), let b = num(op, "to"), b > a else {
                throw Problem("\"\(op["do"] ?? "?")\" needs \"from\" and \"to\" in seconds, with to > from.")
            }
            return (max(a, 0), min(b, p.duration))
        }
        let timelineOps: Set<String> = ["reset", "keep", "cut", "removeSilences", "speed"]
        let ordered = ops.filter { timelineOps.contains($0["do"] as? String ?? "") } + ops.filter { !timelineOps.contains($0["do"] as? String ?? "") }

        for op in ordered {
            let name = op["do"] as? String ?? ""
            switch name {
            case "reset":
                let what = op["what"] as? String ?? "all"
                if what == "all" || what == "cuts" { p.clips = [Clip(start: 0, end: p.duration)] }
                if what == "all" || what == "zooms" { p.manualZooms = [] }
                if what == "all" || what == "overlays" { p.overlays = [] }
                if what == "all" || what == "camera" { p.cameraSections = [] }
                if what == "all" || what == "captions" { p.captions = [] }
                log.append("reset \(what)")
            case "keep":
                guard let ranges = op["ranges"] as? [[NSNumber]], !ranges.isEmpty else { throw Problem("\"keep\" needs \"ranges\": [[from, to], ...].") }
                p.clips = ranges.compactMap { r in
                    guard r.count == 2, r[1].doubleValue - r[0].doubleValue >= 0.05 else { return nil }
                    return Clip(start: max(r[0].doubleValue, 0), end: min(r[1].doubleValue, p.duration))
                }.sorted { $0.start < $1.start }
                log.append("kept \(p.clips?.count ?? 0) range(s)")
            case "cut":
                let (a, b) = try span(op)
                p.clips = remove(a, b, in: p.timeline)
                log.append(String(format: "cut %.2f–%.2f", a, b))
            case "removeSilences":
                let longer = num(op, "longerThan") ?? 0.8, leave = max(num(op, "leave") ?? 0.3, 0)
                var removed = 0.0, count = 0
                for s in await silences(ref, minimum: longer) {
                    let a = s.start + leave / 2, b = s.end - leave / 2
                    guard b - a > 0.1 else { continue }
                    p.clips = remove(a, b, in: p.timeline)
                    removed += b - a; count += 1
                }
                log.append(String(format: "removed %d silence(s), %.1fs in total", count, removed))
            case "speed":
                let (a, b) = try span(op)
                guard let rate = num(op, "rate"), rate >= 0.25, rate <= 8 else { throw Problem("\"speed\" needs \"rate\" between 0.25 and 8.") }
                var clips = split(at: b, in: split(at: a, in: p.timeline))
                for i in clips.indices where clips[i].start >= a - 0.06 && clips[i].end <= b + 0.06 { clips[i].speed = rate == 1 ? nil : rate }
                p.clips = clips
                log.append(String(format: "speed %.2g× for %.2f–%.2f", rate, a, b))
            case "zoom":
                let (a, b) = try span(op)
                p.manualZooms = (p.manualZooms ?? []) + [ZoomRegion(start: a, end: b, x: num(op, "x") ?? 0.5, y: num(op, "y") ?? 0.5,
                                                                    scale: min(max(num(op, "scale") ?? 2, 1.1), 5))]
                log.append(String(format: "zoom %.2f–%.2f", a, b))
            case "autoZoom":
                var z = p.zoomStyle
                z.enabled = op["on"] as? Bool ?? true
                if let s = num(op, "scale") { z.scale = min(max(s, 1), 4) }
                p.zoomStyle = z
                log.append("auto zoom \(z.enabled ? "on" : "off")")
            case "camera":
                let (a, b) = try span(op)
                guard p.cameraFile != nil else { log.append("camera: skipped, this recording has no camera"); continue }
                let mode = CameraSectionMode(rawValue: op["mode"] as? String ?? "") ?? .position
                p.cameraSections = (p.cameraSections ?? []) + [CameraSection(start: a, end: b, mode: mode,
                    anchor: CameraAnchor(col: Int(num(op, "col") ?? 2), row: Int(num(op, "row") ?? 2)))]
                log.append(String(format: "camera %@ %.2f–%.2f", mode.rawValue, a, b))
            case "text", "blur", "highlight", "spotlight":
                let (a, b) = try span(op)
                // Overlays live on the edited timeline, so translate from raw-recording time.
                let map = p.timeMap
                let start = map.output(a), end = map.output(b)
                guard end - start > 0.1 else { log.append("\(name): skipped, that stretch was cut out"); continue }
                var o = Overlay(kind: name == "text" ? .text : name == "blur" ? .blur : .highlight, start: start, end: end)
                o.x = num(op, "x") ?? 0.5
                o.y = num(op, "y") ?? (name == "text" ? 0.2 : 0.5)
                if name == "text" {
                    o.text = op["text"] as? String ?? "Text"
                    o.size = num(op, "size") ?? 1
                    if op["box"] as? Bool == true { o.boxColor = RGBA(r: 0, g: 0, b: 0, a: 0.6) }
                } else {
                    o.shadow = 0; o.fade = 0.15
                    o.w = num(op, "w") ?? 0.3; o.h = num(op, "h") ?? 0.1
                    o.strength = num(op, "strength") ?? 0.6
                    if name != "blur" { o.color = RGBA(r: 1, g: 0.86, b: 0.2); o.spotlight = name == "spotlight" }
                }
                p.overlays = (p.overlays ?? []) + [o]
                log.append(String(format: "%@ %.2f–%.2f", name, a, b))
            case "captions":
                if op["on"] as? Bool == false { p.captionStyle.visible = false; log.append("captions hidden"); continue }
                if p.captions.isEmpty {
                    let made = await transcript(ref)
                    if made.segments.isEmpty { log.append("captions: \(made.note ?? "no speech found")"); continue }
                    p.captions = made.segments
                }
                p.captionStyle.visible = true
                if let s = num(op, "size") { p.captionStyle.scale = min(max(s, 0.5), 2.5) }
                log.append("captions on (\(p.captions.count) lines)")
            case "cleanAudio":
                guard let mic = p.micFile else { log.append("cleanAudio: skipped, there is no microphone track"); continue }
                if op["on"] as? Bool == false { p.audio.voiceCleanup = false; log.append("voice clean-up off"); continue }
                let clean = ref.url("mic-clean.m4a")
                if !FileManager.default.fileExists(atPath: clean.path) {
                    do { try VoiceCleaner.clean(input: ref.url(mic), output: clean) } catch {
                        try? FileManager.default.removeItem(at: clean)
                        log.append("cleanAudio: failed (\(error.localizedDescription))"); continue
                    }
                }
                p.audio.voiceCleanup = true
                log.append("voice clean-up on")
            case "animation":
                var clips = p.timeline
                guard !clips.isEmpty else { continue }
                let which = op["clip"] as? String ?? "first"
                func kind(_ key: String) -> ClipAnimation?? {
                    guard let raw = op[key] as? String else { return nil }
                    return .some(ClipAnimation(rawValue: raw))
                }
                let targets = which == "all" ? Array(clips.indices) : which == "last" ? [clips.count - 1]
                    : [min(max(Int(num(op, "index") ?? 0), 0), clips.count - 1)]
                for i in targets {
                    if let e = kind("entry") { clips[i].entry = e }
                    if let e = kind("exit") { clips[i].exit = e }
                }
                p.clips = clips
                log.append("animation set on \(targets.count) clip(s)")
            case "look":
                if let a = op["aspect"] as? String, let v = CanvasAspect(rawValue: a) { p.aspect = v }
                if let b = op["background"] as? String {
                    if b == "none" { p.background.mode = .none }
                    else if BackgroundPreset.all.contains(where: { $0.id == b }) { p.background.mode = .preset; p.background.presetID = b }
                    else if let paper = MacWallpaper.named(b) { p.background.mode = .image; p.background.imagePath = paper.path }
                    else if b.hasPrefix("#"), let hex = UInt32(b.dropFirst(), radix: 16) { p.background.mode = .color; p.background.color = RGBA(hex: hex) }
                    else { log.append("look: unknown background \"\(b)\" ignored") }
                }
                if let v = num(op, "padding") { p.screen.padding = min(max(v, 0), 0.3) }
                if let v = num(op, "corners") { p.screen.cornerRadius = min(max(v, 0), 80) }
                if let v = num(op, "shadow") { p.screen.shadow = min(max(v, 0), 1) }
                if let v = num(op, "outline") { p.screen.border = min(max(v, 0), 1) }
                if let v = num(op, "backgroundBlur") { p.background.blur = min(max(v, 0), 1) }
                if let v = op["cameraVisible"] as? Bool { p.camera.visible = v }
                if let v = num(op, "cameraSize") { p.camera.size = min(max(v, 0.08), 0.6) }
                if let v = op["showShortcuts"] as? Bool { p.showKeystrokes = v }
                log.append("look updated")
            default:
                throw Problem("Unknown edit \"\(name)\". Nothing was saved.")
            }
        }
        guard !p.timeline.isEmpty else { throw Problem("Those edits would cut away the whole video. Nothing was saved.") }
        // One backup of how the recording was before an assistant first touched it.
        let backup = ref.folder.appendingPathComponent("project.before-claude.json")
        if !FileManager.default.fileExists(atPath: backup.path) {
            try? FileManager.default.copyItem(at: ref.folder.appendingPathComponent("project.json"), to: backup)
        }
        ProjectStore.save(ProjectRef(project: p, folder: ref.folder))
        log.append(String(format: "saved — the edited video is now %.1fs (recording: %.1fs)", p.timeMap.duration, p.duration))
        return log.joined(separator: "\n")
    }

    // MARK: Looking at the result

    /// `seconds` is raw-recording time, like everything else here.
    static func frame(_ ref: ProjectRef, at seconds: Double, to url: URL) async throws {
        var project = ref.project
        let built = try await CompositionBuilder.build(ref)
        if project.sourceSize == nil { project.sourceSize = built.sourceSize }
        let generator = AVAssetImageGenerator(asset: built.composition)
        generator.videoComposition = CompositionBuilder.videoComposition(built, project: project, folder: ref.folder,
                                                                         renderSize: project.canvasSize(shortSide: 720), fps: 30)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let t = min(max(project.timeMap.output(seconds), 0), max(built.duration.seconds - 0.05, 0))
        let image = try await generator.image(at: CMTime(seconds: t, preferredTimescale: 600)).image
        guard let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { throw Problem("Couldn't make the picture.") }
        try png.write(to: url)
    }

    // MARK: The skill

    static var skillFolder: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/skills/framecast-editor", isDirectory: true)
    }
    static var styleFile: URL { skillFolder.appendingPathComponent("STYLE.md") }

    /// Copies the skill that ships inside the app to where Claude looks for skills. The
    /// instructions are refreshed each time; the person's own style file is never overwritten.
    @discardableResult
    static func installSkill() -> Bool {
        guard let source = Bundle.main.resourceURL?.appendingPathComponent("skill"),
              let text = try? String(contentsOf: source.appendingPathComponent("SKILL.md"), encoding: .utf8) else { return false }
        let fm = FileManager.default
        try? fm.createDirectory(at: skillFolder, withIntermediateDirectories: true)
        let binary = Bundle.main.executablePath ?? "/Applications/Framecast.app/Contents/MacOS/Framecast"
        try? text.replacingOccurrences(of: "{{FRAMECAST}}", with: binary)
            .write(to: skillFolder.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        if !fm.fileExists(atPath: styleFile.path) {
            try? fm.copyItem(at: source.appendingPathComponent("STYLE.md"), to: styleFile)
        }
        return fm.fileExists(atPath: styleFile.path)
    }
}
