import AVFoundation
import SwiftUI

extension Color {
    /// Framecast's purple. Used only for icons and selection outlines, never for text.
    static let brand = Color(red: 0.43, green: 0.37, blue: 0.96)
}

/// A solid, high-contrast button (white on a dark window, black on a light one) that
/// looks the same whether or not its window is focused.
struct BrandButtonLabel: View {
    let title: String
    var symbol: String?
    var height: CGFloat = 26
    var wide = false
    var body: some View {
        HStack(spacing: 6) {
            if let symbol { Image(systemName: symbol).font(.system(size: 11, weight: .semibold)) }
            Text(title).font(.system(size: height > 30 ? 13 : 12, weight: .semibold))
        }
        .foregroundStyle(Color(nsColor: .windowBackgroundColor))
        .padding(.horizontal, 13)
        .frame(maxWidth: wide ? .infinity : nil)
        .frame(height: height)
        .background(Color.primary, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .contentShape(Rectangle())
    }
}

struct EditorView: View {
    @ObservedObject var model: EditorModel
    @ObservedObject private var presets = PresetStore.shared
    @FocusState private var nameFocused: Bool
    @State private var showExport = false
    @State private var resolution: ExportResolution = .p1080
    @State private var fps: Int32 = 60

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    PreviewView(model: model)
                        .padding(28)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    EditorTimeline(model: model)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 16)
                }
                .background(Color(nsColor: .underPageBackgroundColor))
                Divider()
                InspectorView(model: model)
                    .frame(width: 380)
            }
        }
        .frame(minWidth: 1080, minHeight: 640)
        .ignoresSafeArea(.container, edges: .top)
        .sheet(isPresented: Binding(get: { model.exportPhase != .idle }, set: { _ in })) {
            ExportProgressView(model: model)
        }
        .alert("Couldn't open this recording", isPresented: Binding(get: { model.loadError != nil }, set: { _ in model.loadError = nil })) {
            Button("OK") {}
        } message: { Text(model.loadError ?? "") }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Spacer().frame(width: 68)
            TextField("Name", text: $model.project.name)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .semibold))
                .frame(maxWidth: 320, alignment: .leading)
                .focused($nameFocused)
                .onSubmit {
                    nameFocused = false
                    model.commitName()
                }
                .onExitCommand {
                    nameFocused = false
                    model.endTextEditing()
                }
                .help("Rename this recording, then press Return")
            if model.nameSaved {
                Label("Saved", systemImage: "checkmark.circle.fill")
                    .font(.caption).foregroundStyle(.green)
                    .transition(.opacity)
            }
            if let note = model.externalNote {
                Label(note, systemImage: "sparkles").font(.caption).foregroundStyle(.secondary).transition(.opacity)
            }
            Spacer()
            Menu {
                Button("Open in Claude") { model.openInClaude() }
                Button("Open My Editing Style…") { model.openEditingStyle() }
                Divider()
                Button("Copy Request Instead") { model.copyClaudeRequest() }
                Button("Show Recording Folder") { NSWorkspace.shared.activateFileViewerSelecting([model.folder]) }
            } label: {
                Text("Edit with Claude")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Have Claude edit this recording the way your editing style describes")
            styleMenu
            Button { showExport.toggle() } label: { BrandButtonLabel(title: "Export", symbol: "square.and.arrow.up") }
                .buttonStyle(.plain)
                .help("Export this video")
            .popover(isPresented: $showExport, arrowEdge: .bottom) { exportPopover }
        }
        .padding(.horizontal, 14)
        .frame(height: 48)
    }

    private var styleMenu: some View {
        Menu {
            if presets.presets.isEmpty {
                Text("No saved presets yet")
            } else {
                ForEach(presets.presets) { preset in
                    Button(preset.name) { model.applyPreset(preset) }
                }
            }
            Divider()
            Button("Save Current Look as Preset…") { model.saveCurrentStyle() }
            if !presets.presets.isEmpty {
                Menu("Use for New Recordings") {
                    Button { presets.defaultID = nil } label: {
                        if presets.defaultID == nil { Label("None", systemImage: "checkmark") } else { Text("None") }
                    }
                    ForEach(presets.presets) { preset in
                        Button { presets.defaultID = preset.id } label: {
                            if presets.defaultID == preset.id { Label(preset.name, systemImage: "checkmark") } else { Text(preset.name) }
                        }
                    }
                }
                Menu("Delete Preset") {
                    ForEach(presets.presets) { preset in
                        Button(preset.name, role: .destructive) { presets.delete(preset) }
                    }
                }
            }
        } label: {
            Text("Presets")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Saved presets: reusable looks for your videos")
    }

    private var exportPopover: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Resolution").font(.caption).foregroundStyle(.secondary)
                Picker("", selection: $resolution) {
                    ForEach(ExportResolution.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden()
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Frame rate").font(.caption).foregroundStyle(.secondary)
                Picker("", selection: $fps) {
                    Text("30 fps").tag(Int32(30))
                    Text("60 fps").tag(Int32(60))
                }
                .pickerStyle(.segmented).labelsHidden()
            }
            let size = model.project.canvasSize(shortSide: resolution.shortSide(for: model.project))
            Text("MP4 · \(Int(size.width)) × \(Int(size.height)) · \(timeString(model.duration))")
                .font(.caption).foregroundStyle(.secondary)
            Button {
                showExport = false
                model.export(resolution: resolution, fps: fps)
            } label: {
                BrandButtonLabel(title: "Export Video", height: 34, wide: true)
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .frame(width: 260)
    }
}

func timeString(_ seconds: Double) -> String {
    let s = max(Int(seconds.rounded(.down)), 0)
    return String(format: "%d:%02d", s / 60, s % 60)
}

// MARK: - Preview

private struct PlayerLayerView: NSViewRepresentable {
    let player: AVPlayer

    final class LayerView: NSView {
        let playerLayer = AVPlayerLayer()
        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            playerLayer.videoGravity = .resizeAspect
            layer?.addSublayer(playerLayer)
        }
        required init?(coder: NSCoder) { fatalError() }
        override func layout() {
            super.layout()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            playerLayer.frame = bounds
            CATransaction.commit()
        }
    }

    func makeNSView(context: Context) -> LayerView {
        let view = LayerView()
        view.playerLayer.player = player
        return view
    }
    func updateNSView(_ nsView: LayerView, context: Context) {}
}

struct PreviewView: View {
    @ObservedObject var model: EditorModel
    @State private var dragStart: CGPoint?
    @State private var regionGrab: CGSize?

    var body: some View {
        PlayerLayerView(player: model.player)
            .aspectRatio(model.canvasAspect, contentMode: .fit)
            .overlay {
                GeometryReader { geo in
                    ZStack(alignment: .topLeading) {
                        cameraHandle(in: geo.size)
                        overlayHandle(in: geo.size)
                        regionHandle(in: geo.size)
                    }
                }
            }
            .coordinateSpace(name: "preview")
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .shadow(color: .black.opacity(0.25), radius: 18, y: 8)
    }

    /// A small grab handle on the selected text or image, for dragging it around the frame.
    @ViewBuilder private func overlayHandle(in size: CGSize) -> some View {
        if let overlay = model.selectedOverlayBinding, !overlay.wrappedValue.kind.isRegion, size.width > 0 {
            let value = overlay.wrappedValue
            Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(Color.brand, in: Circle())
                .overlay(Circle().strokeBorder(.white, lineWidth: 1.5))
                .shadow(radius: 3)
                .position(x: value.x * size.width, y: value.y * size.height)
                .gesture(
                    DragGesture(minimumDistance: 1, coordinateSpace: .named("preview"))
                        .onChanged { drag in
                            overlay.wrappedValue.x = min(max(drag.location.x / size.width, 0), 1)
                            overlay.wrappedValue.y = min(max(drag.location.y / size.height, 0), 1)
                        }
                )
                .help("Drag to move")
        }
    }

    /// The selected blur or highlight box: drag it to move, drag the corner dot to resize.
    @ViewBuilder private func regionHandle(in size: CGSize) -> some View {
        if let overlay = model.selectedOverlayBinding, overlay.wrappedValue.kind.isRegion, size.width > 0 {
            let value = overlay.wrappedValue
            let frame = model.screenFrame(in: size)
            let w = CGFloat(value.boxWidth) * frame.width, h = CGFloat(value.boxHeight) * frame.height
            let cx = frame.minX + CGFloat(value.x) * frame.width, cy = frame.minY + CGFloat(value.y) * frame.height
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .strokeBorder(.white, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                .background(Color.white.opacity(0.001))
                .shadow(color: .black.opacity(0.6), radius: 1)
                .contentShape(Rectangle())
                .frame(width: max(w, 6), height: max(h, 6))
                .position(x: cx, y: cy)
                .gesture(
                    DragGesture(minimumDistance: 1, coordinateSpace: .named("preview"))
                        .onChanged { drag in
                            if regionGrab == nil {
                                model.checkpoint()
                                regionGrab = CGSize(width: drag.startLocation.x - cx, height: drag.startLocation.y - cy)
                            }
                            let grab = regionGrab ?? .zero
                            overlay.wrappedValue.x = Double(min(max((drag.location.x - grab.width - frame.minX) / frame.width, 0), 1))
                            overlay.wrappedValue.y = Double(min(max((drag.location.y - grab.height - frame.minY) / frame.height, 0), 1))
                        }
                        .onEnded { _ in regionGrab = nil }
                )
                .help("Drag to move")
            Circle()
                .fill(.white)
                .frame(width: 12, height: 12)
                .shadow(color: .black.opacity(0.5), radius: 2)
                .position(x: cx + w / 2, y: cy + h / 2)
                .gesture(
                    DragGesture(minimumDistance: 1, coordinateSpace: .named("preview"))
                        .onChanged { drag in
                            if regionGrab == nil { model.checkpoint(); regionGrab = .zero }
                            overlay.wrappedValue.w = Double(min(max(2 * (drag.location.x - cx) / frame.width, 0.02), 1))
                            overlay.wrappedValue.h = Double(min(max(2 * (drag.location.y - cy) / frame.height, 0.02), 1))
                        }
                        .onEnded { _ in regionGrab = nil }
                )
                .help("Drag to resize")
        }
    }

    /// An invisible handle over the camera so it can be dragged anywhere on the canvas.
    @ViewBuilder private func cameraHandle(in size: CGSize) -> some View {
        if model.hasCamera, model.project.camera.visible, size.width > 0 {
            let rect = Layout.cameraRect(canvas: size, style: model.project.camera)
            Color.clear
                .contentShape(Rectangle())
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
                .gesture(
                    DragGesture(minimumDistance: 2)
                        .onChanged { value in
                            let start = dragStart ?? CGPoint(x: rect.midX, y: rect.midY)
                            if dragStart == nil { dragStart = start }
                            let x = min(max((start.x + value.translation.width) / size.width, 0), 1)
                            let y = min(max((start.y + value.translation.height) / size.height, 0), 1)
                            model.project.camera.customCenter = CGPoint(x: x, y: y)
                        }
                        .onEnded { _ in dragStart = nil }
                )
                .help("Drag to move the camera")
        }
    }
}

// MARK: - Timeline

/// The editing timeline: a time ruler, the clips back to back, then zoom and camera tracks.
struct EditorTimeline: View {
    @ObservedObject var model: EditorModel

    private enum ClipDrag { case scrub, trimStart(Int, Clip), trimEnd(Int, Clip) }
    @State private var drag: ClipDrag?
    @State private var draft: [Clip]?
    @State private var frozenScale: CGFloat?

    @State private var regionOrigin: (start: Double, end: Double)?
    @State private var regionEdge = 0
    @State private var regionDragging = false
    @State private var regionCheckpointed = false
    @State private var showShortcuts = false
    @State private var showAnimations = false
    @State private var audioOrigin: AudioClip?
    @State private var pinchBase: Double?

    private let rulerHeight: CGFloat = 18
    private let clipHeight: CGFloat = 66
    private let waveHeight: CGFloat = 20
    private let rowHeight: CGFloat = 20
    private let gap: CGFloat = 5

    private var zoomRowY: CGFloat { rulerHeight + clipHeight + gap }
    private var cameraRowY: CGFloat { zoomRowY + rowHeight + gap }
    private var overlayRowY: CGFloat { (model.hasCamera ? cameraRowY : zoomRowY) + rowHeight + gap }
    private var imageRowY: CGFloat { overlayRowY + rowHeight + gap }
    private var regionRowY: CGFloat { imageRowY + rowHeight + gap }
    private var audioRowY: CGFloat { regionRowY + rowHeight + gap }
    private var totalHeight: CGFloat { audioRowY + CGFloat(audioLaneCount) * (rowHeight + gap) - gap }

    /// Overlapping music clips are stacked on separate lanes so each stays visible.
    private var audioLanes: [UUID: Int] {
        var ends: [Double] = []
        var lanes: [UUID: Int] = [:]
        for clip in (model.project.audioClips ?? []).sorted(by: { $0.start < $1.start }) {
            if let lane = ends.firstIndex(where: { $0 <= clip.start + 0.001 }) {
                ends[lane] = clip.start + clip.duration
                lanes[clip.id] = lane
            } else {
                lanes[clip.id] = min(ends.count, 3)
                if ends.count < 4 { ends.append(clip.start + clip.duration) }
            }
        }
        return lanes
    }
    private var audioLaneCount: Int { ((audioLanes.values.max() ?? 0) + 1) }

    var body: some View {
        VStack(spacing: 8) {
            toolbar
            GeometryReader { geo in
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: model.timelineZoom > 1.01) {
                        tracks(width: max(geo.size.width * CGFloat(model.timelineZoom), 50))
                    }
                    .onChange(of: model.currentTime) { _, _ in
                        if model.isPlaying, model.timelineZoom > 1.01 { proxy.scrollTo("playhead", anchor: .center) }
                    }
                    .onChange(of: model.timelineZoom) { _, _ in proxy.scrollTo("playhead", anchor: .center) }
                }
            }
            // Pinch on the trackpad to zoom the timeline in and out.
            .gesture(
                MagnifyGesture()
                    .onChanged { value in
                        let base = pinchBase ?? model.timelineZoom
                        if pinchBase == nil { pinchBase = base }
                        model.timelineZoom = min(max(base * Double(value.magnification), 1), 40)
                    }
                    .onEnded { _ in pinchBase = nil }
            )
            .frame(height: totalHeight + (model.timelineZoom > 1.01 ? 12 : 0))
        }
    }

    // MARK: Toolbar

    private var toolbar: some View {
        HStack(spacing: 6) {
            Button { model.togglePlay() } label: {
                Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 13))
                    .frame(width: 30, height: 30)
                    .background(.quaternary, in: Circle())
            }
            .buttonStyle(.plain)
            .help("Play / Pause (Space)")
            Text("\(preciseTime(model.currentTime)) / \(preciseTime(model.duration))")
                .font(.system(size: 12, weight: .medium).monospacedDigit())
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
            Spacer()
            if model.clips.count > 1 || abs(model.duration - model.project.duration) > 0.05 {
                Button("Restore Full Video") { model.resetEdits() }
                    .buttonStyle(.link).font(.caption)
                    .padding(.trailing, 4)
            }
            tool("scissors", "Split at the playhead (S)") { model.split() }
            tool("arrow.right.to.line", "Cut away the start of this clip up to the playhead (Q)") { model.trimToPlayhead(start: true) }
            tool("arrow.left.to.line", "Cut away the rest of this clip after the playhead (W)") { model.trimToPlayhead(start: false) }
            tool("trash", "Delete the selected clip, zoom or camera section (Delete)") { model.deleteSelection() }
                .disabled(model.selectedZoom == nil && model.selectedCamera == nil
                          && (model.selectedClip == nil || model.clips.count < 2))
            divider
            tool("arrow.uturn.backward", "Undo (⌘Z)") { model.undo() }.disabled(!model.canUndo)
            tool("arrow.uturn.forward", "Redo (⇧⌘Z)") { model.redo() }.disabled(!model.canRedo)
            divider
            Menu {
                ForEach([0.25, 0.5, 0.75, 1, 1.25, 1.5, 2, 3, 4, 8], id: \.self) { speed in
                    Button {
                        model.setSpeed(speed)
                    } label: {
                        let current = model.animationTarget.map { abs(model.clips[$0].rate - speed) < 0.001 } ?? false
                        let name = speed == 1 ? "Normal (1×)" : speedLabel(speed) + (speed < 1 ? "  slower" : "  faster")
                        if current { Label(name, systemImage: "checkmark") } else { Text(name) }
                    }
                }
            } label: {
                Image(systemName: "speedometer")
            }
            .menuStyle(.borderedButton)
            .menuIndicator(.hidden)
            .controlSize(.small)
            .fixedSize()
            .help("Speed up or slow down the selected clip. Split first to change just one part.")
            tool("sparkles", "Entry and exit animations for the selected clip") { showAnimations.toggle() }
                .popover(isPresented: $showAnimations, arrowEdge: .top) { AnimationPicker(model: model) }
            Menu {
                Button("Text  (T)") { model.addText() }
                Button("Image…") { model.addImage() }
                Button("Music or Sound Effect…") { model.addAudio() }
                Divider()
                Button("Blur (hide something)") { model.addRegion(.blur) }
                Button("Highlight") { model.addRegion(.highlight) }
                Button("Spotlight") { model.addRegion(.highlight, spotlight: true) }
                Divider()
                Button("Zoom  (Z)") { model.addZoom() }
                if model.hasCamera { Button("Camera Layout Section  (C)") { model.addCameraSection() } }
            } label: {
                Label("Add", systemImage: "plus")
            }
            .menuStyle(.borderedButton)
            .controlSize(.small)
            .fixedSize()
            .help("Add text, an image, audio, a zoom or a camera section at the playhead")
            divider
            Image(systemName: "minus.magnifyingglass").font(.system(size: 11)).foregroundStyle(.secondary)
            Slider(value: Binding(get: { log(model.timelineZoom) }, set: { model.timelineZoom = exp($0) }), in: 0...log(40))
                .controlSize(.mini)
                .frame(width: 80)
                .help("Zoom the timeline (⌘+ / ⌘−, ⌘0 to fit)")
            Image(systemName: "plus.magnifyingglass").font(.system(size: 11)).foregroundStyle(.secondary)
            tool("keyboard", "Keyboard shortcuts") { showShortcuts.toggle() }
                .popover(isPresented: $showShortcuts, arrowEdge: .top) { shortcuts }
        }
    }

    private var divider: some View {
        Rectangle().fill(.primary.opacity(0.12)).frame(width: 1, height: 18).padding(.horizontal, 3)
    }

    private func tool(_ symbol: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 12)).frame(width: 24, height: 22)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .help(help)
    }

    private var shortcuts: some View {
        let rows: [(String, String)] = [
            ("Space", "Play / pause"), ("← →", "Step one frame"), ("⇧← ⇧→", "Step one second"),
            ("J  L", "Jump 2 seconds back / forward"), ("↑ ↓", "Previous / next cut"),
            ("S or ⌘B", "Split at the playhead"), ("Q", "Cut away the clip's start up to the playhead"),
            ("W", "Cut away the rest of the clip"), ("Delete", "Delete what is selected"),
            ("Z", "Add a zoom"), ("C", "Add a camera layout section"), ("T", "Add text"),
            ("Pinch", "Zoom the timeline on a trackpad"),
            ("⌘Z  ⇧⌘Z", "Undo / redo"), ("⌘+  ⌘−  ⌘0", "Zoom the timeline in / out / fit"), ("Esc", "Deselect"),
        ]
        return VStack(alignment: .leading, spacing: 7) {
            Text("Keyboard Shortcuts").font(.headline).padding(.bottom, 2)
            ForEach(rows, id: \.0) { row in
                HStack(spacing: 12) {
                    Text(row.0).font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .frame(width: 92, alignment: .leading)
                    Text(row.1).font(.callout).foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
    }

    private func preciseTime(_ t: Double) -> String {
        let total = max(t, 0)
        return String(format: "%d:%04.1f", Int(total) / 60, total.truncatingRemainder(dividingBy: 60))
    }

    // MARK: Tracks

    private func tracks(width: CGFloat) -> some View {
        let clips = draft ?? model.clips
        let map = TimeMap(clips: clips)
        let scale = frozenScale ?? width / CGFloat(max(map.duration, 0.01))
        let playheadX = min(max(CGFloat(model.currentTime) * scale, 0), width)

        return ZStack(alignment: .topLeading) {
            // A real (laid-out) marker so the scroll view can follow the playhead.
            HStack(spacing: 0) {
                Color.clear.frame(width: max(playheadX - 1, 0), height: 1)
                Color.clear.frame(width: 2, height: 1).id("playhead")
                Spacer(minLength: 0)
            }
            .frame(width: width, height: 1, alignment: .leading)

            ruler(width: width, scale: scale, total: map.duration)

            ForEach(Array(clips.enumerated()), id: \.element.id) { index, clip in
                clipView(clip, width: CGFloat(clip.length) * scale, selected: clip.id == model.selectedClip)
                    .offset(x: CGFloat(map.outputStart(of: index)) * scale, y: rulerHeight)
            }
            Color.clear
                .contentShape(Rectangle())
                .frame(width: width, height: rulerHeight + clipHeight)
                .gesture(clipGesture(width: width, scale: scale))

            trackBackground(width: width, y: zoomRowY, empty: model.zoomItems.isEmpty,
                            hint: "Zooms — press Z or use Add to place one")
            ForEach(model.zoomItems) { item in zoomPill(item, map: map, scale: scale) }

            if model.hasCamera {
                let sections = model.project.cameraSections ?? []
                trackBackground(width: width, y: cameraRowY, empty: sections.isEmpty,
                                hint: "Camera layout — press C to move, enlarge or hide the camera for a section")
                ForEach(sections) { section in cameraPill(section, map: map, scale: scale) }
            }

            let texts = (model.project.overlays ?? []).filter { $0.kind == .text }
            let images = (model.project.overlays ?? []).filter { $0.kind == .image }
            trackBackground(width: width, y: overlayRowY, empty: texts.isEmpty, hint: "Text — press T, or use Add")
            ForEach(texts) { overlay in overlayPill(overlay, map: map, scale: scale) }
            trackBackground(width: width, y: imageRowY, empty: images.isEmpty, hint: "Images — use Add to place a picture")
            ForEach(images) { overlay in overlayPill(overlay, map: map, scale: scale) }

            let boxes = (model.project.overlays ?? []).filter { $0.kind.isRegion }
            trackBackground(width: width, y: regionRowY, empty: boxes.isEmpty, hint: "Blur and highlights — use Add to hide or point out part of the screen")
            ForEach(boxes) { overlay in overlayPill(overlay, map: map, scale: scale) }

            let audio = model.project.audioClips ?? []
            let lanes = audioLanes
            ForEach(0..<audioLaneCount, id: \.self) { lane in
                trackBackground(width: width, y: audioRowY + CGFloat(lane) * (rowHeight + gap), empty: audio.isEmpty,
                                hint: "Music and sound effects — use Add to place one at the playhead")
            }
            ForEach(audio) { clip in audioPill(clip, lane: lanes[clip.id] ?? 0, map: map, scale: scale) }

            RoundedRectangle(cornerRadius: 1)
                .fill(.white)
                .frame(width: 2, height: totalHeight)
                .shadow(color: .black.opacity(0.5), radius: 1)
                .offset(x: min(max(playheadX - 1, 0), width - 2))
                .allowsHitTesting(false)
        }
        .frame(width: width, height: totalHeight, alignment: .topLeading)
        .clipped()
        .coordinateSpace(name: "timeline")
    }

    private func ruler(width: CGFloat, scale: CGFloat, total: Double) -> some View {
        Canvas { context, size in
            let steps: [Double] = [0.1, 0.2, 0.5, 1, 2, 5, 10, 15, 30, 60, 120, 300, 600]
            let step = steps.first { CGFloat($0) * scale >= 62 } ?? 600
            var t = 0.0
            while t <= total + 0.0001 {
                let x = CGFloat(t) * scale
                context.fill(Path(CGRect(x: x, y: size.height - 6, width: 1, height: 6)), with: .color(.secondary.opacity(0.6)))
                let label = step < 1 ? String(format: "%d:%04.1f", Int(t) / 60, t.truncatingRemainder(dividingBy: 60))
                                     : String(format: "%d:%02d", Int(t) / 60, Int(t) % 60)
                context.draw(Text(label).font(.system(size: 9).monospacedDigit()).foregroundColor(.secondary),
                             at: CGPoint(x: x + 4, y: 6), anchor: .leading)
                // Four minor ticks between labels.
                for minor in 1..<5 {
                    let mx = CGFloat(t + step * Double(minor) / 5) * scale
                    if mx < size.width {
                        context.fill(Path(CGRect(x: mx, y: size.height - 3, width: 1, height: 3)), with: .color(.secondary.opacity(0.35)))
                    }
                }
                t += step
            }
        }
        .frame(width: width, height: rulerHeight)
        .allowsHitTesting(false)
    }

    private func trackBackground(width: CGFloat, y: CGFloat, empty: Bool, hint: String) -> some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color.primary.opacity(0.05))
            if empty {
                Text(hint).font(.system(size: 10)).foregroundStyle(.tertiary).padding(.leading, 8).lineLimit(1)
            }
        }
        .frame(width: width, height: rowHeight)
        .offset(y: y)
        .allowsHitTesting(false)
    }

    private func clipView(_ clip: Clip, width: CGFloat, selected: Bool) -> some View {
        let w = max(width - 2, 2)
        let count = min(max(1, Int(w / 84)), 60)
        return HStack(spacing: 0) {
            ForEach(0..<count, id: \.self) { slot in
                let t = clip.start + (Double(slot) + 0.5) / Double(count) * clip.sourceLength
                if let image = model.thumbnail(at: t) {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                        .frame(width: w / CGFloat(count), height: clipHeight)
                        .clipped()
                } else {
                    Color.gray.opacity(0.25).frame(width: w / CGFloat(count), height: clipHeight)
                }
            }
        }
        .frame(width: w, height: clipHeight)
        .overlay(alignment: .bottom) {
            // The recording's sound: tall bars where someone is talking, flat where it is silent.
            if !model.voicePeaks.isEmpty {
                Canvas { context, size in
                    context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black.opacity(0.62)))
                    let bars = max(Int(size.width / 2), 1)
                    let span = clip.sourceLength / Double(bars)
                    var path = Path()
                    for i in 0..<bars {
                        let t = clip.start + Double(i) * span
                        let level = CGFloat(sqrt(model.voiceLevel(from: t, to: t + span)))
                        let height = max(level * (size.height - 4), 1)
                        path.addRect(CGRect(x: CGFloat(i) * 2, y: (size.height - height) / 2, width: 1.2, height: height))
                    }
                    context.fill(path, with: .color(.white.opacity(0.92)))
                }
                .frame(width: w, height: waveHeight)
                .allowsHitTesting(false)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(selected ? Color.brand : Color.white.opacity(0.14), lineWidth: selected ? 2 : 1)
        }
        .overlay {
            if selected && w > 30 {
                HStack {
                    grip
                    Spacer()
                    grip
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            if clip.speed != nil, w > 40 {
                Text(speedLabel(clip.rate))
                    .font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                    .padding(.horizontal, 5).frame(height: 15)
                    .background(Color.orange.opacity(0.95), in: Capsule())
                    .padding(.trailing, 9).padding(.top, 4)
                    .help("Plays at \(speedLabel(clip.rate)) speed")
            }
        }
        .overlay(alignment: .bottomLeading) {
            if let entry = clip.entry, w > 44 { animationBadge(entry, leading: true) }
        }
        .overlay(alignment: .bottomTrailing) {
            if let exit = clip.exit, w > 44 { animationBadge(exit, leading: false) }
        }
    }

    private func speedLabel(_ rate: Double) -> String {
        rate == rate.rounded() ? "\(Int(rate))×" : String(format: "%g×", rate)
    }

    private func animationBadge(_ kind: ClipAnimation, leading: Bool) -> some View {
        HStack(spacing: 3) {
            Image(systemName: "sparkles").font(.system(size: 8, weight: .bold))
            Text(kind.label).font(.system(size: 8.5, weight: .semibold)).lineLimit(1)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 5)
        .frame(height: 15)
        .background(Color.pink.opacity(0.9), in: Capsule())
        .padding(.horizontal, 9)
        .padding(.bottom, model.voicePeaks.isEmpty ? 4 : waveHeight + 3)
        .help(leading ? "Entry: \(kind.label)" : "Exit: \(kind.label)")
    }

    private var grip: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(Color.brand)
            .frame(width: 6, height: clipHeight)
            .overlay(RoundedRectangle(cornerRadius: 1).fill(.white).frame(width: 2, height: 16))
    }

    private func clipGesture(width: CGFloat, scale: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let clips = draft ?? model.clips
                if drag == nil {
                    model.endTextEditing()
                    // Decide once, at mouse-down, whether this is an edge trim or a scrub.
                    let x = value.startLocation.x
                    let onClips = value.startLocation.y >= rulerHeight
                    var chosen = ClipDrag.scrub
                    var left: CGFloat = 0
                    for (i, clip) in clips.enumerated() {
                        let right = left + CGFloat(clip.length) * scale
                        if onClips, x >= left, x < right {
                            if right - left > 24 {
                                if x - left < 8 { chosen = .trimStart(i, clip) }
                                else if right - x < 8 { chosen = .trimEnd(i, clip) }
                            }
                            model.clearSelection()
                            model.selectedClip = clip.id
                        }
                        left = right
                    }
                    drag = chosen
                    model.pause()
                    if case .scrub = chosen {} else {
                        frozenScale = scale
                        draft = clips
                    }
                }
                let dt = Double(value.translation.width / scale)
                switch drag {
                case .trimStart(let i, let original):
                    let lower = i > 0 ? clips[i - 1].end : 0
                    draft?[i].start = min(max(original.start + dt * original.rate, lower), original.end - 0.2)
                case .trimEnd(let i, let original):
                    let upper = i + 1 < clips.count ? clips[i + 1].start : model.project.duration
                    draft?[i].end = max(min(original.end + dt * original.rate, upper), original.start + 0.2)
                default:
                    var x = min(max(value.location.x, 0), width)
                    // Snap to a cut when the pointer is right next to one.
                    var edge: CGFloat = 0
                    for clip in clips {
                        edge += CGFloat(clip.length) * scale
                        if abs(x - edge) < 5 { x = edge }
                    }
                    model.seek(Double(x / scale))
                }
            }
            .onEnded { _ in
                if let draft {
                    let map = TimeMap(clips: draft)
                    // Park the playhead on the edge that was just moved.
                    switch drag {
                    case .trimStart(let i, _): model.currentTime = map.outputStart(of: i)
                    case .trimEnd(let i, _): model.currentTime = max(map.outputStart(of: i) + draft[i].length - 0.04, 0)
                    default: break
                    }
                    if draft == model.clips { model.seek(model.currentTime) } else { model.commitClips(draft) }
                }
                drag = nil
                draft = nil
                frozenScale = nil
            }
    }

    // MARK: Zoom and camera blocks

    /// A block on one of the lower tracks. `write` is nil for blocks that can't be moved.
    private func regionPill(start: Double, end: Double, y: CGFloat, label: String, tint: Color, selected: Bool,
                            map: TimeMap, scale: CGFloat, help: String, outputTime: Bool = false,
                            select: @escaping () -> Void,
                            write: ((Double, Double) -> Void)?) -> some View {
        // Zooms and camera sections follow the raw recording; text, images and audio sit on the edit.
        let x0 = CGFloat(outputTime ? start : map.output(start)) * scale
        let x1 = CGFloat(outputTime ? end : map.output(end)) * scale
        let w = max(x1 - x0, 8)
        return RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(tint.opacity(selected ? 0.95 : 0.5))
            .overlay {
                if w > 40 {
                    Text(label).font(.system(size: 9.5, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(.white.opacity(selected ? 0.9 : 0), lineWidth: 1.5)
            }
            .frame(width: w, height: rowHeight)
            .contentShape(Rectangle())
            .offset(x: x0, y: y)
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named("timeline"))
                    .onChanged { value in
                        if !regionDragging {
                            regionDragging = true
                            regionCheckpointed = false
                            select()
                            if write != nil {
                                regionOrigin = (start, end)
                                let local = value.startLocation.x - x0
                                regionEdge = w < 28 ? 0 : (local < 7 ? -1 : (local > w - 7 ? 1 : 0))
                            }
                        }
                        guard let origin = regionOrigin, let write, abs(value.translation.width) > 2 else { return }
                        if !regionCheckpointed { model.checkpoint(); regionCheckpointed = true }
                        let dt = Double(value.translation.width / scale)
                        let total = outputTime ? model.duration : model.project.duration
                        switch regionEdge {
                        case -1: write(min(max(origin.start + dt, 0), origin.end - 0.4), origin.end)
                        case 1: write(origin.start, max(min(origin.end + dt, total), origin.start + 0.4))
                        default:
                            let length = origin.end - origin.start
                            let s = min(max(origin.start + dt, 0), max(total - length, 0))
                            write(s, s + length)
                        }
                    }
                    .onEnded { _ in
                        regionDragging = false
                        regionOrigin = nil
                    }
            )
            .help(help)
    }

    private func zoomPill(_ item: ZoomItem, map: TimeMap, scale: CGFloat) -> some View {
        var write: ((Double, Double) -> Void)?
        if case .manual(let id) = item.kind {
            write = { start, end in
                guard let index = model.project.manualZooms?.firstIndex(where: { $0.id == id }) else { return }
                model.project.manualZooms?[index].start = start
                model.project.manualZooms?[index].end = end
            }
        }
        return regionPill(start: item.start, end: item.end, y: zoomRowY, label: write == nil ? "Auto zoom" : "Zoom",
                          tint: write == nil ? .gray : .brand, selected: model.selectedZoom == item.id,
                          map: map, scale: scale,
                          help: write == nil ? "Automatic zoom from your clicks" : "Drag to move, drag the ends to resize",
                          select: { model.clearSelection(); model.selectedZoom = item.id },
                          write: write)
    }

    private func overlayPill(_ overlay: Overlay, map: TimeMap, scale: CGFloat) -> some View {
        let label: String, y: CGFloat, tint: Color
        switch overlay.kind {
        case .text: label = overlay.text.replacingOccurrences(of: "\n", with: " "); y = overlayRowY; tint = .orange
        case .image: label = "Image"; y = imageRowY; tint = .indigo
        case .blur: label = "Blur"; y = regionRowY; tint = .cyan
        case .highlight: label = overlay.spotlight == true ? "Spotlight" : "Highlight"; y = regionRowY; tint = .yellow
        }
        return regionPill(start: overlay.start, end: overlay.end, y: y, label: label,
                          tint: tint, selected: model.selectedOverlay == overlay.id,
                          map: map, scale: scale, help: "Drag to move, drag the ends to change how long it shows",
                          outputTime: true,
                          select: { model.clearSelection(); model.selectedOverlay = overlay.id },
                          write: { start, end in
                              guard let index = model.project.overlays?.firstIndex(where: { $0.id == overlay.id }) else { return }
                              model.project.overlays?[index].start = start
                              model.project.overlays?[index].end = end
                          })
    }

    private func audioPill(_ clip: AudioClip, lane: Int, map: TimeMap, scale: CGFloat) -> some View {
        regionPill(start: clip.start, end: clip.start + clip.duration, y: audioRowY + CGFloat(lane) * (rowHeight + gap), label: "♪ " + clip.name,
                   tint: .green, selected: model.selectedAudio == clip.id,
                   map: map, scale: scale, help: "Drag to move, drag the ends to trim",
                   outputTime: true,
                   select: { model.clearSelection(); model.selectedAudio = clip.id; audioOrigin = clip },
                   write: { start, end in
                       guard let o = audioOrigin, let index = model.project.audioClips?.firstIndex(where: { $0.id == clip.id }) else { return }
                       switch regionEdge {
                       case -1:
                           // Trimming the front: the sound that plays at any moment stays the same.
                           let newStart = max(start, o.start - o.offset)
                           model.project.audioClips?[index].start = newStart
                           model.project.audioClips?[index].offset = o.offset + (newStart - o.start)
                           model.project.audioClips?[index].duration = o.start + o.duration - newStart
                       case 1:
                           model.project.audioClips?[index].duration = max(min(end - o.start, o.fileDuration - o.offset), 0.2)
                       default:
                           model.project.audioClips?[index].start = start
                       }
                   })
    }

    private func cameraPill(_ section: CameraSection, map: TimeMap, scale: CGFloat) -> some View {
        let label: String
        switch section.mode {
        case .fullscreen: label = "Camera fullscreen"
        case .hidden: label = "Camera hidden"
        case .position:
            let rows = ["Top", "Middle", "Bottom"], cols = ["left", "centre", "right"]
            label = "\(rows[min(max(section.anchor.row, 0), 2)]) \(cols[min(max(section.anchor.col, 0), 2)])"
        }
        return regionPill(start: section.start, end: section.end, y: cameraRowY, label: label,
                          tint: section.mode == .hidden ? .gray : .teal, selected: model.selectedCamera == section.id,
                          map: map, scale: scale, help: "Drag to move, drag the ends to resize",
                          select: { model.clearSelection(); model.selectedCamera = section.id },
                          write: { start, end in
                              guard let index = model.project.cameraSections?.firstIndex(where: { $0.id == section.id }) else { return }
                              model.project.cameraSections?[index].start = start
                              model.project.cameraSections?[index].end = end
                          })
    }
}

// MARK: - Animations

/// Picks how a clip arrives (entry) and leaves (exit). Choosing one plays it back.
struct AnimationPicker: View {
    @ObservedObject var model: EditorModel

    var body: some View {
        let index = model.animationTarget
        let clip = index.map { model.clips[$0] }
        VStack(alignment: .leading, spacing: 12) {
            Text(index.map { "Clip \($0 + 1) of \(model.clips.count)" } ?? "No clip")
                .font(.headline)
            Text("Animations play at the start and end of a clip, so add them on either side of a cut. Pick one to preview it.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            group("ENTRY — how the clip arrives", current: clip?.entry, entry: true)
            group("EXIT — how the clip leaves", current: clip?.exit, entry: false)
            HStack(spacing: 10) {
                Text("Length").font(.callout)
                Slider(value: Binding(get: { model.project.animationDuration ?? 0.5 },
                                      set: { model.project.animationDuration = $0 }), in: 0.2...1.5)
                    .controlSize(.small)
                Text(String(format: "%.1fs", model.project.animationDuration ?? 0.5))
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 30)
            }
            if model.clips.count > 1 {
                HStack {
                    Button("Use Entry on All Clips") { model.setAnimation(clip?.entry, entry: true, allClips: true) }
                    Button("Use Exit on All Clips") { model.setAnimation(clip?.exit, entry: false, allClips: true) }
                }
                .controlSize(.small)
            }
        }
        .padding(16)
        .frame(width: 380)
    }

    private func group(_ title: String, current: ClipAnimation?, entry: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 10, weight: .semibold)).kerning(0.4).foregroundStyle(.secondary)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                chip("None", "nosign", selected: current == nil) { model.setAnimation(nil, entry: entry) }
                ForEach(ClipAnimation.allCases) { kind in
                    chip(kind.label, kind.symbol, selected: current == kind) { model.setAnimation(kind, entry: entry) }
                }
            }
        }
    }

    private func chip(_ label: String, _ symbol: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: symbol).font(.system(size: 12))
                Text(label).font(.system(size: 9.5, weight: .medium)).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 38)
            .foregroundStyle(selected ? Color(nsColor: .windowBackgroundColor) : .primary)
            .background(selected ? Color.primary : Color.primary.opacity(0.07),
                        in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Crop

/// Lets the user drag out the part of the screen recording to keep.
struct CropSheet: View {
    let image: NSImage
    @State var rect: CGRect
    var onDone: (CGRect?) -> Void
    @Environment(\.dismiss) private var dismiss

    private enum Handle { case move, corner(Int), draw }
    @State private var handle: Handle?
    @State private var origin = CGRect.zero

    var body: some View {
        VStack(spacing: 14) {
            Text("Crop Screen").font(.headline)
            Text("Drag a corner to resize, drag inside to move, or drag outside to draw a new area.")
                .font(.caption).foregroundStyle(.secondary)
            Image(nsImage: image)
                .resizable()
                .frame(width: display.width, height: display.height)
                .overlay { overlay(size: display) }
                .clipShape(RoundedRectangle(cornerRadius: 4))
            HStack {
                Button("Show Everything") { rect = CGRect(x: 0, y: 0, width: 1, height: 1) }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button {
                    let full = rect.width > 0.995 && rect.height > 0.995
                    onDone(full ? nil : rect)
                    dismiss()
                } label: { BrandButtonLabel(title: "Apply Crop") }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: display.width + 40)
    }

    /// The picture's on-screen size: as large as fits in 820 × 500.
    private var display: CGSize {
        let w = max(image.size.width, 1), h = max(image.size.height, 1)
        let scale = min(820 / w, 500 / h)
        return CGSize(width: (w * scale).rounded(), height: (h * scale).rounded())
    }

    private func overlay(size: CGSize) -> some View {
        let r = CGRect(x: rect.minX * size.width, y: rect.minY * size.height,
                       width: rect.width * size.width, height: rect.height * size.height)
        let corners = [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY),
                       CGPoint(x: r.minX, y: r.maxY), CGPoint(x: r.maxX, y: r.maxY)]
        return ZStack(alignment: .topLeading) {
            Path { p in
                p.addRect(CGRect(origin: .zero, size: size))
                p.addRect(r)
            }
            .fill(.black.opacity(0.55), style: FillStyle(eoFill: true))
            Path { $0.addRect(r) }
                .stroke(.white, style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
            ForEach(0..<4, id: \.self) { i in
                RoundedRectangle(cornerRadius: 2).fill(.white)
                    .frame(width: 11, height: 11)
                    .shadow(radius: 1)
                    .position(corners[i])
            }
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let start = value.startLocation
                    if handle == nil {
                        origin = r
                        if let i = corners.firstIndex(where: { hypot($0.x - start.x, $0.y - start.y) < 16 }) { handle = .corner(i) }
                        else if r.contains(start) { handle = .move }
                        else { handle = .draw }
                    }
                    let p = CGPoint(x: min(max(value.location.x, 0), size.width), y: min(max(value.location.y, 0), size.height))
                    var out = origin
                    switch handle {
                    case .move:
                        out.origin.x = min(max(origin.minX + value.translation.width, 0), size.width - origin.width)
                        out.origin.y = min(max(origin.minY + value.translation.height, 0), size.height - origin.height)
                    case .corner(let i):
                        // The corner diagonally opposite stays put.
                        let anchor = CGPoint(x: i % 2 == 0 ? origin.maxX : origin.minX, y: i < 2 ? origin.maxY : origin.minY)
                        out = CGRect(x: min(anchor.x, p.x), y: min(anchor.y, p.y), width: abs(p.x - anchor.x), height: abs(p.y - anchor.y))
                    default:
                        out = CGRect(x: min(start.x, p.x), y: min(start.y, p.y), width: abs(p.x - start.x), height: abs(p.y - start.y))
                    }
                    guard out.width >= 40, out.height >= 40 else { return }
                    rect = CGRect(x: out.minX / size.width, y: out.minY / size.height,
                                  width: out.width / size.width, height: out.height / size.height)
                }
                .onEnded { _ in handle = nil }
        )
    }
}

// MARK: - Export sheet

struct ExportProgressView: View {
    @ObservedObject var model: EditorModel

    var body: some View {
        VStack(spacing: 16) {
            switch model.exportPhase {
            case .running(let p):
                Text("Exporting…").font(.headline)
                ProgressView(value: p).frame(width: 260)
                Text("\(Int(p * 100))%").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                Button("Cancel") { model.cancelExport() }
            case .done(let url):
                Image(systemName: "checkmark.circle.fill").font(.system(size: 38)).foregroundStyle(.green)
                Text("Export complete").font(.headline)
                Text(url.lastPathComponent).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                HStack {
                    Button("Done") { model.exportPhase = .idle }
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                        model.exportPhase = .idle
                    } label: { BrandButtonLabel(title: "Show in Finder") }
                    .buttonStyle(.plain)
                }
            case .failed(let message):
                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 34)).foregroundStyle(.orange)
                Text("Export failed").font(.headline)
                Text(message).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button("OK") { model.exportPhase = .idle }
            case .idle:
                EmptyView()
            }
        }
        .padding(28)
        .frame(width: 340)
    }
}
