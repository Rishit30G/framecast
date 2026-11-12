import AVFoundation
import AppKit
import SwiftUI
import UniformTypeIdentifiers

extension Notification.Name {
    static let framecastLibraryChanged = Notification.Name("framecastLibraryChanged")
}

enum ExportPhase: Equatable {
    case idle
    case running(Double)
    case done(URL)
    case failed(String)
}

/// A zoom shown on the timeline: either made from clicks or placed by hand.
struct ZoomItem: Identifiable, Equatable {
    enum Kind: Equatable { case auto, manual(UUID) }
    var id: String
    var kind: Kind
    /// Source seconds.
    var start: Double
    var end: Double
}

@MainActor
final class EditorModel: ObservableObject {
    @Published var project: Project { didSet { projectChanged(from: oldValue) } }
    let folder: URL
    let player = AVPlayer()

    /// Position on the edited timeline, in seconds.
    @Published var currentTime: Double = 0
    @Published var isPlaying = false
    @Published var thumbnails: [(time: Double, image: NSImage)] = []
    @Published var loadError: String?

    @Published var selectedClip: UUID?
    @Published var selectedZoom: String?
    @Published var selectedCamera: UUID?
    @Published var selectedOverlay: UUID?
    @Published var selectedAudio: UUID?
    /// Flips briefly after the name is saved, so the field can show a tick.
    @Published var nameSaved = false
    @Published var isCleaningVoice = false
    /// Loudness outlines of audio files, keyed by file, for the trimmer.
    @Published var waveforms: [String: [Float]] = [:]
    /// Loudness of the recording's own sound (your voice, else system audio) for the timeline.
    @Published var voicePeaks: [Float] = []
    private var voicePeaksStart = 0.0
    private var voicePeaksLength = 0.0
    /// The audio clip currently being played on its own.
    @Published var auditioning: UUID?
    private var auditionPlayer: AVAudioPlayer?
    @Published var canUndo = false
    @Published var canRedo = false
    /// 1 = the whole video fits the timeline; larger values zoom in.
    @Published var timelineZoom: Double = 1

    @Published var isGeneratingCaptions = false
    @Published var captionError: String?
    @Published var isRecordingVoice = false
    @Published var voiceError: String?
    @Published var exportPhase: ExportPhase = .idle

    private var built: BuiltComposition?
    private var timeObserver: Any?
    private var keyMonitor: Any?
    private var saveTask: Task<Void, Never>?
    /// When project.json was last written by, or read into, this editor.
    private var fileStamp: Date?
    private var reloadTimer: Timer?
    /// Shown briefly after edits made outside the editor (by Claude) are picked up.
    @Published var externalNote: String?
    private var rebuildTask: Task<Void, Never>?
    private var recorder: AVAudioRecorder?
    private var voiceStart: Double = 0
    private var voiceFile = ""
    private var exporter: Exporter?
    private var undoStack: [Project] = []
    private var redoStack: [Project] = []
    weak var window: NSWindow?

    var ref: ProjectRef { ProjectRef(project: project, folder: folder) }
    var hasCamera: Bool { project.cameraFile != nil }
    var hasMic: Bool { project.micFile != nil }
    var hasSystemAudio: Bool { !(built?.systemTracks.isEmpty ?? true) }
    var clips: [Clip] { project.timeline }
    var timeMap: TimeMap { project.timeMap }
    /// Length of the edited video.
    var duration: Double { timeMap.duration }
    /// Width / height of the finished video.
    var canvasAspect: CGFloat {
        let size = project.canvasSize(shortSide: 1080)
        return size.width / max(size.height, 1)
    }

    init(ref: ProjectRef) {
        var project = ref.project
        if project.clips == nil { project.clips = project.timeline }
        self.project = project
        folder = ref.folder

        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 30), queue: .main) { [weak self] time in
            Task { @MainActor in self?.tick(time.seconds) }
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.window,
                  !(event.window?.firstResponder is NSTextView) else { return event }
            let command = event.modifierFlags.contains(.command)
            let shift = event.modifierFlags.contains(.shift)
            switch event.keyCode {
            case 49, 40: self.togglePlay()                                // Space, K
            case 51, 117: self.deleteSelection()                          // Delete
            case 1 where !command, 11 where command: self.split()         // S, ⌘B
            case 12 where !command: self.trimToPlayhead(start: true)      // Q
            case 13 where !command: self.trimToPlayhead(start: false)     // W
            case 6 where command && shift: self.redo()                    // ⇧⌘Z
            case 6 where command: self.undo()                             // ⌘Z
            case 6: self.addZoom()                                        // Z
            case 8 where !command: self.addCameraSection()                // C
            case 17 where !command: self.addText()                        // T
            case 123: self.seek(self.currentTime - (shift ? 1 : 1.0 / 30))   // ←
            case 124: self.seek(self.currentTime + (shift ? 1 : 1.0 / 30))   // →
            case 38: self.seek(self.currentTime - 2)                      // J
            case 37: self.seek(self.currentTime + 2)                      // L
            case 126: self.jumpToCut(forward: false)                      // ↑
            case 125: self.jumpToCut(forward: true)                       // ↓
            case 115: self.seek(0)                                        // Home
            case 119: self.seek(self.duration)                            // End
            case 24 where command: self.timelineZoom = min(self.timelineZoom * 1.5, 40)   // ⌘+
            case 27 where command: self.timelineZoom = max(self.timelineZoom / 1.5, 1)    // ⌘−
            case 29 where command: self.timelineZoom = 1                  // ⌘0
            case 53: self.clearSelection()                                // Esc
            default: return event
            }
            return nil
        }
        Task {
            await migrateMusic()
            await rebuild()
            watchFile()
            loadVoicePeaks()
            await loadThumbnails()
        }
    }

    private var projectFile: URL { folder.appendingPathComponent("project.json") }
    private var stampOnDisk: Date? {
        (try? FileManager.default.attributesOfItem(atPath: projectFile.path))?[.modificationDate] as? Date
    }

    private func saveNow() {
        ProjectStore.save(ref)
        fileStamp = stampOnDisk
    }

    /// Picks up edits written to the project file from outside (the Claude tools) while it is open.
    private func watchFile() {
        fileStamp = stampOnDisk
        reloadTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkFile() }
        }
    }

    private func checkFile() {
        guard let stamp = stampOnDisk, stamp != fileStamp else { return }
        fileStamp = stamp
        if ProcessInfo.processInfo.environment["FC_DEBUG"] != nil { FileHandle.standardError.write("project file changed on disk\n".data(using: .utf8)!) }
        guard var loaded = ProjectStore.load(folder: folder)?.project else { return }
        if loaded.clips == nil { loaded.clips = loaded.timeline }
        if loaded.sourceSize == nil { loaded.sourceSize = project.sourceSize }
        guard loaded != project else { return }
        saveTask?.cancel()
        checkpoint()            // so ⌘Z brings back how it was
        project = loaded
        clearSelection()
        currentTime = min(currentTime, duration)
        externalNote = "Updated by Claude — ⌘Z to undo"
        if ProcessInfo.processInfo.environment["FC_DEBUG"] != nil { FileHandle.standardError.write("reloaded: background \(project.background.presetID)\n".data(using: .utf8)!) }
        Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            externalNote = nil
        }
    }

    private var claudeRequest: String {
        "Edit my Framecast recording using the framecast-editor skill and my editing style.\nRecording folder: \(folder.path)"
    }

    /// Opens the Claude desktop app's Code tab on this recording with the request filled in.
    func openInClaude() {
        ClaudeTools.installSkill()
        saveNow()
        var link = URLComponents()
        link.scheme = "claude"
        link.host = "code"
        link.path = "/new"
        link.queryItems = [URLQueryItem(name: "folder", value: folder.path), URLQueryItem(name: "q", value: claudeRequest)]
        // "+" would be read as a space on the other side.
        link.percentEncodedQuery = link.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        guard let url = link.url, NSWorkspace.shared.urlForApplication(toOpen: url) != nil, NSWorkspace.shared.open(url) else {
            copyClaudeRequest()
            externalNote = "Claude isn't installed — request copied instead"
            return
        }
        externalNote = "Opened in Claude — press Return there to start"
        Task {
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            externalNote = nil
        }
    }

    /// Puts a ready-made request on the clipboard for pasting into Claude.
    func copyClaudeRequest() {
        ClaudeTools.installSkill()
        saveNow()
        let text = claudeRequest
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        externalNote = "Copied — paste it into Claude"
        Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            externalNote = nil
        }
    }

    func openEditingStyle() {
        guard ClaudeTools.installSkill() else { return }
        // A plain text editor, rather than whatever happens to own .md files (often Xcode).
        NSWorkspace.shared.open([ClaudeTools.styleFile], withApplicationAt: URL(fileURLWithPath: "/System/Applications/TextEdit.app"),
                                configuration: NSWorkspace.OpenConfiguration())
    }

    private func loadVoicePeaks() {
        let url: URL, start: Double
        if let mic = project.micFile { url = ref.url(mic); start = project.micOffset }
        else { url = ref.url(project.screenFile); start = 0 }
        Task.detached {
            let length = (try? await AVURLAsset(url: url).load(.duration).seconds) ?? 0
            guard length > 0 else { return }
            let peaks = await Self.peaks(of: url, buckets: min(max(Int(length * 50), 200), 12_000))
            await MainActor.run {
                self.voicePeaksStart = start
                self.voicePeaksLength = length
                self.voicePeaks = peaks
            }
        }
    }

    /// The loudest moment between two times of the raw recording, 0…1.
    func voiceLevel(from a: Double, to b: Double) -> Float {
        guard voicePeaksLength > 0, !voicePeaks.isEmpty else { return 0 }
        let n = Double(voicePeaks.count)
        let i0 = Int(((a - voicePeaksStart) / voicePeaksLength * n).rounded(.down))
        let i1 = Int(((b - voicePeaksStart) / voicePeaksLength * n).rounded(.down))
        guard i1 >= 0, i0 < voicePeaks.count else { return 0 }
        var top: Float = 0
        for i in max(i0, 0)...min(max(i1, i0, 0), voicePeaks.count - 1) { top = max(top, voicePeaks[i]) }
        return top
    }

    /// Where the recording sits inside a preview of the given size.
    func screenFrame(in size: CGSize) -> CGRect {
        var style = project.screen
        if project.background.mode == .none { style.padding = 0 }
        let source = project.sourceSize ?? size
        let crop = style.crop ?? CGRect(x: 0, y: 0, width: 1, height: 1)
        return Layout.screenRect(canvas: size, source: CGSize(width: source.width * crop.width, height: source.height * crop.height),
                                 style: style)
    }

    /// Older projects had one music file for the whole video; turn it into a timeline clip.
    private func migrateMusic() async {
        guard let path = project.audio.musicPath else { return }
        let length = (try? await AVURLAsset(url: URL(fileURLWithPath: path)).load(.duration).seconds) ?? 0
        project.audio.musicPath = nil
        guard length > 0 else { return }
        let clip = AudioClip(file: path, name: URL(fileURLWithPath: path).lastPathComponent, start: 0,
                             duration: min(length, duration), fileDuration: length, volume: project.audio.musicVolume)
        project.audioClips = (project.audioClips ?? []) + [clip]
    }

    /// Saves the recording's name straight away (Return in the name field).
    func commitName() {
        let trimmed = project.name.trimmingCharacters(in: .whitespacesAndNewlines)
        project.name = trimmed.isEmpty ? "Untitled Recording" : trimmed
        saveTask?.cancel()
        saveNow()
        window?.title = project.name
        endTextEditing()
        NotificationCenter.default.post(name: .framecastLibraryChanged, object: nil)
        nameSaved = true
        Task {
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            nameSaved = false
        }
    }

    func close() {
        player.pause()
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        reloadTimer?.invalidate()
        timeObserver = nil
        keyMonitor = nil
        recorder?.stop()
        auditionPlayer?.stop()
        exporter?.cancel()
        saveNow()
    }

    // MARK: Keeping the preview in sync

    private func projectChanged(from old: Project) {
        guard old != project else { return }
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled, let self else { return }
            self.saveNow()
        }
        let cuts: (Project) -> [[Double]] = { ($0.clips ?? []).map { [$0.start, $0.end, $0.rate] } }
        // Where an audio clip sits needs a rebuild; its volume and fades do not.
        let placed: (Project) -> [[String]] = { ($0.audioClips ?? []).map { [$0.file, "\($0.start)", "\($0.offset)", "\($0.duration)"] } }
        if cuts(old) != cuts(project) || old.audio.musicPath != project.audio.musicPath
            || old.audio.voiceClips != project.audio.voiceClips || placed(old) != placed(project)
            || old.audio.voiceCleanup != project.audio.voiceCleanup {
            // Dragging an audio clip fires many small changes; wait for a pause before rebuilding.
            let settle: UInt64 = cuts(old) == cuts(project) && placed(old) != placed(project) ? 180_000_000 : 0
            rebuildTask?.cancel()
            rebuildTask = Task {
                if settle > 0 { try? await Task.sleep(nanoseconds: settle) }
                guard !Task.isCancelled else { return }
                await rebuild()
            }
            return
        }
        guard let built, let item = player.currentItem else { return }
        if old.audio != project.audio || old.audioClips != project.audioClips {
            item.audioMix = CompositionBuilder.audioMix(built, audio: project.audio, clips: project.audioClips ?? [])
        }
        if old.aspect != project.aspect || old.background != project.background || old.screen != project.screen
            || old.camera != project.camera || old.captions != project.captions || old.captionStyle != project.captionStyle
            || old.zoom != project.zoom || old.manualZooms != project.manualZooms || old.clicks != project.clicks
            || old.cameraSections != project.cameraSections || old.sourceSize != project.sourceSize
            || old.clips != project.clips || old.animationDuration != project.animationDuration
            || old.overlays != project.overlays || old.keystrokes != project.keystrokes
            || old.showKeystrokes != project.showKeystrokes {
            item.videoComposition = previewComposition(built)
        }
    }

    private func previewComposition(_ built: BuiltComposition) -> AVVideoComposition {
        CompositionBuilder.videoComposition(built, project: project, folder: folder,
                                            renderSize: project.canvasSize(shortSide: 1080), fps: 60)
    }

    private func rebuild() async {
        do {
            let built = try await CompositionBuilder.build(ref)
            guard !Task.isCancelled else { return }
            self.built = built
            if project.sourceSize != built.sourceSize, built.sourceSize.width > 0 { project.sourceSize = built.sourceSize }
            let item = AVPlayerItem(asset: built.composition)
            item.audioTimePitchAlgorithm = .timeDomain
            item.videoComposition = previewComposition(built)
            item.audioMix = CompositionBuilder.audioMix(built, audio: project.audio, clips: project.audioClips ?? [])
            player.replaceCurrentItem(with: item)
            seek(currentTime)
            objectWillChange.send()
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func loadThumbnails() async {
        let asset = AVURLAsset(url: ref.url(project.screenFile))
        let generator = AVAssetImageGenerator(asset: asset)
        generator.maximumSize = CGSize(width: 240, height: 160)
        let count = min(max(Int(project.duration / 2), 12), 40)
        var images: [(Double, NSImage)] = []
        for i in 0..<count {
            let t = project.duration * (Double(i) + 0.5) / Double(count)
            if let cg = try? await generator.image(at: CompositionBuilder.time(t)).image {
                images.append((t, NSImage(cgImage: cg, size: .zero)))
            }
        }
        thumbnails = images
    }

    /// The closest pre-rendered thumbnail to a source time.
    func thumbnail(at source: Double) -> NSImage? {
        thumbnails.min(by: { abs($0.time - source) < abs($1.time - source) })?.image
    }

    /// A sharp frame of the raw screen recording at the playhead, for the crop sheet.
    func screenFrame() async -> NSImage? {
        let asset = AVURLAsset(url: ref.url(project.screenFile))
        let generator = AVAssetImageGenerator(asset: asset)
        generator.maximumSize = CGSize(width: 1800, height: 1800)
        let t = CompositionBuilder.time(timeMap.source(currentTime))
        guard let cg = try? await generator.image(at: t).image else { return nil }
        return NSImage(cgImage: cg, size: .zero)
    }

    // MARK: Playback

    private func tick(_ seconds: Double) {
        guard seconds.isFinite, isPlaying else { return }
        currentTime = min(seconds, duration)
        if seconds >= duration - 0.02 {
            if isRecordingVoice { stopVoiceover() } else { pause() }
        }
    }

    func togglePlay() { isPlaying ? pause() : play() }

    func play() {
        if currentTime >= duration - 0.05 { seek(0) }
        player.play()
        isPlaying = true
    }

    func pause() {
        player.pause()
        isPlaying = false
    }

    func seek(_ seconds: Double) {
        let t = min(max(seconds, 0), duration)
        currentTime = t
        player.seek(to: CompositionBuilder.time(t), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    // MARK: Editing the timeline

    /// Remembers the current state so the next change can be undone.
    func checkpoint() {
        undoStack.append(project)
        if undoStack.count > 80 { undoStack.removeFirst() }
        redoStack.removeAll()
        canUndo = true
        canRedo = false
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(project)
        restore(previous)
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(project)
        restore(next)
    }

    private func restore(_ state: Project) {
        project = state
        canUndo = !undoStack.isEmpty
        canRedo = !redoStack.isEmpty
        clearSelection()
        currentTime = min(currentTime, duration)
        if !isPlaying { seek(currentTime) }
    }

    func clearSelection() {
        selectedClip = nil
        selectedZoom = nil
        selectedCamera = nil
        selectedOverlay = nil
        selectedAudio = nil
    }

    /// Q / W: cut away everything in the current clip before (or after) the playhead.
    func trimToPlayhead(start: Bool) {
        let map = timeMap
        guard let index = map.index(atOutput: currentTime) else { return }
        let clip = map.clips[index]
        let at = map.source(currentTime)
        // Needs something to remove on one side and something left over on the other.
        guard start ? (at - clip.start > 0.05 && clip.end - at > 0.2)
                    : (clip.end - at > 0.05 && at - clip.start > 0.2) else { return }
        checkpoint()
        var clips = map.clips
        if start { clips[index].start = at } else { clips[index].end = at }
        project.clips = clips
        selectedClip = clip.id
        currentTime = start ? map.outputStart(of: index) : min(currentTime, duration)
    }

    /// ↑ / ↓: jump to the previous or next cut.
    func jumpToCut(forward: Bool) {
        var edges: [Double] = [0]
        for clip in clips { edges.append(edges.last! + clip.length) }
        if forward { seek(edges.first(where: { $0 > currentTime + 0.02 }) ?? duration) }
        else { seek(edges.last(where: { $0 < currentTime - 0.02 }) ?? 0) }
    }

    /// Cuts the clip under the playhead in two.
    func split() {
        let map = timeMap
        guard let index = map.index(atOutput: currentTime) else { return }
        let clip = map.clips[index]
        let at = map.source(currentTime)
        guard at - clip.start > 0.1, clip.end - at > 0.1 else { return }
        checkpoint()
        var clips = map.clips
        // The piece on the right keeps the original's exit; the new cut starts plain.
        let right = Clip(start: at, end: clip.end, exit: clip.exit, speed: clip.speed)
        clips[index].end = at
        clips[index].exit = nil
        clips.insert(right, at: index + 1)
        project.clips = clips
        selectedClip = right.id
    }

    func deleteSelection() {
        if let id = selectedZoom { deleteZoom(id); return }
        if let id = selectedOverlay {
            checkpoint()
            project.overlays?.removeAll { $0.id == id }
            selectedOverlay = nil
            return
        }
        if let id = selectedAudio {
            checkpoint()
            project.audioClips?.removeAll { $0.id == id }
            selectedAudio = nil
            return
        }
        if let id = selectedCamera {
            checkpoint()
            project.cameraSections?.removeAll { $0.id == id }
            selectedCamera = nil
            return
        }
        guard let id = selectedClip, clips.count > 1, let index = clips.firstIndex(where: { $0.id == id }) else { return }
        checkpoint()
        let start = timeMap.outputStart(of: index)
        var clips = self.clips
        clips.remove(at: index)
        project.clips = clips
        selectedClip = nil
        currentTime = min(start, duration)
    }

    /// Applies an edge-drag from the timeline.
    func commitClips(_ clips: [Clip]) {
        guard clips != self.clips else { return }
        checkpoint()
        project.clips = clips
        currentTime = min(currentTime, duration)
    }

    func resetEdits() {
        checkpoint()
        project.clips = [Clip(start: 0, end: project.duration)]
        selectedClip = nil
    }

    // MARK: Zooms

    var zoomItems: [ZoomItem] {
        let plan = ZoomPlan(clicks: project.clicks ?? [], style: project.zoomStyle, manual: project.manualZooms ?? [])
        var items = plan.autoSegments.enumerated().map { i, s in
            ZoomItem(id: "auto-\(i)", kind: .auto, start: max(s.start, 0), end: min(s.end + ZoomPlan.easeOut, project.duration))
        }
        items += plan.manual.map { ZoomItem(id: $0.id.uuidString, kind: .manual($0.id), start: $0.start, end: $0.end) }
        return items
    }

    var selectedManualZoom: Binding<ZoomRegion>? {
        guard let id = selectedZoom, let index = project.manualZooms?.firstIndex(where: { $0.id.uuidString == id }) else { return nil }
        return Binding(
            get: { [weak self] in
                guard let zooms = self?.project.manualZooms, index < zooms.count else { return ZoomRegion(start: 0, end: 1) }
                return zooms[index]
            },
            set: { [weak self] value in
                guard let self, let zooms = self.project.manualZooms, index < zooms.count else { return }
                self.project.manualZooms?[index] = value
            })
    }

    func addZoom() {
        checkpoint()
        let start = timeMap.source(currentTime)
        let end = min(start + 2.5, project.duration)
        let region = ZoomRegion(start: max(end - 2.5, 0), end: end)
        project.manualZooms = (project.manualZooms ?? []) + [region]
        clearSelection()
        selectedZoom = region.id.uuidString
    }

    // MARK: Camera sections

    var selectedCameraSection: Binding<CameraSection>? {
        guard let id = selectedCamera, let index = project.cameraSections?.firstIndex(where: { $0.id == id }) else { return nil }
        return Binding(
            get: { [weak self] in
                guard let list = self?.project.cameraSections, index < list.count else { return CameraSection(start: 0, end: 1) }
                return list[index]
            },
            set: { [weak self] value in
                guard let self, let list = self.project.cameraSections, index < list.count else { return }
                self.project.cameraSections?[index] = value
            })
    }

    func addCameraSection() {
        guard hasCamera else { return }
        checkpoint()
        let start = timeMap.source(currentTime)
        let end = min(start + 3, project.duration)
        let section = CameraSection(start: max(end - 3, 0), end: end)
        project.cameraSections = (project.cameraSections ?? []) + [section]
        clearSelection()
        selectedCamera = section.id
    }

    // MARK: Entry / exit animations

    /// The clip animations apply to: the selected one, else the one under the playhead.
    var animationTarget: Int? {
        if let id = selectedClip, let index = clips.firstIndex(where: { $0.id == id }) { return index }
        return timeMap.index(atOutput: currentTime)
    }

    /// Sets (or clears) a clip's entry or exit animation, then plays it back as a preview.
    func setAnimation(_ kind: ClipAnimation?, entry: Bool, allClips: Bool = false) {
        guard let index = animationTarget else { return }
        checkpoint()
        var clips = self.clips
        for i in clips.indices where allClips || i == index {
            if entry { clips[i].entry = kind } else { clips[i].exit = kind }
        }
        project.clips = clips
        selectedClip = clips[index].id
        guard kind != nil else { return }
        let start = timeMap.outputStart(of: index)
        let d = project.animationDuration ?? 0.5
        pause()
        seek(entry ? start : max(start + clips[index].length - d - 0.6, start))
        play()
    }

    /// Takes the keyboard away from any text field, so shortcuts work again. Done a moment
    /// later because a text field re-selects itself right after Return is pressed.
    func endTextEditing() {
        DispatchQueue.main.async { [weak self] in
            guard let window = self?.window, window.firstResponder is NSTextView else { return }
            window.makeFirstResponder(nil)
        }
    }

    // MARK: Speed

    /// Speeds up or slows down the selected clip (or the one under the playhead).
    func setSpeed(_ speed: Double) {
        guard let index = animationTarget else { return }
        checkpoint()
        let at = timeMap.source(currentTime)
        var clips = self.clips
        clips[index].speed = abs(speed - 1) < 0.001 ? nil : speed
        project.clips = clips
        selectedClip = clips[index].id
        currentTime = min(TimeMap(clips: clips).output(at), duration)
    }

    // MARK: Style presets

    func applyPreset(_ preset: StylePreset) {
        checkpoint()
        preset.apply(to: &project)
    }

    func saveCurrentStyle() {
        guard let name = PresetStore.askName() else { return }
        PresetStore.shared.add(StylePreset(name: name, from: project))
    }

    func deleteZoom(_ id: String) {
        guard let item = zoomItems.first(where: { $0.id == id }) else { return }
        checkpoint()
        switch item.kind {
        case .manual(let uuid):
            project.manualZooms?.removeAll { $0.id == uuid }
        case .auto:
            // An automatic zoom goes away by forgetting the clicks that caused it.
            project.clicks?.removeAll { $0.time >= item.start - 0.01 && $0.time <= item.end + 0.01 }
        }
        selectedZoom = nil
    }

    // MARK: Audio

    // MARK: Text, images, music and sound effects

    private func binding<T>(_ list: WritableKeyPath<Project, [T]?>, id: UUID?, fallback: T) -> Binding<T>? where T: Identifiable, T.ID == UUID {
        guard let id, let index = project[keyPath: list]?.firstIndex(where: { $0.id == id }) else { return nil }
        return Binding(
            get: { [weak self] in
                guard let items = self?.project[keyPath: list], index < items.count else { return fallback }
                return items[index]
            },
            set: { [weak self] value in
                guard let self, let items = self.project[keyPath: list], index < items.count else { return }
                self.project[keyPath: list]?[index] = value
            })
    }

    var selectedOverlayBinding: Binding<Overlay>? {
        binding(\.overlays, id: selectedOverlay, fallback: Overlay(kind: .text, start: 0, end: 1))
    }

    var selectedAudioBinding: Binding<AudioClip>? {
        binding(\.audioClips, id: selectedAudio, fallback: AudioClip(file: "", name: "", start: 0, duration: 1, fileDuration: 1))
    }

    private func place(_ overlay: Overlay) {
        checkpoint()
        project.overlays = (project.overlays ?? []) + [overlay]
        clearSelection()
        selectedOverlay = overlay.id
    }

    func addText() {
        let start = min(currentTime, max(duration - 0.5, 0))
        place(Overlay(kind: .text, start: start, end: min(start + 3, duration), y: 0.2))
    }

    /// A blur box (to hide something) or a highlight, placed over the middle of the recording.
    func addRegion(_ kind: OverlayKind, spotlight: Bool = false) {
        let start = min(currentTime, max(duration - 0.5, 0))
        var box = Overlay(kind: kind, start: start, end: min(start + 4, duration))
        box.shadow = 0
        box.fade = 0.15
        box.w = 0.3
        box.h = kind == .blur ? 0.12 : 0.08
        box.strength = kind == .blur ? 0.6 : 0.5
        if kind == .highlight {
            box.color = RGBA(r: 1, g: 0.86, b: 0.2)
            box.spotlight = spotlight
        }
        place(box)
    }

    func addImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        // Keep a copy with the recording so it survives the original being moved.
        let name = "overlay-\(UUID().uuidString.prefix(8)).\(url.pathExtension.isEmpty ? "png" : url.pathExtension)"
        let copy = folder.appendingPathComponent(name)
        let file = (try? FileManager.default.copyItem(at: url, to: copy)) != nil ? name : url.path
        let start = min(currentTime, max(duration - 0.5, 0))
        place(Overlay(kind: .image, start: start, end: min(start + 3, duration), size: 0.3, file: file))
    }

    func addAudio() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = false
        panel.message = "Choose music or a sound effect"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let name = "audio-\(UUID().uuidString.prefix(8)).\(url.pathExtension.isEmpty ? "m4a" : url.pathExtension)"
        let copy = folder.appendingPathComponent(name)
        let file = (try? FileManager.default.copyItem(at: url, to: copy)) != nil ? name : url.path
        // With under a second of video left there is no room for it, so start from the top.
        let start = duration - currentTime < 1 ? 0 : currentTime
        Task {
            let length = (try? await AVURLAsset(url: ref.url(file)).load(.duration).seconds) ?? 0
            guard length > 0.05 else {
                voiceError = "That audio file couldn't be read."
                return
            }
            checkpoint()
            let clip = AudioClip(file: file, name: url.deletingPathExtension().lastPathComponent, start: start,
                                 duration: min(length, max(duration - start, 0.3)), fileDuration: length)
            project.audioClips = (project.audioClips ?? []) + [clip]
            clearSelection()
            selectedAudio = clip.id
        }
    }

    /// A second copy of the selected music or sound, placed right after it when there is room.
    func duplicateAudio() {
        guard let id = selectedAudio, let clip = project.audioClips?.first(where: { $0.id == id }) else { return }
        checkpoint()
        var copy = clip
        copy.id = UUID()
        let after = clip.start + clip.duration
        copy.start = duration - after >= 1 ? after : clip.start
        copy.duration = min(clip.duration, max(duration - copy.start, 0.3))
        project.audioClips = (project.audioClips ?? []) + [copy]
        clearSelection()
        selectedAudio = copy.id
    }

    // MARK: Voice clean-up

    /// Turns noise reduction for the microphone on or off. The first time it is switched
    /// on, a cleaned copy of the recording is made; after that the switch is instant.
    func setVoiceCleanup(_ on: Bool) {
        guard let mic = project.micFile else { return }
        guard on else { project.audio.voiceCleanup = false; return }
        let clean = ref.url("mic-clean.m4a")
        if FileManager.default.fileExists(atPath: clean.path) { project.audio.voiceCleanup = true; return }
        guard !isCleaningVoice else { return }
        isCleaningVoice = true
        voiceError = nil
        let input = ref.url(mic)
        Task.detached {
            var failure: String?
            do { try VoiceCleaner.clean(input: input, output: clean) }
            catch {
                try? FileManager.default.removeItem(at: clean)
                failure = error.localizedDescription
            }
            let message = failure
            await MainActor.run {
                self.isCleaningVoice = false
                if let message { self.voiceError = message } else { self.project.audio.voiceCleanup = true }
            }
        }
    }

    // MARK: Trimming and previewing audio clips

    func loadWaveform(for clip: AudioClip) {
        guard waveforms[clip.file] == nil else { return }
        waveforms[clip.file] = []
        let url = ref.url(clip.file)
        let key = clip.file
        Task.detached {
            let peaks = await Self.peaks(of: url, buckets: 260)
            await MainActor.run { self.waveforms[key] = peaks }
        }
    }

    /// The loudest sample in each of `buckets` equal slices of the file, 0…1.
    nonisolated static func peaks(of url: URL, buckets: Int) async -> [Float] {
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .audio).first,
              let reader = try? AVAssetReader(asset: asset) else { return [] }
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 8000, AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsNonInterleaved: false,
        ])
        reader.add(output)
        guard reader.startReading() else { return [] }
        var samples: [Int16] = []
        while let buffer = output.copyNextSampleBuffer() {
            guard let block = CMSampleBufferGetDataBuffer(buffer) else { continue }
            let length = CMBlockBufferGetDataLength(block)
            var data = Data(count: length)
            data.withUnsafeMutableBytes { raw in
                if let base = raw.baseAddress { CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: base) }
            }
            data.withUnsafeBytes { samples.append(contentsOf: $0.bindMemory(to: Int16.self)) }
        }
        guard !samples.isEmpty else { return [] }
        let size = max(samples.count / buckets, 1)
        var peaks: [Float] = []
        var i = 0
        while i < samples.count {
            let slice = samples[i..<min(i + size, samples.count)]
            peaks.append(Float(slice.map { abs(Int32($0)) }.max() ?? 0) / 32768)
            i += size
        }
        let top = max(peaks.max() ?? 1, 0.05)
        return peaks.map { $0 / top }
    }

    /// Plays just the chosen part of an audio clip, by itself, so it can be checked by ear.
    func toggleAudition(_ clip: AudioClip) {
        if auditioning == clip.id { stopAudition(); return }
        stopAudition()
        pause()
        guard let player = try? AVAudioPlayer(contentsOf: ref.url(clip.file)) else { return }
        player.currentTime = clip.offset
        player.volume = Float(min(clip.volume, 1))
        player.play()
        auditionPlayer = player
        auditioning = clip.id
        let id = clip.id, length = clip.duration
        Task {
            try? await Task.sleep(nanoseconds: UInt64(length * 1_000_000_000))
            if auditioning == id { stopAudition() }
        }
    }

    func stopAudition() {
        auditionPlayer?.stop()
        auditionPlayer = nil
        auditioning = nil
    }

    func toggleVoiceover() { isRecordingVoice ? stopVoiceover() : startVoiceover() }

    private func startVoiceover() {
        voiceError = nil
        Task {
            guard await AVCaptureDevice.requestAccess(for: .audio) else {
                voiceError = "Microphone access is off. Turn it on in System Settings › Privacy & Security › Microphone."
                return
            }
            pause()
            if currentTime >= duration - 0.3 { seek(0) }
            voiceFile = "voice-\(Int(Date().timeIntervalSince1970)).m4a"
            do {
                let rec = try AVAudioRecorder(url: folder.appendingPathComponent(voiceFile), settings: [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVSampleRateKey: 48_000,
                    AVNumberOfChannelsKey: 1,
                    AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
                ])
                guard rec.record() else { throw NSError(domain: "Framecast", code: 3) }
                recorder = rec
                voiceStart = currentTime
                isRecordingVoice = true
                // Silence playback so the speakers don't bleed into the take.
                player.isMuted = true
                play()
            } catch {
                voiceError = "Couldn't start recording from the microphone."
            }
        }
    }

    private func stopVoiceover() {
        guard isRecordingVoice else { return }
        recorder?.stop()
        recorder = nil
        pause()
        player.isMuted = false
        isRecordingVoice = false
        project.audio.voiceClips.append(VoiceClip(file: voiceFile, start: voiceStart))
    }

    func removeVoiceClip(_ clip: VoiceClip) {
        project.audio.voiceClips.removeAll { $0.id == clip.id }
        try? FileManager.default.removeItem(at: folder.appendingPathComponent(clip.file))
    }

    // MARK: Background

    func chooseBackgroundImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            project.background.imagePath = url.path
            project.background.mode = .image
        }
    }

    // MARK: Captions

    func generateCaptions() {
        guard !isGeneratingCaptions else { return }
        isGeneratingCaptions = true
        captionError = nil
        let ref = self.ref
        Task {
            do {
                project.captions = try await CaptionGenerator.generate(for: ref)
                project.captionStyle.visible = true
            } catch {
                captionError = error.localizedDescription
            }
            isGeneratingCaptions = false
        }
    }

    /// Asks for a font file and copies it next to the recordings so it keeps working if
    /// the original moves. Returns the copy's path, or nil if cancelled or unreadable.
    func pickFont() -> String? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = ["ttf", "otf", "ttc"].compactMap { UTType(filenameExtension: $0) }
        panel.allowsMultipleSelection = false
        panel.message = "Choose a font file (.ttf or .otf)"
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        let fonts = ProjectStore.root.appendingPathComponent("Fonts", isDirectory: true)
        try? FileManager.default.createDirectory(at: fonts, withIntermediateDirectories: true)
        let copy = fonts.appendingPathComponent(url.lastPathComponent)
        if !FileManager.default.fileExists(atPath: copy.path) { try? FileManager.default.copyItem(at: url, to: copy) }
        let path = FileManager.default.fileExists(atPath: copy.path) ? copy.path : url.path
        guard let all = CTFontManagerCreateFontDescriptorsFromURL(URL(fileURLWithPath: path) as CFURL) as? [CTFontDescriptor],
              !all.isEmpty else {
            captionError = "That file couldn't be read as a font."
            return nil
        }
        captionError = nil
        return path
    }

    func chooseCaptionFont() {
        if let path = pickFont() { project.captionStyle.fontPath = path }
    }

    var captionFontName: String {
        guard let path = project.captionStyle.fontPath else { return "System" }
        if let all = CTFontManagerCreateFontDescriptorsFromURL(URL(fileURLWithPath: path) as CFURL) as? [CTFontDescriptor],
           let first = all.first,
           let name = CTFontDescriptorCopyAttribute(first, kCTFontDisplayNameAttribute) as? String { return name }
        return URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
    }

    func exportSRT() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = project.name + ".srt"
        if panel.runModal() == .OK, let url = panel.url {
            // Shift captions onto the edited timeline and drop the ones that were cut out.
            let map = timeMap
            let shifted = project.captions.compactMap { c -> CaptionSegment? in
                let start = map.output(c.start), end = map.output(c.end)
                return end - start > 0.05 ? CaptionSegment(start: start, end: end, text: c.text) : nil
            }
            try? CaptionGenerator.srt(shifted).write(to: url, atomically: true, encoding: .utf8)
        }
    }

    // MARK: Export

    func export(resolution: ExportResolution, fps: Int32) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.mpeg4Movie]
        panel.nameFieldStringValue = "\(project.name) \(resolution.rawValue).mp4"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        pause()
        exportPhase = .running(0)
        let exporter = Exporter()
        self.exporter = exporter
        let ref = self.ref
        Task {
            do {
                try await exporter.export(ref: ref, to: url, resolution: resolution, fps: fps) { [weak self] p in
                    Task { @MainActor in
                        if case .running = self?.exportPhase { self?.exportPhase = .running(p) }
                    }
                }
                exportPhase = .done(url)
                NSSound(named: "Glass")?.play()
                NSApp.requestUserAttention(.informationalRequest)
            } catch is CancellationError {
                exportPhase = .idle
            } catch {
                exportPhase = .failed(error.localizedDescription)
            }
            self.exporter = nil
        }
    }

    func cancelExport() { exporter?.cancel() }
}
