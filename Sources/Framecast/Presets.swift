import AppKit

/// A saved look: everything about how a video is styled, nothing about its content.
struct StylePreset: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var aspect: CanvasAspect
    var background: BackgroundStyle
    var screen: ScreenStyle
    var camera: CameraStyle
    var captionStyle: CaptionStyle
    var zoom: ZoomStyle

    init(name: String, from project: Project) {
        self.name = name
        aspect = project.aspect
        background = project.background
        screen = project.screen
        screen.crop = nil            // a crop belongs to one recording, not to a style
        camera = project.camera
        captionStyle = project.captionStyle
        zoom = project.zoomStyle
    }

    func apply(to project: inout Project) {
        let crop = project.screen.crop
        project.aspect = aspect
        project.background = background
        project.screen = screen
        project.screen.crop = crop
        project.camera = camera
        project.captionStyle = captionStyle
        project.zoomStyle = zoom
    }
}

@MainActor
final class PresetStore: ObservableObject {
    static let shared = PresetStore()
    @Published private(set) var presets: [StylePreset] = []
    /// The preset applied to every new recording, if any.
    @Published var defaultID: UUID? {
        didSet { UserDefaults.standard.set(defaultID?.uuidString ?? "", forKey: "defaultPreset") }
    }

    private var url: URL { ProjectStore.root.appendingPathComponent("presets.json") }

    private init() {
        if let data = try? Data(contentsOf: url), let list = try? JSONDecoder().decode([StylePreset].self, from: data) {
            presets = list
        }
        defaultID = UserDefaults.standard.string(forKey: "defaultPreset").flatMap(UUID.init(uuidString:))
        if let id = defaultID, !presets.contains(where: { $0.id == id }) { defaultID = nil }
    }

    var defaultPreset: StylePreset? { presets.first { $0.id == defaultID } }

    func add(_ preset: StylePreset) {
        presets.removeAll { $0.name == preset.name }
        presets.append(preset)
        save()
    }

    func delete(_ preset: StylePreset) {
        presets.removeAll { $0.id == preset.id }
        if defaultID == preset.id { defaultID = nil }
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(presets) { try? data.write(to: url, options: .atomic) }
    }

    /// Asks for a name with a small dialog. Returns nil if cancelled.
    static func askName() -> String? {
        let alert = NSAlert()
        alert.messageText = "Save Preset"
        alert.informativeText = "Saves the background, screen, camera, caption and zoom settings so you can reuse them."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.placeholderString = "Preset name"
        alert.accessoryView = field
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let name = field.stringValue.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : name
    }
}
