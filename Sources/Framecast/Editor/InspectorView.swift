import SwiftUI

private enum InspectorTab: String, CaseIterable, Identifiable {
    case background, screen, camera, overlays, audio, captions
    var id: String { rawValue }
    var label: String { self == .overlays ? "Text & Marks" : rawValue.capitalized }
    var symbol: String {
        switch self {
        case .background: return "photo"
        case .screen: return "macwindow"
        case .camera: return "person.crop.circle"
        case .overlays: return "photo.on.rectangle.angled"
        case .audio: return "waveform"
        case .captions: return "captions.bubble"
        }
    }
}

struct InspectorView: View {
    @ObservedObject var model: EditorModel
    @State private var tab: InspectorTab = .background
    @State private var cropTarget: CropTarget?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 2) {
                ForEach(InspectorTab.allCases) { item in
                    Button { tab = item } label: {
                        VStack(spacing: 4) {
                            // Purple marks the selected icon; the label stays plain text.
                            Image(systemName: item.symbol).font(.system(size: 15))
                                .foregroundStyle(tab == item ? Color.brand : .secondary)
                            Text(item.label).font(.system(size: 10, weight: .medium))
                                .lineLimit(1).fixedSize()
                                .foregroundStyle(tab == item ? .primary : .secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(tab == item ? Color.primary.opacity(0.09) : .clear,
                                    in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    switch tab {
                    case .background: backgroundTab
                    case .screen: screenTab
                    case .camera: cameraTab
                    case .overlays: overlaysTab
                    case .audio: audioTab
                    case .captions: captionsTab
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(.background)
        .task {
            // Test hook: `FC_TEST=crop` opens the crop sheet by itself shortly after launch.
            if ProcessInfo.processInfo.environment["FC_TEST"] == "audio" {
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                model.selectedAudio = model.project.audioClips?.first?.id
                return
            }
            guard ProcessInfo.processInfo.environment["FC_TEST"] == "crop" else { return }
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            tab = .screen
            if let image = await model.screenFrame() { cropTarget = CropTarget(image: image) }
        }
        // One sheet for the whole inspector, with an explicit size (an unsized sheet opens
        // at 0×0: invisible, but still blocking every click).
        .sheet(item: $cropTarget) { target in
            CropSheet(image: target.image, rect: model.project.screen.crop ?? CGRect(x: 0, y: 0, width: 1, height: 1)) { rect in
                model.checkpoint()
                model.project.screen.crop = rect
            }
        }
        .onChange(of: model.selectedOverlay) { _, id in if id != nil { tab = .overlays } }
        .onChange(of: model.selectedAudio) { _, id in if id != nil { tab = .audio } }
        .onChange(of: model.selectedCamera) { _, id in if id != nil { tab = .camera } }
        .onChange(of: model.selectedZoom) { _, id in if id != nil { tab = .screen } }
    }

    // MARK: Background

    private var backgroundTab: some View {
        Group {
            Section("Canvas") {
                Picker("", selection: $model.project.aspect) {
                    ForEach(CanvasAspect.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden()
                .disabled(model.project.background.mode == .none)
                if model.project.background.mode == .none {
                    Text("With no background the video is exactly your recording, edge to edge, so its shape follows the recording.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            Section("Wallpaper") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                    Button { model.project.background.mode = .none } label: {
                        let selected = model.project.background.mode == .none
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color.primary.opacity(0.06))
                            .aspectRatio(1.3, contentMode: .fill)
                            .overlay {
                                VStack(spacing: 2) {
                                    Image(systemName: "rectangle.slash").font(.system(size: 13))
                                        .foregroundStyle(selected ? Color.brand : .secondary)
                                    Text("None").font(.system(size: 9, weight: .medium))
                                        .foregroundStyle(selected ? .primary : .secondary)
                                }
                            }
                            .overlay {
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .strokeBorder(selected ? Color.brand : Color.primary.opacity(0.1), lineWidth: selected ? 2 : 1)
                            }
                    }
                    .buttonStyle(.plain)
                    .help("No background: just the recording, with no padding")
                    ForEach(MacWallpaper.all) { paper in
                        let selected = model.project.background.mode == .image && model.project.background.imagePath == paper.path
                        Button {
                            model.project.background.imagePath = paper.path
                            model.project.background.mode = .image
                        } label: {
                            Color.primary.opacity(0.06)
                                .aspectRatio(1.3, contentMode: .fill)
                                .overlay {
                                    if let image = MacWallpaper.thumbnail(paper.path) {
                                        Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                                    }
                                }
                                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .strokeBorder(selected ? Color.brand : Color.primary.opacity(0.1), lineWidth: selected ? 2 : 1)
                                }
                        }
                        .buttonStyle(.plain)
                        .help(paper.name)
                    }
                }
                if model.project.background.mode == .image || model.project.background.mode == .preset {
                    SliderRow(title: "Blur", value: Binding(get: { model.project.background.blur ?? 0 },
                                                             set: { model.project.background.blur = $0 }), range: 0...1)
                }
                Text("These are the wallpapers on this Mac. To get more, download them in System Settings › Wallpaper and reopen Framecast.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Section("Colours") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 9), spacing: 8) {
                    ForEach(MacColors.all, id: \.name) { item in
                        let value = RGBA(hex: item.hex)
                        let selected = model.project.background.mode == .color && model.project.background.color == value
                        Button {
                            model.project.background.color = value
                            model.project.background.mode = .color
                        } label: {
                            Circle().fill(Color(cgColor: value.cgColor))
                                .aspectRatio(1, contentMode: .fit)
                                .overlay { Circle().strokeBorder(selected ? Color.brand : Color.primary.opacity(0.18), lineWidth: selected ? 2.5 : 1) }
                        }
                        .buttonStyle(.plain)
                        .help(item.name)
                    }
                }
            }
            Section("Custom") {
                HStack {
                    ColorPicker("Other colour", selection: Binding(
                        get: { Color(cgColor: model.project.background.color.cgColor) },
                        set: { color in
                            if let c = NSColor(color).usingColorSpace(.sRGB) {
                                model.project.background.color = RGBA(r: c.redComponent, g: c.greenComponent, b: c.blueComponent)
                                model.project.background.mode = .color
                            }
                        }), supportsOpacity: false)
                    if model.project.background.mode == .color {
                        Image(systemName: "checkmark").foregroundStyle(Color.brand).font(.caption.bold())
                    }
                }
                HStack {
                    Button("Choose Image…") { model.chooseBackgroundImage() }
                    if model.project.background.mode == .image {
                        Image(systemName: "checkmark").foregroundStyle(Color.brand).font(.caption.bold())
                    }
                }
            }
        }
    }

    // MARK: Screen

    private var screenTab: some View {
        Group {
            Section("Screen recording") {
                SliderRow(title: "Padding", value: $model.project.screen.padding, range: 0...0.2)
                SliderRow(title: "Corners", value: $model.project.screen.cornerRadius, range: 0...60)
                SliderRow(title: "Shadow", value: $model.project.screen.shadow, range: 0...1)
                SliderRow(title: "Outline", value: Binding(get: { model.project.screen.border ?? 0 },
                                                            set: { model.project.screen.border = $0 }), range: 0...1)
            }
            Section("Crop") {
                HStack {
                    Button(model.project.screen.crop == nil ? "Crop Screen…" : "Edit Crop…") {
                        Task {
                            if let image = await model.screenFrame() { cropTarget = CropTarget(image: image) }
                        }
                    }
                    if model.project.screen.crop != nil {
                        Button("Remove") {
                            model.checkpoint()
                            model.project.screen.crop = nil
                        }
                    }
                }
                Text(model.project.screen.crop == nil ? "Show only part of what you recorded."
                     : "Only the selected part of the screen is shown.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Zoom") {
                let count = model.project.clicks?.count ?? 0
                Toggle("Zoom in on clicks automatically", isOn: $model.project.zoomStyle.enabled)
                    .disabled(count == 0)
                if count == 0 {
                    Text("No clicks were captured in this recording. You can still add zooms by hand.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                } else {
                    SliderRow(title: "Auto level", value: $model.project.zoomStyle.scale, range: 1.2...3)
                        .disabled(!model.project.zoomStyle.enabled)
                }
                Button { model.addZoom() } label: { Label("Add Zoom at Playhead", systemImage: "plus.magnifyingglass") }
            }
            Section("Keyboard shortcuts") {
                let count = model.project.keystrokes?.count ?? 0
                if count == 0 {
                    Text("None were captured. To show shortcuts like ⌘ C in future recordings, turn on \"Show Keyboard Shortcuts in Video\" in the recorder's ⋯ menu before recording.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                } else {
                    Toggle("Show on video", isOn: Binding(
                        get: { model.project.showKeystrokes ?? true },
                        set: { model.project.showKeystrokes = $0 }))
                    Text("\(count) shortcut\(count == 1 ? "" : "s") captured. Ordinary typing is never recorded.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            if let zoom = model.selectedManualZoom {
                Section("Selected zoom") {
                    SliderRow(title: "Level", value: zoom.scale, range: 1.2...4)
                    Text("Click where the zoom should point:").font(.caption).foregroundStyle(.secondary)
                    FocusPad(image: model.thumbnail(at: zoom.wrappedValue.start), x: zoom.x, y: zoom.y)
                    Text("Drag it on the timeline to move it, or drag its ends to change how long it lasts.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Button("Delete Zoom", role: .destructive) { model.deleteSelection() }
                }
            } else if let id = model.selectedZoom, id.hasPrefix("auto") {
                Section("Selected zoom") {
                    Text("This zoom was made automatically from your clicks.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Remove This Zoom", role: .destructive) { model.deleteSelection() }
                }
            }
        }
    }

    // MARK: Camera

    @ViewBuilder private var cameraTab: some View {
        if !model.hasCamera {
            EmptyNote(symbol: "video.slash", text: "This recording has no camera.\nPick a camera before you record to add your face.")
        } else {
            Section("Camera") {
                Toggle("Show camera", isOn: $model.project.camera.visible)
            }
            Group {
                Section("Shape") {
                    Picker("", selection: $model.project.camera.shape) {
                        ForEach([CameraShape.square, .circle, .rectangle]) { shape in
                            Label(shape.label, systemImage: shape.symbol).tag(shape)
                        }
                    }
                    .pickerStyle(.segmented).labelsHidden()
                    SliderRow(title: "Roundness", value: $model.project.camera.cornerRadius, range: 0...1)
                        .disabled(model.project.camera.shape == .circle)
                    SliderRow(title: "Size", value: $model.project.camera.size, range: 0.1...0.6)
                }
                Section("Position") {
                    HStack(alignment: .top, spacing: 14) {
                        VStack(spacing: 5) {
                            ForEach(0..<3, id: \.self) { row in
                                HStack(spacing: 5) {
                                    ForEach(0..<3, id: \.self) { col in positionButton(col: col, row: row) }
                                }
                            }
                        }
                        Text("Pick a spot, or drag the camera directly on the preview.")
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Section("Options") {
                    Toggle("Mirror", isOn: $model.project.camera.mirrored)
                    SliderRow(title: "Shadow", value: $model.project.camera.shadowStrength, range: 0...1)
                }
                Section("Layout changes") {
                    Text("Move, enlarge or hide the camera for just part of the video. Sections appear on the timeline's camera track.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Button { model.addCameraSection() } label: {
                        Label("Add Section at Playhead", systemImage: "person.crop.rectangle")
                    }
                    if let section = model.selectedCameraSection {
                        Picker("", selection: section.mode) {
                            ForEach(CameraSectionMode.allCases) { Text($0.label).tag($0) }
                        }
                        .pickerStyle(.segmented).labelsHidden()
                        if section.wrappedValue.mode == .position {
                            VStack(spacing: 5) {
                                ForEach(0..<3, id: \.self) { row in
                                    HStack(spacing: 5) {
                                        ForEach(0..<3, id: \.self) { col in
                                            let anchor = CameraAnchor(col: col, row: row)
                                            Button { section.wrappedValue.anchor = anchor } label: {
                                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                                    .fill(section.wrappedValue.anchor == anchor ? Color.teal : Color.primary.opacity(0.08))
                                                    .frame(width: 30, height: 22)
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                            }
                        }
                        Button("Delete Section", role: .destructive) { model.deleteSelection() }
                    } else if !(model.project.cameraSections ?? []).isEmpty {
                        Text("Click a section on the timeline to edit it.")
                            .font(.caption).foregroundStyle(.tertiary)
                    }
                }
            }
            .disabled(!model.project.camera.visible)
            .opacity(model.project.camera.visible ? 1 : 0.45)
        }
    }

    private func positionButton(col: Int, row: Int) -> some View {
        let anchor = CameraAnchor(col: col, row: row)
        let selected = model.project.camera.customCenter == nil && model.project.camera.anchor == anchor
        return Button {
            model.project.camera.customCenter = nil
            model.project.camera.anchor = anchor
        } label: {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(selected ? Color.brand : Color.primary.opacity(0.08))
                .frame(width: 30, height: 22)
        }
        .buttonStyle(.plain)
    }

    // MARK: Text and images

    private static func overlayIcon(_ o: Overlay) -> String {
        switch o.kind {
        case .text: return "textformat"
        case .image: return "photo"
        case .blur: return "eye.slash"
        case .highlight: return o.spotlight == true ? "flashlight.on.fill" : "highlighter"
        }
    }

    private static func overlayName(_ o: Overlay) -> String {
        switch o.kind {
        case .text: return o.text
        case .image: return "Image"
        case .blur: return "Blur"
        case .highlight: return o.spotlight == true ? "Spotlight" : "Highlight"
        }
    }

    private var overlaysTab: some View {
        Group {
            Section("Add") {
                HStack {
                    Button { model.addText() } label: { Label("Text", systemImage: "textformat") }
                    Button { model.addImage() } label: { Label("Image…", systemImage: "photo") }
                }
                HStack {
                    Button { model.addRegion(.blur) } label: { Label("Blur", systemImage: "eye.slash") }
                    Button { model.addRegion(.highlight) } label: { Label("Highlight", systemImage: "highlighter") }
                    Button { model.addRegion(.highlight, spotlight: true) } label: { Label("Spotlight", systemImage: "flashlight.on.fill") }
                }
                Text("Added at the playhead. Each one appears on the timeline, where you can move it and set how long it shows.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            let overlays = model.project.overlays ?? []
            if !overlays.isEmpty {
                Section("On this video") {
                    ForEach(overlays) { overlay in
                        Button {
                            model.clearSelection()
                            model.selectedOverlay = overlay.id
                            model.seek(overlay.start + 0.05)
                        } label: {
                            HStack {
                                Image(systemName: Self.overlayIcon(overlay))
                                    .foregroundStyle(overlay.kind == .text ? .orange : overlay.kind == .image ? .indigo
                                                     : overlay.kind == .blur ? .cyan : .yellow)
                                Text(Self.overlayName(overlay)).lineLimit(1)
                                Spacer()
                                Text(timeString(overlay.start)).foregroundStyle(.secondary).monospacedDigit()
                            }
                            .font(.callout)
                            .padding(.vertical, 3).padding(.horizontal, 6)
                            .background(model.selectedOverlay == overlay.id ? Color.primary.opacity(0.1) : .clear,
                                        in: RoundedRectangle(cornerRadius: 5))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if let overlay = model.selectedOverlayBinding, overlay.wrappedValue.kind.isRegion {
                let isBlur = overlay.wrappedValue.kind == .blur
                let spot = overlay.wrappedValue.spotlight == true
                Section(isBlur ? "Blur" : "Highlight") {
                    if !isBlur {
                        Picker("Style", selection: Binding(get: { spot }, set: { overlay.wrappedValue.spotlight = $0 })) {
                            Text("Marker").tag(false)
                            Text("Spotlight").tag(true)
                        }
                        .pickerStyle(.segmented)
                        if !spot {
                            ColorPicker("Colour", selection: colorBinding(
                                get: { overlay.wrappedValue.color }, set: { overlay.wrappedValue.color = $0 }), supportsOpacity: false)
                        }
                    }
                    SliderRow(title: "Width", value: Binding(get: { overlay.wrappedValue.boxWidth }, set: { overlay.wrappedValue.w = $0 }), range: 0.02...1)
                    SliderRow(title: "Height", value: Binding(get: { overlay.wrappedValue.boxHeight }, set: { overlay.wrappedValue.h = $0 }), range: 0.02...1)
                    SliderRow(title: isBlur ? "Blur" : spot ? "Dimming" : "Strength",
                              value: Binding(get: { overlay.wrappedValue.amount }, set: { overlay.wrappedValue.strength = $0 }), range: 0...1)
                    SliderRow(title: "Fade", value: overlay.fade, range: 0...1.5)
                    Text(isBlur ? "Hides what is under the box. Drag the dashed box on the preview to move it and its corner dot to resize it."
                         : spot ? "Darkens everything except the box. Drag the dashed box on the preview to move it and its corner dot to resize it."
                         : "Tints the box like a marker pen. Drag the dashed box on the preview to move it and its corner dot to resize it.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Text("It is pinned to the recording, so it stays on the same spot when the video zooms. It does not follow things that scroll.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Section("Timing") {
                    Text(String(format: "Shows from %@ for %.1fs. Drag it on the timeline to move it, or drag its ends to change the length.",
                                timeString(overlay.wrappedValue.start), overlay.wrappedValue.end - overlay.wrappedValue.start))
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Button("Delete", role: .destructive) { model.deleteSelection() }
                }
            } else if let overlay = model.selectedOverlayBinding {
                let isText = overlay.wrappedValue.kind == .text
                Section(isText ? "Text" : "Image") {
                    if isText {
                        TextField("Text", text: overlay.text, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(1...4)
                        SliderRow(title: "Size", value: overlay.size, range: 0.3...4)
                        ColorPicker("Colour", selection: colorBinding(
                            get: { overlay.wrappedValue.color }, set: { overlay.wrappedValue.color = $0 }), supportsOpacity: false)
                        Toggle("Box behind text", isOn: Binding(
                            get: { overlay.wrappedValue.boxColor != nil },
                            set: { overlay.wrappedValue.boxColor = $0 ? RGBA(r: 0, g: 0, b: 0, a: 0.6) : nil }))
                        if overlay.wrappedValue.boxColor != nil {
                            ColorPicker("Box colour", selection: colorBinding(
                                get: { overlay.wrappedValue.boxColor ?? RGBA(r: 0, g: 0, b: 0, a: 0.6) },
                                set: { overlay.wrappedValue.boxColor = $0 }), supportsOpacity: true)
                        }
                        HStack {
                            Button("Upload Font…") { if let path = model.pickFont() { overlay.wrappedValue.fontPath = path } }
                            if overlay.wrappedValue.fontPath != nil {
                                Button("Use System") { overlay.wrappedValue.fontPath = nil }
                            }
                        }
                    } else {
                        SliderRow(title: "Size", value: overlay.size, range: 0.05...1)
                        SliderRow(title: "Corners", value: overlay.cornerRadius, range: 0...0.5)
                    }
                    SliderRow(title: "Opacity", value: overlay.opacity, range: 0.1...1)
                    SliderRow(title: "Shadow", value: overlay.shadow, range: 0...1)
                    SliderRow(title: "Fade", value: overlay.fade, range: 0...1.5)
                }
                Section("Position") {
                    HStack(alignment: .top, spacing: 14) {
                        VStack(spacing: 5) {
                            ForEach(0..<3, id: \.self) { row in
                                HStack(spacing: 5) {
                                    ForEach(0..<3, id: \.self) { col in
                                        let px = [0.18, 0.5, 0.82][col], py = [0.15, 0.5, 0.85][row]
                                        let on = abs(overlay.wrappedValue.x - px) < 0.01 && abs(overlay.wrappedValue.y - py) < 0.01
                                        Button {
                                            overlay.wrappedValue.x = px
                                            overlay.wrappedValue.y = py
                                        } label: {
                                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                                .fill(on ? Color.brand : Color.primary.opacity(0.08))
                                                .frame(width: 30, height: 22)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                        Text("Pick a spot, or drag the round handle on the preview.")
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
                Section("Timing") {
                    Text(String(format: "Shows from %@ for %.1fs. Drag it on the timeline to move it, or drag its ends to change the length.",
                                timeString(overlay.wrappedValue.start), overlay.wrappedValue.end - overlay.wrappedValue.start))
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Button("Delete", role: .destructive) { model.deleteSelection() }
                }
            }
        }
    }

    // MARK: Audio

    private var audioTab: some View {
        Group {
            Section("Recorded audio") {
                if model.hasMic {
                    SliderRow(title: "Microphone", value: $model.project.audio.micVolume, range: 0...1.5)
                    HStack(spacing: 8) {
                        Toggle("Clean up voice", isOn: Binding(
                            get: { model.project.audio.voiceCleanup == true },
                            set: { model.setVoiceCleanup($0) }))
                            .disabled(model.isCleaningVoice)
                        if model.isCleaningVoice {
                            ProgressView().controlSize(.small)
                            Text("Cleaning…").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Text("Removes background noise and hum from your microphone and evens out the volume.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                if model.hasSystemAudio { SliderRow(title: "System", value: $model.project.audio.systemVolume, range: 0...1.5) }
                if !model.hasMic && !model.hasSystemAudio {
                    Text("Nothing was recorded with this video.").font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Music & sound effects") {
                Button { model.addAudio() } label: { Label("Add Audio at Playhead…", systemImage: "music.note") }
                ForEach(model.project.audioClips ?? []) { clip in
                    Button {
                        model.clearSelection()
                        model.selectedAudio = clip.id
                    } label: {
                        HStack {
                            Image(systemName: "music.note").foregroundStyle(.green)
                            Text(clip.name).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Text("at \(timeString(clip.start))").foregroundStyle(.secondary)
                        }
                        .font(.callout)
                        .padding(.vertical, 3).padding(.horizontal, 6)
                        .background(model.selectedAudio == clip.id ? Color.primary.opacity(0.1) : .clear,
                                    in: RoundedRectangle(cornerRadius: 5))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                if let clip = model.selectedAudioBinding {
                    Text("Choose the part to use").font(.caption).foregroundStyle(.secondary)
                    WaveformTrimmer(peaks: model.waveforms[clip.wrappedValue.file] ?? [], clip: clip)
                        .frame(height: 56)
                        .onAppear { model.loadWaveform(for: clip.wrappedValue) }
                        .onChange(of: clip.wrappedValue.file) { _, _ in model.loadWaveform(for: clip.wrappedValue) }
                    HStack {
                        Button { model.toggleAudition(clip.wrappedValue) } label: {
                            Label(model.auditioning == clip.wrappedValue.id ? "Stop" : "Play This Part",
                                  systemImage: model.auditioning == clip.wrappedValue.id ? "stop.fill" : "play.fill")
                        }
                        Spacer()
                        Text("\(timeString(clip.wrappedValue.offset)) – \(timeString(clip.wrappedValue.offset + clip.wrappedValue.duration)) of \(timeString(clip.wrappedValue.fileDuration))")
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    Text("Drag the highlighted part to pick a different section, or drag its edges to make it longer or shorter.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    SliderRow(title: "Volume", value: clip.volume, range: 0...1.5)
                    SliderRow(title: "Fade in", value: clip.fadeIn, range: 0...min(5, max(clip.wrappedValue.duration / 2, 0.1)))
                    SliderRow(title: "Fade out", value: clip.fadeOut, range: 0...min(5, max(clip.wrappedValue.duration / 2, 0.1)))
                    Text(String(format: "Starts at %@, plays for %.1fs. Fade in %.1fs, fade out %.1fs. Drag it on the timeline to move it, or drag its ends to trim.",
                                timeString(clip.wrappedValue.start), clip.wrappedValue.duration,
                                clip.wrappedValue.fadeIn, clip.wrappedValue.fadeOut))
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button("Add Again") { model.duplicateAudio() }
                            .help("Places another copy of this sound on the timeline")
                        Spacer()
                        Button("Remove Audio", role: .destructive) { model.deleteSelection() }
                    }
                } else if !(model.project.audioClips ?? []).isEmpty {
                    Text("Select a clip to set its volume and fades.").font(.caption).foregroundStyle(.tertiary)
                }
            }
            Section("Voiceover") {
                Button { model.toggleVoiceover() } label: {
                    Label(model.isRecordingVoice ? "Stop Recording" : "Record Voiceover",
                          systemImage: model.isRecordingVoice ? "stop.circle.fill" : "mic.circle.fill")
                }
                .tint(model.isRecordingVoice ? .red : nil)
                Text(model.isRecordingVoice ? "Recording — the video plays silently while you talk."
                     : "Starts at the playhead and records while the video plays.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if let error = model.voiceError { Text(error).font(.caption).foregroundStyle(.red) }
                ForEach(Array(model.project.audio.voiceClips.enumerated()), id: \.element.id) { index, clip in
                    HStack {
                        Image(systemName: "waveform").foregroundStyle(.secondary)
                        Text("Take \(index + 1)")
                        Text("at \(timeString(clip.start))").foregroundStyle(.secondary)
                        Spacer()
                        Button { model.removeVoiceClip(clip) } label: { Image(systemName: "trash") }
                            .buttonStyle(.plain).foregroundStyle(.secondary)
                    }
                    .font(.callout)
                }
                if !model.project.audio.voiceClips.isEmpty {
                    SliderRow(title: "Volume", value: $model.project.audio.voiceVolume, range: 0...1.5)
                }
            }
        }
    }

    // MARK: Captions

    private var captionsTab: some View {
        Group {
            Section("Captions") {
                Button { model.generateCaptions() } label: {
                    HStack(spacing: 6) {
                        if model.isGeneratingCaptions { ProgressView().controlSize(.small) }
                        Text(model.isGeneratingCaptions ? "Listening…"
                             : model.project.captions.isEmpty ? "Generate Captions" : "Regenerate Captions")
                    }
                }
                .disabled(model.isGeneratingCaptions)
                Text("Transcribed from your voice, on this Mac.")
                    .font(.caption).foregroundStyle(.secondary)
                if let error = model.captionError {
                    Text(error).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                }
            }
            if !model.project.captions.isEmpty {
                Section("Appearance") {
                    Toggle("Show on video", isOn: $model.project.captionStyle.visible)
                    SliderRow(title: "Size", value: $model.project.captionStyle.scale, range: 0.6...1.8)
                    HStack {
                        Text("Font").font(.callout).frame(width: 78, alignment: .leading)
                        Text(model.captionFontName).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                        Spacer()
                    }
                    HStack {
                        Button("Upload Font…") { model.chooseCaptionFont() }
                        if model.project.captionStyle.fontPath != nil {
                            Button("Use System") { model.project.captionStyle.fontPath = nil }
                        }
                    }
                    ColorPicker("Text colour", selection: colorBinding(
                        get: { model.project.captionStyle.textColor ?? RGBA(r: 1, g: 1, b: 1) },
                        set: { model.project.captionStyle.textColor = $0 }), supportsOpacity: false)
                    ColorPicker("Box colour", selection: colorBinding(
                        get: { model.project.captionStyle.boxColor ?? RGBA(r: 0, g: 0, b: 0, a: 0.62) },
                        set: { model.project.captionStyle.boxColor = $0 }), supportsOpacity: true)
                    Text("Lower the box colour's opacity to zero for text with no box.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Section("Text") {
                    ForEach($model.project.captions) { $caption in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Button(timeString(caption.start)) { model.seek(model.timeMap.output(caption.start) + 0.01) }
                                .buttonStyle(.plain)
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 34, alignment: .leading)
                            TextField("", text: $caption.text, axis: .vertical)
                                .textFieldStyle(.plain)
                                .font(.callout)
                            Button { model.project.captions.removeAll { $0.id == caption.id } } label: {
                                Image(systemName: "xmark")
                            }
                            .buttonStyle(.plain).font(.caption2).foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 2)
                    }
                    Button("Export .srt…") { model.exportSRT() }
                        .padding(.top, 4)
                }
            }
        }
    }
}

/// A picture of an audio file's loudness with the used part highlighted. Drag the part
/// to choose a different section, or drag its edges to change how much is used.
private struct WaveformTrimmer: View {
    let peaks: [Float]
    @Binding var clip: AudioClip

    private enum Grab { case start, end, move }
    @State private var grab: Grab?
    @State private var origin: AudioClip?

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let total = max(clip.fileDuration, 0.01)
            let x0 = CGFloat(clip.offset / total) * w
            let x1 = CGFloat(min(clip.offset + clip.duration, total) / total) * w
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(0.06))
                Canvas { context, size in
                    guard !peaks.isEmpty else { return }
                    let step = size.width / CGFloat(peaks.count)
                    for (i, peak) in peaks.enumerated() {
                        let x = CGFloat(i) * step
                        let bar = max(CGFloat(peak) * (size.height - 8), 1.5)
                        let inside = x + step / 2 >= x0 && x + step / 2 <= x1
                        context.fill(Path(CGRect(x: x, y: (size.height - bar) / 2, width: max(step - 0.6, 0.6), height: bar)),
                                     with: .color(inside ? Color.green : Color.secondary.opacity(0.4)))
                    }
                }
                if peaks.isEmpty {
                    Text("Loading…").font(.caption2).foregroundStyle(.tertiary).frame(width: w, height: h)
                }
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(Color.green, lineWidth: 2)
                    .background(Color.green.opacity(0.10), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .frame(width: max(x1 - x0, 6), height: h)
                    .offset(x: x0)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if grab == nil {
                            origin = clip
                            let x = value.startLocation.x
                            if abs(x - x0) < 8 { grab = .start }
                            else if abs(x - x1) < 8 { grab = .end }
                            else {
                                grab = .move
                                // Clicking outside the highlighted part jumps it there first.
                                if x < x0 || x > x1 {
                                    let centre = Double(x / w) * total
                                    clip.offset = min(max(centre - clip.duration / 2, 0), max(total - clip.duration, 0))
                                    origin = clip
                                }
                            }
                        }
                        guard let o = origin else { return }
                        let t = Double(min(max(value.location.x, 0), w) / w) * total
                        let dt = Double(value.translation.width / w) * total
                        switch grab {
                        case .start:
                            let end = o.offset + o.duration
                            let start = min(max(t, 0), end - 0.2)
                            clip.offset = start
                            clip.duration = end - start
                        case .end:
                            clip.duration = min(max(t - o.offset, 0.2), total - o.offset)
                        default:
                            clip.offset = min(max(o.offset + dt, 0), max(total - o.duration, 0))
                        }
                    }
                    .onEnded { _ in
                        grab = nil
                        origin = nil
                    }
            )
        }
    }
}

struct CropTarget: Identifiable {
    let id = UUID()
    let image: NSImage
}

private func colorBinding(get: @escaping () -> RGBA, set: @escaping (RGBA) -> Void) -> Binding<Color> {
    Binding(
        get: { Color(cgColor: get().cgColor) },
        set: { color in
            if let c = NSColor(color).usingColorSpace(.sRGB) {
                set(RGBA(r: c.redComponent, g: c.greenComponent, b: c.blueComponent, a: c.alphaComponent))
            }
        })
}

/// A small picture of the screen; click or drag to choose where a zoom points.
private struct FocusPad: View {
    let image: NSImage?
    @Binding var x: Double
    @Binding var y: Double

    var body: some View {
        let aspect = image.map { $0.size.width / max($0.size.height, 1) } ?? 1.6
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                if let image { Image(nsImage: image).resizable() } else { Color.gray.opacity(0.3) }
                Circle()
                    .strokeBorder(.white, lineWidth: 2)
                    .background(Circle().fill(Color.brand.opacity(0.7)))
                    .frame(width: 18, height: 18)
                    .shadow(radius: 2)
                    .position(x: x * geo.size.width, y: y * geo.size.height)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                x = min(max(value.location.x / geo.size.width, 0), 1)
                y = min(max(value.location.y / geo.size.height, 0), 1)
            })
        }
        .aspectRatio(aspect, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(.primary.opacity(0.15)))
    }
}

// MARK: - Small pieces

private struct Section<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .kerning(0.5)
                .foregroundStyle(.secondary)
            content
        }
    }
}

private struct SliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var body: some View {
        HStack(spacing: 10) {
            Text(title).font(.callout).frame(width: 78, alignment: .leading)
            Slider(value: $value, in: range).controlSize(.small)
        }
    }
}

private struct EmptyNote: View {
    let symbol: String
    let text: String
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 26)).foregroundStyle(.tertiary)
            Text(text).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }
}
