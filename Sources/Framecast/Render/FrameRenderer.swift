import AVFoundation
import CoreImage
import CoreText

/// Everything the renderer needs to draw one frame. A snapshot of the project's look.
struct RenderState {
    var background: BackgroundStyle
    var screen: ScreenStyle
    var camera: CameraStyle
    var captions: [CaptionSegment]
    var captionStyle: CaptionStyle
    var zoom: ZoomPlan
    var timeMap: TimeMap
    var cameraSections: [CameraSection]
    var animationDuration: Double
    var overlays: [Overlay]
    var keystrokes: [KeyStroke]
    var folder: URL?
    var screenTrackID: CMPersistentTrackID
    var cameraTrackID: CMPersistentTrackID?
    /// How to read the screen recording's pixels.
    var screenSpace: CGColorSpace?

    init(project: Project, folder: URL? = nil, screenTrackID: CMPersistentTrackID, cameraTrackID: CMPersistentTrackID?) {
        overlays = project.overlays ?? []
        if !ColorMode.legacy {
            screenSpace = CGColorSpace(name: project.screenColor == "sRGB" ? CGColorSpace.sRGB : CGColorSpace.displayP3)
        }
        keystrokes = (project.showKeystrokes ?? true) ? (project.keystrokes ?? []).sorted { $0.time < $1.time } : []
        self.folder = folder
        background = project.background
        screen = project.screen
        camera = project.camera
        captions = project.captions
        captionStyle = project.captionStyle
        zoom = ZoomPlan(clicks: project.clicks ?? [], style: project.zoomStyle, manual: project.manualZooms ?? [])
        timeMap = project.timeMap
        cameraSections = project.cameraSections ?? []
        animationDuration = project.animationDuration ?? 0.5
        if background.mode == .none {
            // Edge to edge: nothing around the recording.
            screen.padding = 0
            screen.cornerRadius = 0
            screen.shadow = 0
            screen.border = 0
        }
        self.screenTrackID = screenTrackID
        self.cameraTrackID = cameraTrackID
    }
}

/// Draws background + screen recording + camera + captions with Core Image.
/// Used for both the live preview and the export, so they always match.
final class FrameRenderer {
    static let shared = FrameRenderer()

    private let context: CIContext
    private let outputSpace = CGColorSpace(name: ColorMode.legacy ? CGColorSpace.itur_709 : CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    private let lock = NSLock()
    private var baseCache: [String: CIImage] = [:]
    private var captionCache: [String: CIImage] = [:]

    private init() {
        let srgb = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        context = CIContext(options: [.workingColorSpace: srgb, .cacheIntermediates: false])
    }

    func render(screen: CVPixelBuffer?, camera: CVPixelBuffer?, time outputTime: Double, state: RenderState, to output: CVPixelBuffer) {
        // Captions and zooms are stored against the raw recording, not the cut-down timeline.
        let time = state.timeMap.source(outputTime)
        let canvas = CGSize(width: CVPixelBufferGetWidth(output), height: CVPixelBufferGetHeight(output))
        let bounds = CGRect(origin: .zero, size: canvas)
        let unit = min(canvas.width, canvas.height) / 1080
        var screenImage = screen.map { buffer in
            state.screenSpace.map { CIImage(cvPixelBuffer: buffer, options: [.colorSpace: $0]) } ?? CIImage(cvPixelBuffer: buffer)
        }
        let fullExtent = screenImage?.extent ?? bounds
        if let image = screenImage, let c = state.screen.crop {
            let r = CGRect(x: fullExtent.minX + c.minX * fullExtent.width,
                           y: fullExtent.minY + (1 - c.maxY) * fullExtent.height,
                           width: c.width * fullExtent.width, height: c.height * fullExtent.height)
                .integral.intersection(fullExtent)
            if r.width >= 16, r.height >= 16 { screenImage = image.cropped(to: r) }
        }
        let sourceSize = screenImage?.extent.size ?? canvas
        // Blur and highlight boxes are drawn into the recording itself, before any zoom.
        if let image = screenImage { screenImage = regions(on: image, at: outputTime, state: state) }

        let screenRect = flip(Layout.screenRect(canvas: canvas, source: sourceSize, style: state.screen), canvas)
        let screenRadius = min(CGFloat(state.screen.cornerRadius) * unit, min(screenRect.width, screenRect.height) / 2)
        // While a clip is animating in or out, the screen and camera are drawn on their own
        // transparent layer so they can move as one over the still background.
        // A fade takes the whole picture (background included) to black; the other
        // animations move the recording over a still background.
        let playing = state.timeMap.animation(atOutput: outputTime, duration: state.animationDuration)
        let animation = playing?.kind == .fade ? nil : playing
        var image: CIImage
        if animation == nil {
            image = base(state: state, canvas: canvas, screenRect: screenRect, radius: screenRadius, unit: unit, withShadow: true)
        } else {
            image = CIImage(color: .clear).cropped(to: bounds)
            if let s = screenShadow(state: state, rect: screenRect, radius: screenRadius, unit: unit) {
                image = s.composited(over: image)
            }
        }

        if var source = screenImage {
            if let crop = state.zoom.crop(of: source.extent, full: fullExtent, at: time) { source = source.cropped(to: crop) }
            let placed = place(source, in: screenRect)
            image = clip(placed, to: screenRect, radius: screenRadius, over: image)
        }
        // A hairline of translucent white just inside the recording's edge.
        if let strength = state.screen.border, strength > 0.01 {
            let a = CGFloat(0.12 + 0.55 * min(strength, 1))
            let width = max((1 + 1.5 * CGFloat(min(strength, 1))) * unit, 1)
            let outer = roundedRect(screenRect, radius: screenRadius, color: CIColor(red: a, green: a, blue: a, alpha: a))
            let inner = roundedRect(screenRect.insetBy(dx: width, dy: width), radius: max(screenRadius - width, 0), color: .white)
            image = outer.applyingFilter("CISourceOutCompositing", parameters: [kCIInputBackgroundImageKey: inner])
                .composited(over: image)
        }

        var cameraRect: CGRect?
        if let camera, state.camera.visible {
            let layout = cameraLayout(at: time, state: state, canvas: canvas)
            if layout.alpha > 0.004 {
                let rect = layout.rect
                var cam = CIImage(cvPixelBuffer: camera)
                let e = cam.extent
                let aspect = rect.width / rect.height
                var crop = e
                if e.width / e.height > aspect {
                    let w = e.height * aspect
                    crop = CGRect(x: e.midX - w / 2, y: e.minY, width: w, height: e.height)
                } else {
                    let h = e.width / aspect
                    crop = CGRect(x: e.minX, y: e.midY - h / 2, width: e.width, height: h)
                }
                cam = cam.cropped(to: crop)
                if state.camera.mirrored { cam = cam.transformed(by: CGAffineTransform(scaleX: -1, y: 1)) }
                let strength = CGFloat(state.camera.shadowStrength)
                if strength > 0.01, layout.shadow > 0.01 {
                    image = shadow(rect: rect, radius: layout.radius, opacity: (0.2 + 0.45 * strength) * layout.alpha * layout.shadow,
                                   blur: (8 + 22 * strength) * unit, drop: (3 + 8 * strength) * unit).composited(over: image)
                }
                image = clip(place(cam, in: rect), to: rect, radius: layout.radius, over: image, alpha: layout.alpha)
                if layout.alpha > 0.5 { cameraRect = rect }
            }
        }

        if let animation {
            let background = base(state: state, canvas: canvas, screenRect: screenRect, radius: screenRadius, unit: unit, withShadow: false)
            image = animate(image, animation.kind, presence: CGFloat(animation.presence), canvas: canvas, unit: unit)
                .composited(over: background)
        }

        // Text and pictures the user placed, on top of everything except captions.
        for overlay in state.overlays where !overlay.kind.isRegion && outputTime >= overlay.start && outputTime < overlay.end {
            guard var layer = overlayImage(overlay, canvas: canvas, unit: unit, folder: state.folder) else { continue }
            let e = layer.extent
            layer = layer.transformed(by: CGAffineTransform(
                translationX: (CGFloat(overlay.x) * canvas.width - e.width / 2 - e.minX).rounded(),
                y: (CGFloat(1 - overlay.y) * canvas.height - e.height / 2 - e.minY).rounded()))
            var alpha = CGFloat(min(max(overlay.opacity, 0), 1))
            if overlay.fade > 0.01 {
                let f = min(overlay.fade, (overlay.end - overlay.start) / 2)
                alpha *= CGFloat(min(1, (outputTime - overlay.start) / f, (overlay.end - outputTime) / f))
            }
            guard alpha > 0.004 else { continue }
            let strength = CGFloat(overlay.shadow)
            if strength > 0.01 {
                // A blurred black copy of the layer's own shape, nudged downwards.
                let zero = CIVector(x: 0, y: 0, z: 0, w: 0)
                let dark = layer.applyingFilter("CIColorMatrix", parameters: [
                    "inputRVector": zero, "inputGVector": zero, "inputBVector": zero,
                    "inputAVector": CIVector(x: 0, y: 0, z: 0, w: (0.35 + 0.55 * strength) * alpha),
                ])
                image = dark.applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: (3 + 14 * strength) * unit])
                    .transformed(by: CGAffineTransform(translationX: 0, y: -(2 + 7 * strength) * unit))
                    .composited(over: image)
            }
            if alpha < 0.999 {
                layer = layer.applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: alpha)])
            }
            image = layer.composited(over: image)
        }

        // The most recent keyboard shortcut, shown bottom-left for a moment and then faded.
        if let key = state.keystrokes.last(where: { $0.time <= time }), time - key.time < 1.6 {
            var style = CaptionStyle()
            style.scale = 0.95
            style.boxColor = RGBA(r: 0.08, g: 0.08, b: 0.1, a: 0.82)
            if var badge = captionImage(key.label, canvas: canvas, style: style) {
                let age = time - key.time
                let alpha = CGFloat(min(1, age / 0.08, (1.6 - age) / 0.35))
                let x = canvas.width * 0.035
                var y = canvas.height * 0.06
                if let cam = cameraRect, cam.intersects(CGRect(x: x, y: y, width: badge.extent.width, height: badge.extent.height)) {
                    y = cam.maxY + 16 * unit
                }
                badge = badge.transformed(by: CGAffineTransform(translationX: x.rounded(), y: y.rounded()))
                if alpha < 0.999 {
                    badge = badge.applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: max(alpha, 0))])
                }
                image = badge.composited(over: image)
            }
        }

        if state.captionStyle.visible,
           let segment = state.captions.first(where: { time >= $0.start && time < $0.end }),
           let caption = captionImage(segment.text, canvas: canvas, style: state.captionStyle) {
            let x = (canvas.width - caption.extent.width) / 2
            var y = canvas.height * 0.06
            // Sit above the camera rather than on top of the speaker's face.
            if let cam = cameraRect,
               cam.intersects(CGRect(x: x, y: y, width: caption.extent.width, height: caption.extent.height)),
               cam.maxY + 16 * unit + caption.extent.height < canvas.height * 0.6 {
                y = cam.maxY + 16 * unit
            }
            image = caption.transformed(by: CGAffineTransform(translationX: x.rounded(), y: y.rounded())).composited(over: image)
        }

        if let playing, playing.kind == .fade {
            let v = 1 - pow(1 - CGFloat(min(max(playing.presence, 0), 1)), 2)
            image = image.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: v, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: v, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: v, w: 0),
            ])
        }
        context.render(image.cropped(to: bounds), to: output, bounds: bounds, colorSpace: outputSpace)
    }

    // MARK: Blur and highlight boxes

    private func regions(on source: CIImage, at outputTime: Double, state: RenderState) -> CIImage {
        var image = source
        let e = source.extent
        let unit = min(e.width, e.height) / 1080
        for o in state.overlays where o.kind.isRegion && outputTime >= o.start && outputTime < o.end {
            var alpha = CGFloat(1)
            if o.fade > 0.01 {
                let f = min(o.fade, (o.end - o.start) / 2)
                alpha = CGFloat(min(1, (outputTime - o.start) / f, (o.end - outputTime) / f))
            }
            guard alpha > 0.004 else { continue }
            let w = CGFloat(o.boxWidth) * e.width, h = CGFloat(o.boxHeight) * e.height
            let rect = CGRect(x: e.minX + CGFloat(o.x) * e.width - w / 2,
                              y: e.minY + CGFloat(1 - o.y) * e.height - h / 2, width: w, height: h)
                .integral.intersection(e)
            guard rect.width >= 2, rect.height >= 2 else { continue }
            let corner = min(10 * unit, min(rect.width, rect.height) / 2)
            let amount = CGFloat(o.amount)

            switch o.kind {
            case .blur:
                let radius = (6 + 44 * amount) * unit
                let reach = rect.insetBy(dx: -radius * 3, dy: -radius * 3).intersection(e)
                let blurred = image.cropped(to: reach).clampedToExtent()
                    .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: radius])
                    .cropped(to: rect)
                image = blurred.applyingFilter("CIBlendWithMask", parameters: [
                    kCIInputBackgroundImageKey: image,
                    kCIInputMaskImageKey: roundedRect(rect, radius: corner, color: CIColor(red: alpha, green: alpha, blue: alpha, alpha: alpha)),
                ]).cropped(to: e)
            case .highlight where o.spotlight == true:
                let keep = 1 - (0.25 + 0.6 * amount) * alpha
                let dimmed = image.applyingFilter("CIColorMatrix", parameters: [
                    "inputRVector": CIVector(x: keep, y: 0, z: 0, w: 0),
                    "inputGVector": CIVector(x: 0, y: keep, z: 0, w: 0),
                    "inputBVector": CIVector(x: 0, y: 0, z: keep, w: 0),
                ])
                image = image.applyingFilter("CIBlendWithMask", parameters: [
                    kCIInputBackgroundImageKey: dimmed,
                    kCIInputMaskImageKey: roundedRect(rect, radius: corner, color: .white),
                ]).cropped(to: e)
            case .highlight:
                // Multiplied like a marker pen, so dark text underneath stays crisp.
                let a = (0.25 + 0.7 * amount) * alpha
                // CIColor takes straight (not premultiplied) components.
                let tint = roundedRect(rect, radius: corner, color: CIColor(red: CGFloat(o.color.r), green: CGFloat(o.color.g),
                                                                            blue: CGFloat(o.color.b), alpha: a))
                image = tint.applyingFilter("CIMultiplyBlendMode", parameters: [kCIInputBackgroundImageKey: image]).cropped(to: e)
            default:
                break
            }
        }
        return image
    }

    // MARK: Camera layout over time

    private struct CameraLayout {
        var rect: CGRect
        var radius: CGFloat
        var alpha: CGFloat
        var shadow: CGFloat
    }

    /// Where the camera sits at source time `t`, gliding for a moment after each change.
    private func cameraLayout(at t: Double, state: RenderState, canvas: CGSize) -> CameraLayout {
        func settled(_ time: Double) -> CameraLayout {
            let section = state.cameraSections.first { time >= $0.start && time < $0.end }
            var style = state.camera
            if let section, section.mode == .position {
                style.anchor = section.anchor
                style.customCenter = nil
            }
            let rect = flip(Layout.cameraRect(canvas: canvas, style: style), canvas)
            switch section?.mode {
            case .fullscreen:
                return CameraLayout(rect: CGRect(origin: .zero, size: canvas), radius: 0, alpha: 1, shadow: 0)
            case .hidden:
                return CameraLayout(rect: rect, radius: Layout.cameraRadius(rect: rect, style: style), alpha: 0, shadow: 1)
            default:
                return CameraLayout(rect: rect, radius: Layout.cameraRadius(rect: rect, style: style), alpha: 1, shadow: 1)
            }
        }
        let now = settled(t)
        let glide = 0.4
        var last: Double?
        for section in state.cameraSections {
            for edge in [section.start, section.end] where edge <= t && edge > 0.001 {
                if last == nil || edge > last! { last = edge }
            }
        }
        guard let edge = last, t - edge < glide else { return now }
        let before = settled(edge - 0.001)
        let x = CGFloat((t - edge) / glide)
        let k = x * x * (3 - 2 * x)
        func mix(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * k }
        // Fading in or out happens in place rather than sliding across the frame.
        let from = before.alpha < 0.01 ? CameraLayout(rect: now.rect, radius: now.radius, alpha: 0, shadow: now.shadow) : before
        let to = now.alpha < 0.01 ? CameraLayout(rect: before.rect, radius: before.radius, alpha: 0, shadow: before.shadow) : now
        return CameraLayout(
            rect: CGRect(x: mix(from.rect.minX, to.rect.minX), y: mix(from.rect.minY, to.rect.minY),
                         width: mix(from.rect.width, to.rect.width), height: mix(from.rect.height, to.rect.height)),
            radius: mix(from.radius, to.radius), alpha: mix(from.alpha, to.alpha), shadow: mix(from.shadow, to.shadow))
    }

    // MARK: Pieces

    /// Top-left-origin rect → Core Image's bottom-left origin.
    private func flip(_ r: CGRect, _ canvas: CGSize) -> CGRect {
        CGRect(x: r.minX, y: canvas.height - r.maxY, width: r.width, height: r.height)
    }

    /// Scales an image to fill `rect` exactly.
    private func place(_ image: CIImage, in rect: CGRect) -> CIImage {
        let e = image.extent
        let scale = rect.height / e.height
        var out: CIImage
        if scale < 0.98 {
            out = image.applyingFilter("CILanczosScaleTransform", parameters: [
                kCIInputScaleKey: scale,
                kCIInputAspectRatioKey: (rect.width / e.width) / scale,
            ])
        } else {
            out = image.transformed(by: CGAffineTransform(scaleX: rect.width / e.width, y: scale))
        }
        out = out.transformed(by: CGAffineTransform(translationX: rect.minX - out.extent.minX, y: rect.minY - out.extent.minY))
        return out
    }

    private func roundedRect(_ rect: CGRect, radius: CGFloat, color: CIColor) -> CIImage {
        let r = max(min(radius, min(rect.width, rect.height) / 2), 0)
        return CIFilter(name: "CIRoundedRectangleGenerator", parameters: [
            "inputExtent": CIVector(cgRect: rect),
            "inputRadius": r,
            "inputColor": color,
        ])?.outputImage ?? CIImage(color: color).cropped(to: rect)
    }

    private func clip(_ image: CIImage, to rect: CGRect, radius: CGFloat, over background: CIImage, alpha: CGFloat = 1) -> CIImage {
        if radius < 0.5, alpha > 0.999 { return image.cropped(to: rect).composited(over: background) }
        // The mask's brightness doubles as the layer's opacity.
        let mask = roundedRect(rect, radius: radius, color: CIColor(red: alpha, green: alpha, blue: alpha, alpha: alpha))
        return image.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: background,
            kCIInputMaskImageKey: mask,
        ])
    }

    private func shadow(rect: CGRect, radius: CGFloat, opacity: CGFloat, blur: CGFloat, drop: CGFloat) -> CIImage {
        roundedRect(rect, radius: radius, color: CIColor(red: 0, green: 0, blue: 0, alpha: opacity))
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: blur])
            .transformed(by: CGAffineTransform(translationX: 0, y: -drop))
    }

    /// Background + the screen's drop shadow never change between frames, so render them once.
    private func screenShadow(state: RenderState, rect: CGRect, radius: CGFloat, unit: CGFloat) -> CIImage? {
        let strength = CGFloat(state.screen.shadow)
        guard strength > 0.01 else { return nil }
        return shadow(rect: rect, radius: radius, opacity: 0.25 + 0.4 * strength,
                      blur: (14 + 36 * strength) * unit, drop: (6 + 16 * strength) * unit)
    }

    /// The background (optionally with the screen's drop shadow) never changes between
    /// frames, so each variant is rendered once and reused.
    private func base(state: RenderState, canvas: CGSize, screenRect: CGRect, radius: CGFloat, unit: CGFloat,
                      withShadow: Bool) -> CIImage {
        let b = state.background
        let key = "\(b.mode.rawValue)|\(b.presetID)|\(b.color.r),\(b.color.g),\(b.color.b)|\(b.imagePath ?? "")|\(b.blur ?? 0)|\(canvas)|\(screenRect)|\(radius)|\(state.screen.shadow)|\(withShadow)"
        lock.lock()
        defer { lock.unlock() }
        if let hit = baseCache[key] { return hit }

        let bounds = CGRect(origin: .zero, size: canvas)
        var image: CIImage
        if let cg = BackgroundPainter.image(b, size: canvas) { image = CIImage(cgImage: cg) }
        else { image = CIImage(color: .black).cropped(to: bounds) }
        if let blur = b.blur, blur > 0.01, b.mode == .image || b.mode == .preset {
            image = image.clampedToExtent()
                .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 70 * CGFloat(min(blur, 1)) * unit])
                .cropped(to: bounds)
        }
        if withShadow, let s = screenShadow(state: state, rect: screenRect, radius: radius, unit: unit) {
            image = s.composited(over: image)
        }
        if let flat = context.createCGImage(image.cropped(to: bounds), from: bounds) { image = CIImage(cgImage: flat) }
        if baseCache.count >= 4 { baseCache.removeAll() }
        baseCache[key] = image
        return image
    }

    /// Moves, scales, fades or blurs the foreground layer. `presence` runs 0 (gone) → 1 (in place).
    private func animate(_ layer: CIImage, _ kind: ClipAnimation, presence p: CGFloat, canvas: CGSize, unit: CGFloat) -> CIImage {
        let v = 1 - pow(1 - min(max(p, 0), 1), 3)       // eased: quick to arrive, gentle to settle
        let away = 1 - v
        var dx: CGFloat = 0, dy: CGFloat = 0, scale: CGFloat = 1, alpha: CGFloat = 1, blur: CGFloat = 0
        switch kind {
        case .fade: alpha = v
        case .rise: dy = -away * canvas.height * 0.12; alpha = v
        case .slideLeft: dx = -away * canvas.width
        case .slideRight: dx = away * canvas.width
        case .slideUp: dy = -away * canvas.height
        case .slideDown: dy = away * canvas.height
        case .zoomIn: scale = 0.6 + 0.4 * v; alpha = v
        case .zoomOut: scale = 1.4 - 0.4 * v; alpha = v
        case .blur: blur = away * 40 * unit; alpha = v
        case .pop:
            // Overshoots a little past full size, then settles.
            let q = min(max(p, 0), 1) - 1
            scale = max(1 + 2.70158 * q * q * q + 1.70158 * q * q, 0.01)
            alpha = min(p * 4, 1)
        }
        var out = layer
        if blur > 0.5 { out = out.applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: blur]) }
        if scale != 1 || dx != 0 || dy != 0 {
            let cx = canvas.width / 2, cy = canvas.height / 2
            out = out.transformed(by: CGAffineTransform(translationX: cx + dx, y: cy + dy)
                .scaledBy(x: scale, y: scale)
                .translatedBy(x: -cx, y: -cy))
        }
        if alpha < 0.999 {
            out = out.applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: alpha)])
        }
        return out
    }

    private var overlayCache: [String: CIImage] = [:]
    private var pictureCache: [String: CGImage] = [:]

    /// The overlay drawn at its final pixel size, with its origin at (0, 0).
    private func overlayImage(_ o: Overlay, canvas: CGSize, unit: CGFloat, folder: URL?) -> CIImage? {
        let key = "\(o.kind.rawValue)|\(o.text)|\(o.fontPath ?? "")|\(o.size)|\(o.color)|\(String(describing: o.boxColor))|\(o.file ?? "")|\(o.cornerRadius)|\(canvas)"
        lock.lock()
        defer { lock.unlock() }
        if let hit = overlayCache[key] { return hit }
        var result: CIImage?

        switch o.kind {
        case .text:
            let trimmed = o.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            let fontSize = 72 * unit * CGFloat(o.size)
            let font = captionFont(path: o.fontPath, size: fontSize)
            var alignment = CTTextAlignment.center
            let paragraph = withUnsafePointer(to: &alignment) { ptr in
                CTParagraphStyleCreate([CTParagraphStyleSetting(spec: .alignment, valueSize: MemoryLayout<CTTextAlignment>.size, value: ptr)], 1)
            }
            let attributed = NSAttributedString(string: trimmed, attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): o.color.cgColor,
                NSAttributedString.Key(kCTParagraphStyleAttributeName as String): paragraph,
            ])
            let setter = CTFramesetterCreateWithAttributedString(attributed)
            let fit = CTFramesetterSuggestFrameSizeWithConstraints(setter, CFRange(location: 0, length: 0), nil,
                                                                   CGSize(width: canvas.width * 0.92, height: .greatestFiniteMagnitude), nil)
            let padX = fontSize * 0.45, padY = fontSize * 0.25
            let w = Int(ceil(fit.width + padX * 2)), h = Int(ceil(fit.height + padY * 2))
            guard w > 0, h > 0, let cs = CGColorSpace(name: CGColorSpace.sRGB),
                  let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
            else { return nil }
            if let box = o.boxColor, box.a > 0.01 {
                ctx.addPath(CGPath(roundedRect: CGRect(x: 0, y: 0, width: w, height: h),
                                   cornerWidth: fontSize * 0.28, cornerHeight: fontSize * 0.28, transform: nil))
                ctx.setFillColor(box.cgColor)
                ctx.fillPath()
            }
            let textRect = CGRect(x: padX, y: padY, width: ceil(fit.width), height: ceil(fit.height))
            CTFrameDraw(CTFramesetterCreateFrame(setter, CFRange(location: 0, length: 0), CGPath(rect: textRect, transform: nil), nil), ctx)
            result = ctx.makeImage().map { CIImage(cgImage: $0) }

        case .image:
            guard let file = o.file else { return nil }
            let url = file.hasPrefix("/") ? URL(fileURLWithPath: file) : (folder ?? URL(fileURLWithPath: "/")).appendingPathComponent(file)
            if pictureCache[url.path] == nil,
               let src = CGImageSourceCreateWithURL(url as CFURL, nil),
               let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) {
                if pictureCache.count > 12 { pictureCache.removeAll() }
                pictureCache[url.path] = cg
            }
            guard let cg = pictureCache[url.path] else { return nil }
            var picture = CIImage(cgImage: cg)
            let width = max(CGFloat(o.size) * canvas.width, 8)
            let scale = width / picture.extent.width
            picture = scale < 0.98
                ? picture.applyingFilter("CILanczosScaleTransform", parameters: [kCIInputScaleKey: scale, kCIInputAspectRatioKey: 1])
                : picture.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            picture = picture.transformed(by: CGAffineTransform(translationX: -picture.extent.minX, y: -picture.extent.minY))
            let radius = CGFloat(min(max(o.cornerRadius, 0), 0.5)) * min(picture.extent.width, picture.extent.height)
            if radius > 0.5 {
                picture = picture.applyingFilter("CIBlendWithMask", parameters: [
                    kCIInputBackgroundImageKey: CIImage(color: .clear).cropped(to: picture.extent),
                    kCIInputMaskImageKey: roundedRect(picture.extent, radius: radius, color: .white),
                ])
            }
            result = picture

        case .blur, .highlight:
            return nil      // drawn into the recording by `regions`
        }
        if overlayCache.count > 60 { overlayCache.removeAll() }
        if let result { overlayCache[key] = result }
        return result
    }

    private var fontDescriptors: [String: CTFontDescriptor] = [:]

    /// The user's font file if it loads, else the bold system font.
    private func captionFont(path: String?, size: CGFloat) -> CTFont {
        if let path {
            if fontDescriptors[path] == nil,
               let all = CTFontManagerCreateFontDescriptorsFromURL(URL(fileURLWithPath: path) as CFURL) as? [CTFontDescriptor],
               let first = all.first {
                fontDescriptors[path] = first
            }
            if let descriptor = fontDescriptors[path] { return CTFontCreateWithFontDescriptor(descriptor, size, nil) }
        }
        return CTFontCreateUIFontForLanguage(.emphasizedSystem, size, nil) ?? CTFontCreateWithName("Helvetica-Bold" as CFString, size, nil)
    }

    private func captionImage(_ text: String, canvas: CGSize, style: CaptionStyle) -> CIImage? {
        let scale = CGFloat(style.scale)
        let textColor = style.textColor ?? RGBA(r: 1, g: 1, b: 1)
        let boxColor = style.boxColor ?? RGBA(r: 0, g: 0, b: 0, a: 0.62)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let key = "\(trimmed)|\(canvas)|\(scale)|\(style.fontPath ?? "")|\(textColor)|\(boxColor)"
        lock.lock()
        defer { lock.unlock() }
        if let hit = captionCache[key] { return hit }

        let unit = min(canvas.width, canvas.height) / 1080
        let fontSize = 40 * unit * scale
        let font = captionFont(path: style.fontPath, size: fontSize)
        var alignment = CTTextAlignment.center
        let paragraph = withUnsafePointer(to: &alignment) { ptr in
            CTParagraphStyleCreate([CTParagraphStyleSetting(spec: .alignment, valueSize: MemoryLayout<CTTextAlignment>.size, value: ptr)], 1)
        }
        let attributed = NSAttributedString(string: trimmed, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): textColor.cgColor,
            NSAttributedString.Key(kCTParagraphStyleAttributeName as String): paragraph,
        ])
        let setter = CTFramesetterCreateWithAttributedString(attributed)
        let maxWidth = canvas.width * 0.78
        let fit = CTFramesetterSuggestFrameSizeWithConstraints(setter, CFRange(location: 0, length: 0), nil,
                                                               CGSize(width: maxWidth, height: .greatestFiniteMagnitude), nil)
        let padX = fontSize * 0.55, padY = fontSize * 0.32
        let w = Int(ceil(fit.width + padX * 2)), h = Int(ceil(fit.height + padY * 2))
        guard let cs = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return nil }
        let box = CGRect(x: 0, y: 0, width: w, height: h)
        ctx.addPath(CGPath(roundedRect: box, cornerWidth: fontSize * 0.35, cornerHeight: fontSize * 0.35, transform: nil))
        ctx.setFillColor(boxColor.cgColor)
        ctx.fillPath()
        let textRect = CGRect(x: padX, y: padY, width: ceil(fit.width), height: ceil(fit.height))
        let frame = CTFramesetterCreateFrame(setter, CFRange(location: 0, length: 0), CGPath(rect: textRect, transform: nil), nil)
        CTFrameDraw(frame, ctx)
        guard let cg = ctx.makeImage() else { return nil }
        let image = CIImage(cgImage: cg)
        if captionCache.count > 200 { captionCache.removeAll() }
        captionCache[key] = image
        return image
    }
}

// MARK: - AVFoundation glue

final class RenderInstruction: NSObject, AVVideoCompositionInstructionProtocol {
    let timeRange: CMTimeRange
    let enablePostProcessing = false
    let containsTweening = true
    let requiredSourceTrackIDs: [NSValue]?
    let passthroughTrackID = kCMPersistentTrackID_Invalid
    let state: RenderState

    init(timeRange: CMTimeRange, state: RenderState) {
        self.timeRange = timeRange
        self.state = state
        var ids = [NSNumber(value: state.screenTrackID)]
        if let cam = state.cameraTrackID { ids.append(NSNumber(value: cam)) }
        requiredSourceTrackIDs = ids
    }
}

final class FrameCompositor: NSObject, AVVideoCompositing {
    private let queue = DispatchQueue(label: "framecast.compositor")
    private static let attributes: [String: Any] = [
        kCVPixelBufferPixelFormatTypeKey as String: [kCVPixelFormatType_32BGRA],
        kCVPixelBufferMetalCompatibilityKey as String: true,
    ]
    var sourcePixelBufferAttributes: [String: Any]? { Self.attributes }
    var requiredPixelBufferAttributesForRenderContext: [String: Any] { Self.attributes }

    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {}

    func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        queue.async {
            guard let instruction = request.videoCompositionInstruction as? RenderInstruction,
                  let output = request.renderContext.newPixelBuffer() else {
                request.finish(with: NSError(domain: "Framecast", code: 1))
                return
            }
            let state = instruction.state
            let screen = request.sourceFrame(byTrackID: state.screenTrackID)
            let camera = state.cameraTrackID.flatMap { request.sourceFrame(byTrackID: $0) }
            FrameRenderer.shared.render(screen: screen, camera: camera, time: request.compositionTime.seconds,
                                        state: state, to: output)
            request.finish(withComposedVideoFrame: output)
        }
    }

    func cancelAllPendingVideoCompositionRequests() {}
}
