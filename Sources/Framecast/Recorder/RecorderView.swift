import AVFoundation
import SwiftUI

/// The whole recorder: one slim bar with the source, camera, microphone and a record button.
struct RecorderBar: View {
    @ObservedObject var model: RecorderModel
    @ObservedObject var library: Library
    var selectArea: () -> Void
    var open: (ProjectRef) -> Void
    var close: () -> Void
    /// Reports the bar's size so its window can be resized to match.
    var resized: (CGSize) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Button(action: close) {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
                        .frame(width: 20, height: 20)
                        .background(.quaternary, in: Circle())
                }
                .buttonStyle(.plain)
                .help("Hide (reopen from the menu bar icon)")

                HStack(spacing: 2) {
                    ForEach(CaptureMode.allCases) { mode in modeButton(mode) }
                }
                .padding(3)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 9, style: .continuous))

                sourceControl
                separator
                deviceMenu(symbol: model.cameraID == nil ? "video.slash" : "video", selection: $model.cameraID,
                           options: model.cameras, none: "No Camera")
                deviceMenu(symbol: model.micID == nil ? "mic.slash" : "mic", selection: $model.micID,
                           options: model.mics, none: "No Microphone")
                Button { model.systemAudio.toggle() } label: {
                    HStack(spacing: 5) {
                        Image(systemName: model.systemAudio ? "speaker.wave.2.fill" : "speaker.slash.fill")
                        Text(model.systemAudio ? "System Audio On" : "System Audio Off")
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(model.systemAudio ? .primary : .secondary)
                    .padding(.horizontal, 10)
                    .frame(height: 24)
                    .background(Color.primary.opacity(model.systemAudio ? 0.16 : 0.06), in: Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help("Click to turn recording of the Mac's own sound on or off")

                Menu {
                    Toggle("3 Second Countdown", isOn: $model.countdownEnabled)
                    Toggle("Show Keyboard Shortcuts in Video", isOn: $model.captureKeys)
                    if !library.items.isEmpty {
                        Divider()
                        Text("Recent Recordings")
                        ForEach(library.items.prefix(6)) { ref in
                            Button("\(ref.project.name)  ·  \(timeString(ref.project.duration))") { open(ref) }
                        }
                    }
                    Divider()
                    Button("Open Recordings Folder") { NSWorkspace.shared.open(ProjectStore.root) }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Options and recent recordings")

                Button {
                    Task { await model.start() }
                } label: {
                    // Drawn by hand so it stays red with white text even when the bar isn't focused.
                    HStack(spacing: 7) {
                        Circle().fill(.white).frame(width: 9, height: 9)
                        Text("Record").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 28)
                    .background(Color(red: 0.90, green: 0.18, blue: 0.20), in: Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .opacity(model.canRecord ? 1 : 0.45)
                .disabled(!model.canRecord)
                .keyboardShortcut(.defaultAction)
                .help("Start recording (⌥⌘R from anywhere)")
            }

            if !model.screenPermission {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text("Turn on Framecast under Screen & System Audio Recording, then reopen it.")
                        .font(.caption)
                    Spacer(minLength: 8)
                    Button("Open Settings") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    Button("Reopen Framecast") { model.relaunch() }
                }
                .controlSize(.small)
            }
            if let error = model.errorMessage {
                Text(error).font(.caption).foregroundStyle(.red)
                    .frame(maxWidth: 620, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.primary.opacity(0.12)))
        .fixedSize()
        .onGeometryChange(for: CGSize.self) { $0.size } action: { resized($0) }
        .task {
            model.refreshDevices()
            await model.refreshContent()
        }
    }

    private var separator: some View {
        Rectangle().fill(.primary.opacity(0.12)).frame(width: 1, height: 20)
    }

    private func modeButton(_ mode: CaptureMode) -> some View {
        let selected = model.mode == mode
        return Button {
            model.mode = mode
            if mode == .window { Task { await model.refreshContent() } }
            if mode == .area, model.area == nil { selectArea() }
        } label: {
            Image(systemName: mode.symbol)
                .font(.system(size: 14))
                .frame(width: 34, height: 24)
                .foregroundStyle(selected ? .primary : .secondary)
                .background(selected ? Color.primary.opacity(0.2) : .clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(mode.label)
    }

    private func short(_ text: String, _ limit: Int = 22) -> String {
        text.count > limit ? String(text.prefix(limit - 1)) + "…" : text
    }

    @ViewBuilder private var sourceControl: some View {
        switch model.mode {
        case .display:
            pickerMenu(title: short(model.displays.first(where: { $0.id == model.displayID })?.name ?? "Full Screen", 26)) {
                ForEach(model.displays) { d in choice(d.name, selected: d.id == model.displayID) { model.displayID = d.id } }
            }
        case .window:
            pickerMenu(title: short(model.windows.first(where: { $0.id == model.windowID })?.name ?? "Choose Window", 26)) {
                if model.windows.isEmpty { Text("No windows found") }
                ForEach(model.windows) { w in choice(short(w.name, 60), selected: w.id == model.windowID) { model.windowID = w.id } }
                Divider()
                Button("Refresh List") { Task { await model.refreshContent() } }
            }
        case .area:
            Button(model.area.map { "\(Int($0.rect.width)) × \(Int($0.rect.height))" } ?? "Select Area") { selectArea() }
                .help("Drag out the part of the screen to record")
        }
    }

    private func pickerMenu<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        Menu(content: content) { Text(title) }
            .menuStyle(.borderlessButton)
            .fixedSize()
    }

    private func choice(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            if selected { Label(title, systemImage: "checkmark") } else { Text(title) }
        }
    }

    private func deviceMenu(symbol: String, selection: Binding<String?>, options: [DeviceOption], none: String) -> some View {
        let current = options.first(where: { $0.id == selection.wrappedValue })?.name ?? none
        return Menu {
            ForEach(options) { option in
                choice(option.name, selected: option.id == selection.wrappedValue) { selection.wrappedValue = option.id }
            }
            Divider()
            choice(none, selected: selection.wrappedValue == nil) { selection.wrappedValue = nil }
        } label: {
            Label(short(current), systemImage: symbol)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(current)
    }
}

/// Recordings saved on disk.
@MainActor
final class Library: ObservableObject {
    @Published var items: [ProjectRef] = []
    func reload() { items = ProjectStore.all() }
    func delete(_ ref: ProjectRef) {
        ProjectStore.delete(ref)
        reload()
    }
}

struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession

    final class PreviewNSView: NSView {
        let previewLayer: AVCaptureVideoPreviewLayer
        init(session: AVCaptureSession) {
            previewLayer = AVCaptureVideoPreviewLayer(session: session)
            super.init(frame: .zero)
            wantsLayer = true
            previewLayer.videoGravity = .resizeAspectFill
            layer?.addSublayer(previewLayer)
        }
        required init?(coder: NSCoder) { fatalError() }
        override func layout() {
            super.layout()
            previewLayer.frame = bounds
        }
        // Dragging the picture drags its window.
        override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
    }

    func makeNSView(context: Context) -> PreviewNSView { PreviewNSView(session: session) }
    func updateNSView(_ nsView: PreviewNSView, context: Context) {}
}

/// The floating camera preview: a rounded square, shown before and during recording.
/// It belongs to Framecast, so it is never part of the recording itself.
struct CameraBubble: View {
    let session: AVCaptureSession
    let side: CGFloat
    var setSide: (CGFloat) -> Void

    static let sizes: [(String, CGFloat)] = [("Small", 180), ("Medium", 260), ("Large", 340), ("Extra Large", 440)]

    var body: some View {
        let radius = side * 0.25
        CameraPreview(session: session)
            .scaleEffect(x: -1, y: 1)
            .frame(width: side, height: side)
            .background(Color.black)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(.white.opacity(0.3), lineWidth: 1.5))
            .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
            .padding(16)
            .contextMenu {
                ForEach(Self.sizes, id: \.1) { name, value in
                    Button { setSide(value) } label: {
                        if abs(value - side) < 1 { Label(name, systemImage: "checkmark") } else { Text(name) }
                    }
                }
            }
            .help("Drag to move, right-click to resize. This preview is not recorded.")
    }
}

// MARK: - Small floating pieces

struct CountdownView: View {
    let number: Int
    var body: some View {
        Text("\(number)")
            .font(.system(size: 84, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: 160, height: 160)
            .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 36, style: .continuous))
    }
}

/// The control strip shown while recording: timer, pause, restart, discard, stop.
struct StopPillView: View {
    @ObservedObject var model: RecorderModel

    var body: some View {
        HStack(spacing: 10) {
            if model.state == .finishing {
                ProgressView().controlSize(.small).colorScheme(.dark)
                Text("Saving…")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .fixedSize()
            } else {
                Circle()
                    .fill(model.isPaused ? Color.orange : Color.red)
                    .frame(width: 9, height: 9)
                Text(model.isPaused ? "Paused  \(timeString(model.elapsed))" : timeString(model.elapsed))
                    .font(.system(size: 13, weight: .medium).monospacedDigit())
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .fixedSize()
                Spacer(minLength: 4)
                icon(model.isPaused ? "play.fill" : "pause.fill", model.isPaused ? "Resume (⌥⌘P)" : "Pause (⌥⌘P)") { model.togglePause() }
                icon("arrow.counterclockwise", "Start over: discard this take and record again") { Task { await model.restart() } }
                icon("trash", "Discard this recording") { Task { await model.discard() } }
                Button { Task { await model.stop() } } label: {
                    HStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: 2).fill(.white).frame(width: 9, height: 9)
                        Text("Stop").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 24)
                    .background(Color(red: 0.90, green: 0.18, blue: 0.20), in: Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help("Stop and open the editor (⌥⌘R)")
            }
        }
        .padding(.horizontal, 14)
        .frame(width: 320, height: 40)
        .background(.black.opacity(0.82), in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.15)))
        .padding(6)
    }

    private func icon(_ symbol: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 24)
                .background(.white.opacity(0.14), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
