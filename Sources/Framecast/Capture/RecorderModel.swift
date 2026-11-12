import AVFoundation
import AppKit
import ScreenCaptureKit

enum CaptureMode: String, CaseIterable, Identifiable {
    case display, window, area
    var id: String { rawValue }
    var label: String {
        switch self {
        case .display: return "Full Screen"
        case .window: return "Window"
        case .area: return "Area"
        }
    }
    var symbol: String {
        switch self {
        case .display: return "display"
        case .window: return "macwindow"
        case .area: return "rectangle.dashed"
        }
    }
}

struct DisplayOption: Identifiable, Hashable {
    var id: CGDirectDisplayID
    var name: String
}

struct WindowOption: Identifiable, Hashable {
    var id: CGWindowID
    var name: String
}

struct DeviceOption: Identifiable, Hashable {
    var id: String
    var name: String
}

enum RecorderState: Equatable {
    case idle
    case countdown(Int)
    case recording
    case finishing
}

@MainActor
final class RecorderModel: ObservableObject {
    @Published var mode: CaptureMode = .display
    @Published var displays: [DisplayOption] = []
    @Published var windows: [WindowOption] = []
    @Published var displayID: CGDirectDisplayID?
    @Published var windowID: CGWindowID?
    @Published var area: AreaSelection?

    @Published var cameras: [DeviceOption] = []
    @Published var mics: [DeviceOption] = []
    @Published var cameraID: String? {
        didSet {
            guard cameraID != oldValue else { return }
            // Only remember a choice once the device list is known, so launch can't wipe it.
            if devicesLoaded { UserDefaults.standard.set(cameraID ?? "none", forKey: "camera") }
            applyCamera()
        }
    }
    private var devicesLoaded = false
    @Published var micID: String? { didSet { UserDefaults.standard.set(micID ?? "none", forKey: "mic") } }
    @Published var systemAudio = true
    @Published var countdownEnabled = true
    /// Show keyboard shortcuts in the video. Needs macOS's Input Monitoring permission.
    @Published var captureKeys = UserDefaults.standard.bool(forKey: "captureKeys") {
        didSet {
            UserDefaults.standard.set(captureKeys, forKey: "captureKeys")
            if captureKeys, !KeyTracker.hasAccess {
                KeyTracker.requestAccess()
                errorMessage = "To show keyboard shortcuts, allow Framecast under System Settings › Privacy & Security › Input Monitoring, then reopen it."
            }
        }
    }

    @Published var state: RecorderState = .idle
    @Published var elapsed: TimeInterval = 0
    @Published var isPaused = false
    @Published var errorMessage: String?
    @Published var screenPermission = true

    let camera = CameraRecorder()
    var onFinished: ((ProjectRef) -> Void)?

    private var screen: ScreenRecorder?
    private let clicks = ClickTracker()
    private let keys = KeyTracker()
    private var clock = PauseClock()
    /// Recorded time banked before the current un-paused stretch began.
    private var elapsedBase: TimeInterval = 0
    private var folder: URL?
    private var projectName = ""
    private var startedAt: Date?
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []

    init() {
        let nc = NotificationCenter.default
        for name in [AVCaptureDevice.wasConnectedNotification, AVCaptureDevice.wasDisconnectedNotification] {
            observers.append(nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.refreshDevices() }
            })
        }
    }

    // MARK: Devices

    func refreshDevices() {
        let cams = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera],
            mediaType: .video, position: .unspecified).devices
        let microphones = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone], mediaType: .audio, position: .unspecified).devices
        cameras = cams.map { DeviceOption(id: $0.uniqueID, name: $0.localizedName) }
        mics = microphones.map { DeviceOption(id: $0.uniqueID, name: $0.localizedName) }

        let defaults = UserDefaults.standard
        if cameraID == nil || !cameras.contains(where: { $0.id == cameraID }) {
            let saved = defaults.string(forKey: "camera")
            if saved == "none" { cameraID = nil }
            else { cameraID = cameras.first(where: { $0.id == saved })?.id ?? cameras.first?.id }
        }
        devicesLoaded = true
        if micID == nil || !mics.contains(where: { $0.id == micID }) {
            let saved = defaults.string(forKey: "mic")
            if saved == "none" { micID = nil }
            else {
                micID = mics.first(where: { $0.id == saved })?.id
                    ?? mics.first(where: { $0.id == AVCaptureDevice.default(for: .audio)?.uniqueID })?.id
                    ?? mics.first?.id
            }
        }
    }

    private var previewActive = false

    /// The camera only runs while the recorder is on screen or a recording is in progress.
    func setPreview(active: Bool) {
        previewActive = active
        applyCamera()
    }

    private func applyCamera() {
        guard previewActive || state != .idle, let cameraID, let device = AVCaptureDevice(uniqueID: cameraID) else {
            camera.setCamera(nil)
            return
        }
        Task {
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            if granted { camera.setCamera(device) }
            else { errorMessage = "Camera access is off. Turn it on in System Settings › Privacy & Security › Camera." }
        }
    }

    // MARK: Screen content

    private var askedForScreenAccess = false

    func refreshContent() async {
        // macOS only tells a running app about a new grant after it restarts, so check
        // first and ask at most once per launch instead of prompting on every refresh.
        guard CGPreflightScreenCaptureAccess() else {
            if !askedForScreenAccess {
                askedForScreenAccess = true
                CGRequestScreenCaptureAccess()
            }
            screenPermission = false
            return
        }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            screenPermission = true
            let screens = NSScreen.screens
            displays = content.displays.enumerated().map { index, d in
                let name = screens.first(where: { $0.displayID == d.displayID })?.localizedName ?? "Display \(index + 1)"
                return DisplayOption(id: d.displayID, name: "\(name)  ·  \(d.width) × \(d.height)")
            }
            let pid = ProcessInfo.processInfo.processIdentifier
            windows = content.windows.compactMap { w in
                guard w.windowLayer == 0, w.frame.width >= 120, w.frame.height >= 120,
                      let app = w.owningApplication, app.processID != pid,
                      let title = w.title, !title.isEmpty else { return nil }
                return WindowOption(id: w.windowID, name: "\(app.applicationName) — \(title)")
            }
            if displayID == nil || !displays.contains(where: { $0.id == displayID }) {
                displayID = displays.first(where: { $0.id == CGMainDisplayID() })?.id ?? displays.first?.id
            }
            if windowID == nil || !windows.contains(where: { $0.id == windowID }) { windowID = windows.first?.id }
        } catch {
            screenPermission = false
        }
    }

    /// Starts a fresh copy of the app and quits this one, so a new permission takes effect.
    func relaunch() {
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: config) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }

    // MARK: Recording

    var canRecord: Bool {
        guard state == .idle else { return false }
        switch mode {
        case .display: return displayID != nil
        case .window: return windowID != nil
        case .area: return area != nil
        }
    }

    func start() async {
        guard state == .idle else { return }
        errorMessage = nil
        do {
            let content: SCShareableContent
            do { content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true) }
            catch { screenPermission = false; throw RecorderError.noPermission }

            let pid = ProcessInfo.processInfo.processIdentifier
            let me = content.applications.filter { $0.processID == pid }
            let filter: SCContentFilter
            var sourceRect: CGRect?
            let pointSize: CGSize
            /// The recorded region in AppKit global coordinates, for placing clicks.
            var region = CGRect.zero

            switch mode {
            case .display:
                guard let d = content.displays.first(where: { $0.displayID == displayID }) ?? content.displays.first
                else { throw RecorderError.noSource }
                filter = SCContentFilter(display: d, excludingApplications: me, exceptingWindows: [])
                pointSize = CGSize(width: d.width, height: d.height)
                region = NSScreen.screens.first(where: { $0.displayID == d.displayID })?.frame ?? .zero
            case .window:
                guard let w = content.windows.first(where: { $0.windowID == windowID }) else { throw RecorderError.noSource }
                filter = SCContentFilter(desktopIndependentWindow: w)
                pointSize = w.frame.size
                // Window frames come with a top-left origin; AppKit's is bottom-left.
                let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
                region = CGRect(x: w.frame.minX, y: primaryHeight - w.frame.maxY,
                                width: w.frame.width, height: w.frame.height)
            case .area:
                guard let area, let d = content.displays.first(where: { $0.displayID == area.displayID })
                else { throw RecorderError.noSource }
                filter = SCContentFilter(display: d, excludingApplications: me, exceptingWindows: [])
                sourceRect = area.localRect
                pointSize = area.localRect.size
                region = area.rect
            }
            let scale = max(CGFloat(filter.pointPixelScale), 1)
            let pixelSize = CGSize(width: pointSize.width * scale, height: pointSize.height * scale)

            if countdownEnabled {
                for n in stride(from: 3, through: 1, by: -1) {
                    state = .countdown(n)
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                }
            }

            let (folder, name) = try ProjectStore.newFolder()
            self.folder = folder
            self.projectName = name
            let mic = micID.flatMap { AVCaptureDevice(uniqueID: $0) }
            if mic != nil { _ = await AVCaptureDevice.requestAccess(for: .audio) }
            await camera.startRecording(mic: mic,
                                        cameraURL: folder.appendingPathComponent("camera.mov"),
                                        micURL: folder.appendingPathComponent("mic.m4a"))
            let clock = PauseClock()
            self.clock = clock
            camera.clock = clock
            let screen = ScreenRecorder()
            screen.clock = clock
            screen.onError = { [weak self] error in
                Task { @MainActor in
                    guard let self, self.state == .recording else { return }
                    self.errorMessage = "Recording stopped: \(error.localizedDescription)"
                    await self.stop()
                }
            }
            try await screen.start(filter: filter, pixelSize: pixelSize, sourceRect: sourceRect,
                                   systemAudio: systemAudio, url: folder.appendingPathComponent("screen.mov"))
            self.screen = screen
            clicks.start(region: region)
            if captureKeys { keys.start() }
            startedAt = Date()
            elapsedBase = 0
            elapsed = 0
            isPaused = false
            state = .recording
            timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self, !self.isPaused, let s = self.startedAt else { return }
                    self.elapsed = self.elapsedBase + Date().timeIntervalSince(s)
                }
            }
        } catch {
            _ = await camera.stopRecording()
            if let folder { try? FileManager.default.removeItem(at: folder) }
            folder = nil
            state = .idle
            errorMessage = error.localizedDescription
        }
    }

    /// Pauses or resumes. Nothing is captured while paused and the gap is closed up.
    func togglePause() {
        guard state == .recording else { return }
        if isPaused {
            clock.resume()
            startedAt = Date()
            isPaused = false
        } else {
            clock.pause()
            if let s = startedAt { elapsedBase += Date().timeIntervalSince(s) }
            elapsed = elapsedBase
            isPaused = true
        }
    }

    /// Stops and throws the recording away.
    func discard() async {
        guard state == .recording, let screen, let folder else { return }
        state = .finishing
        await teardown(screen)
        _ = await camera.stopRecording()
        try? FileManager.default.removeItem(at: folder)
        state = .idle
    }

    /// Throws the current take away and starts a fresh one with the same settings.
    func restart() async {
        await discard()
        await start()
    }

    private func teardown(_ screen: ScreenRecorder) async {
        timer?.invalidate()
        timer = nil
        isPaused = false
        clicks.stop()
        keys.stop()
        await screen.stop()
        self.screen = nil
        self.folder = nil
    }

    func stop() async {
        guard state == .recording, let screen, let folder else { return }
        state = .finishing
        await teardown(screen)
        let written = await camera.stopRecording()

        let asset = AVURLAsset(url: folder.appendingPathComponent("screen.mov"))
        let duration = (try? await asset.load(.duration).seconds) ?? 0
        guard let first = screen.firstPTS, duration > 0.2 else {
            try? FileManager.default.removeItem(at: folder)
            state = .idle
            errorMessage = "The recording was empty, so nothing was saved."
            return
        }
        var project = Project(name: projectName)
        project.duration = duration
        project.screenColor = ColorMode.legacy ? nil : "sRGB"
        // New recordings start on a macOS wallpaper (a saved preset, applied later, still wins).
        if let paper = MacWallpaper.all.first {
            project.background.mode = .image
            project.background.imagePath = paper.path
        }
        project.trimEnd = duration
        if written.camera, let pts = camera.firstVideoPTS {
            project.cameraFile = "camera.mov"
            project.cameraOffset = (pts - first).seconds
        }
        if written.mic, let pts = camera.firstAudioPTS {
            project.micFile = "mic.m4a"
            project.micOffset = (pts - first).seconds
        }
        project.clicks = clicks.events(relativeTo: first.seconds, duration: duration, clock: clock)
        let strokes = keys.events(relativeTo: first.seconds, duration: duration, clock: clock)
        if !strokes.isEmpty { project.keystrokes = strokes }
        PresetStore.shared.defaultPreset?.apply(to: &project)
        let ref = ProjectRef(project: project, folder: folder)
        ProjectStore.save(ref)
        state = .idle
        onFinished?(ref)
    }
}
