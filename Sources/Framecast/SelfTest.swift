import AVFoundation
import AppKit

/// Builds a fake recording (screen + camera + mic), then runs it through the real
/// composition, renderer and exporter. Lets the pipeline be checked from the command line.
enum SelfTest {
    static func run(in folder: URL) async -> Bool {
        do {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let seconds = 3.0
            try await writeVideo(folder.appendingPathComponent("screen.mov"), size: CGSize(width: 2560, height: 1600),
                                 seconds: seconds, fps: 30, draw: drawScreen)
            try await writeVideo(folder.appendingPathComponent("camera.mov"), size: CGSize(width: 1280, height: 720),
                                 seconds: seconds, fps: 30, draw: drawCamera)
            try writeTone(folder.appendingPathComponent("mic.m4a"), seconds: seconds)

            var project = Project(name: "Self test")
            project.duration = seconds
            project.screenColor = "sRGB"
            project.trimStart = 0.5
            project.trimEnd = 2.5
            project.cameraFile = "camera.mov"
            project.micFile = "mic.m4a"
            project.cameraOffset = 0.1
            project.captions = [
                CaptionSegment(start: 0, end: 1.5, text: "Captions are drawn right on the video"),
                CaptionSegment(start: 1.5, end: 3, text: "and exported with it."),
            ]

            ProjectStore.save(ProjectRef(project: project, folder: folder))

            let variants: [(String, ExportResolution, (inout Project) -> Void)] = [
                ("circle-720p", .p720, { _ in }),
                ("rounded-1080p", .p1080, { p in
                    p.camera.shape = .square; p.camera.cornerRadius = 0.35; p.camera.anchor = CameraAnchor(col: 0, row: 0)
                    p.background.presetID = "dawn"
                }),
                ("rectangle-4k", .p2160, { p in
                    p.camera.shape = .rectangle; p.camera.cornerRadius = 0.2; p.camera.anchor = CameraAnchor(col: 2, row: 0)
                    p.background.presetID = "ocean"; p.screen.padding = 0.1
                }),
                ("zoom-1080p", .p1080, { p in
                    p.clicks = [ClickEvent(time: 0.6, x: 0.2, y: 0.5), ClickEvent(time: 1.0, x: 0.3, y: 0.5)]
                    p.zoomStyle.scale = 2
                }),
                ("edited-1080p", .p1080, { p in
                    // Two kept pieces (1.8s total), a crop, a hand-placed zoom and a styled caption.
                    p.clips = [Clip(start: 0.2, end: 1.0), Clip(start: 1.8, end: 2.8)]
                    p.screen.crop = CGRect(x: 0, y: 0, width: 0.6, height: 0.7)
                    p.manualZooms = [ZoomRegion(start: 1.2, end: 2.8, x: 0.1, y: 0.1, scale: 2)]
                    p.captionStyle.fontPath = "/System/Library/Fonts/Supplemental/Georgia Bold.ttf"
                    p.captionStyle.textColor = RGBA(hex: 0xffe066)
                    p.captionStyle.boxColor = RGBA(r: 0.1, g: 0.1, b: 0.35, a: 0.9)
                    p.background.presetID = "moss"
                }),
                ("nobackground-original", .original, { p in
                    // Edge to edge at the recording's own size, camera moved top-left for this stretch.
                    p.background.mode = .none
                    p.cameraSections = [CameraSection(start: 0, end: 3, mode: .position, anchor: CameraAnchor(col: 0, row: 0))]
                }),
                ("camera-fullscreen", .p720, { p in
                    p.cameraSections = [CameraSection(start: 1.0, end: 3, mode: .fullscreen)]
                }),
                ("camera-hidden", .p720, { p in
                    p.cameraSections = [CameraSection(start: 0.5, end: 3, mode: .hidden)]
                }),
                ("animation-slide", .p720, { p in
                    // Frame grabbed at 1.0s: 0.15s into the second clip's entry.
                    p.aspect = .wide
                    p.clips = [Clip(start: 0.0, end: 0.85, exit: .fade), Clip(start: 1.2, end: 2.6, entry: .slideLeft)]
                }),
                ("animation-zoom", .p720, { p in
                    p.aspect = .wide
                    p.clips = [Clip(start: 0.0, end: 0.85), Clip(start: 1.2, end: 2.6, entry: .zoomIn)]
                }),
                ("overlays-audio", .p720, { p in
                    // Text + picture on screen, and a music clip that fades in over 1s and out over 0.5s.
                    p.micFile = nil
                    p.overlays = [
                        Overlay(kind: .text, start: 0, end: 2, x: 0.5, y: 0.18, size: 1.1, shadow: 0.8, text: "Hello from Framecast"),
                        Overlay(kind: .image, start: 0, end: 2, x: 0.2, y: 0.6, size: 0.16, shadow: 0.9,
                                file: folder.deletingLastPathComponent().appendingPathComponent("AppIcon.iconset/icon_256x256.png").path,
                                cornerRadius: 0.2),
                    ]
                    p.audioClips = [AudioClip(file: "mic.m4a", name: "tone", start: 0.2, duration: 1.8, fileDuration: 3,
                                              volume: 1, fadeIn: 1.0, fadeOut: 0.5)]
                }),
                ("speed-keys", .p720, { p in
                    // First second at 2× (0.5s), the rest normal: 0.5 + 1.5 = 2.0s. A shortcut shows at the grab point.
                    p.clips = [Clip(start: 0.0, end: 1.0, speed: 2), Clip(start: 1.0, end: 2.5)]
                    p.keystrokes = [KeyStroke(time: 1.3, label: "⌘ ⇧ P")]
                }),
                ("blur-highlight", .p720, { p in
                    // Blur over the window buttons, a marker on one row, a spotlight on another.
                    p.overlays = [
                        Overlay(kind: .blur, start: 0, end: 2, x: 0.05, y: 0.03, fade: 0, w: 0.1, h: 0.06, strength: 0.6),
                        Overlay(kind: .highlight, start: 0, end: 2, x: 0.3, y: 0.3, fade: 0, color: RGBA(r: 1, g: 0.86, b: 0.2), w: 0.5, h: 0.08, strength: 0.5),
                        Overlay(kind: .highlight, start: 0, end: 2, x: 0.6, y: 0.7, fade: 0, w: 0.4, h: 0.2, strength: 0.6, spotlight: true),
                    ]
                }),
                ("vertical-1080p", .p1080, { p in
                    p.aspect = .vertical; p.background.presetID = "orchid"; p.camera.anchor = CameraAnchor(col: 1, row: 2)
                    p.camera.size = 0.2
                }),
            ]
            for (name, resolution, tweak) in variants {
                var p = project
                tweak(&p)
                let ref = ProjectRef(project: p, folder: folder)
                let out = folder.appendingPathComponent("\(name).mp4")
                let started = Date()
                try await Exporter().export(ref: ref, to: out, resolution: resolution, fps: 30) { _ in }
                let asset = AVURLAsset(url: out)
                let duration = try await asset.load(.duration).seconds
                let video = try await asset.loadTracks(withMediaType: .video).first
                let size = try await video?.load(.naturalSize) ?? .zero
                let audio = try await asset.loadTracks(withMediaType: .audio).count
                let generator = AVAssetImageGenerator(asset: asset)
                generator.requestedTimeToleranceBefore = .zero
                generator.requestedTimeToleranceAfter = .zero
                let frame = try await generator.image(at: CMTime(seconds: 1, preferredTimescale: 600)).image
                let png = NSBitmapImageRep(cgImage: frame).representation(using: .png, properties: [:])
                try png?.write(to: folder.appendingPathComponent("\(name).png"))
                print(String(format: "%@: %.0fx%.0f, %.2fs, %d audio track(s), exported in %.1fs",
                             name, size.width, size.height, duration, audio, Date().timeIntervalSince(started)))
            }
            return true
        } catch {
            print("SELFTEST FAILED: \(error)")
            return false
        }
    }

    private static func drawScreen(_ ctx: CGContext, _ size: CGSize, _ t: Double) {
        ctx.setFillColor(CGColor(gray: 0.97, alpha: 1))
        ctx.fill(CGRect(origin: .zero, size: size))
        ctx.setFillColor(CGColor(gray: 0.9, alpha: 1))
        ctx.fill(CGRect(x: 0, y: size.height - 90, width: size.width, height: 90))
        for (i, c) in [CGColor(red: 1, green: 0.37, blue: 0.34, alpha: 1), CGColor(red: 1, green: 0.74, blue: 0.18, alpha: 1),
                       CGColor(red: 0.16, green: 0.79, blue: 0.25, alpha: 1)].enumerated() {
            ctx.setFillColor(c)
            ctx.fillEllipse(in: CGRect(x: 36 + CGFloat(i) * 44, y: size.height - 60, width: 28, height: 28))
        }
        ctx.setFillColor(CGColor(gray: 0.82, alpha: 1))
        for row in 0..<9 {
            let w = size.width * (0.35 + 0.5 * CGFloat((row * 37) % 10) / 10)
            ctx.fill(CGRect(x: 120, y: size.height - 260 - CGFloat(row) * 120, width: w, height: 44))
        }
        ctx.setFillColor(CGColor(red: 0.2, green: 0.45, blue: 0.95, alpha: 1))
        ctx.fillEllipse(in: CGRect(x: 200 + CGFloat(t) * 600, y: size.height / 2 - 60, width: 120, height: 120))
    }

    private static func drawCamera(_ ctx: CGContext, _ size: CGSize, _ t: Double) {
        ctx.setFillColor(CGColor(red: 0.35, green: 0.42, blue: 0.5, alpha: 1))
        ctx.fill(CGRect(origin: .zero, size: size))
        ctx.setFillColor(CGColor(red: 0.2, green: 0.24, blue: 0.3, alpha: 1))
        ctx.fillEllipse(in: CGRect(x: size.width / 2 - 330, y: -420, width: 660, height: 660))
        ctx.setFillColor(CGColor(red: 0.93, green: 0.76, blue: 0.62, alpha: 1))
        ctx.fillEllipse(in: CGRect(x: size.width / 2 - 150 + CGFloat(sin(t * 3)) * 20, y: 230, width: 300, height: 360))
        // A marker on the left so mirroring is visible.
        ctx.setFillColor(CGColor(red: 1, green: 0.3, blue: 0.3, alpha: 1))
        ctx.fill(CGRect(x: 40, y: size.height - 120, width: 80, height: 80))
    }

    static func writeVideo(_ url: URL, size: CGSize, seconds: Double, fps: Int32,
                                   draw: (CGContext, CGSize, Double) -> Void) async throws {
        try? FileManager.default.removeItem(at: url)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height),
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(size.width),
            kCVPixelBufferHeightKey as String: Int(size.height),
        ])
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? ExportError.failed }
        writer.startSession(atSourceTime: .zero)
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        for frame in 0..<Int(seconds * Double(fps)) {
            while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 2_000_000) }
            guard let pool = adaptor.pixelBufferPool else { throw ExportError.failed }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
            guard let buffer else { throw ExportError.failed }
            CVPixelBufferLockBaseAddress(buffer, [])
            if let ctx = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: Int(size.width), height: Int(size.height),
                                   bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: cs,
                                   bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) {
                draw(ctx, size, Double(frame) / Double(fps))
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: fps))
        }
        input.markAsFinished()
        writer.endSession(atSourceTime: CMTime(seconds: seconds, preferredTimescale: 600))
        await writer.finishWriting()
        if writer.status != .completed { throw writer.error ?? ExportError.failed }
    }

    private static func writeTone(_ url: URL, seconds: Double) throws {
        try? FileManager.default.removeItem(at: url)
        let rate = 48_000.0
        let file = try AVAudioFile(forWriting: url, settings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: rate, AVNumberOfChannelsKey: 1,
        ])
        let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)!
        let frames = AVAudioFrameCount(rate * seconds)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        let samples = buffer.floatChannelData![0]
        for i in 0..<Int(frames) { samples[i] = Float(sin(Double(i) / rate * 2 * .pi * 330)) * 0.2 }
        try file.write(from: buffer)
    }
}
