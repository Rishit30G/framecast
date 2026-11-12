import AppKit
import Combine
import SwiftUI

/// A borderless window that can still take keyboard focus and open menus.
final class KeyableWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let recorder = RecorderModel()
    private let library = Library()
    private let areaSelector = AreaSelector()
    private let areaFrame = AreaFrameWindow()

    private var recorderWindow: NSWindow?
    private var countdownWindow: NSWindow?
    private var pillWindow: NSWindow?
    private var bubbleWindow: NSWindow?
    private var statusItem: NSStatusItem?
    private var editors: [UUID: (window: NSWindow, model: EditorModel)] = [:]
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()
        buildStatusItem()
        library.reload()
        recorder.onFinished = { [weak self] ref in
            self?.library.reload()
            self?.openEditor(ref)
        }
        NotificationCenter.default.addObserver(forName: .framecastLibraryChanged, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.library.reload() }
        }
        recorder.$state.removeDuplicates().sink { [weak self] state in self?.stateChanged(state) }.store(in: &cancellables)
        recorder.$cameraID.receive(on: RunLoop.main).sink { [weak self] _ in self?.updateBubble() }.store(in: &cancellables)
        recorder.$mode.combineLatest(recorder.$area).sink { [weak self] mode, area in
            if mode == .area, let area { self?.areaFrame.show(area.rect) } else { self?.areaFrame.hide() }
        }.store(in: &cancellables)
        // `--open <project folder>` jumps straight into the editor.
        if let i = CommandLine.arguments.firstIndex(of: "--open"), CommandLine.arguments.count > i + 1,
           let ref = ProjectStore.load(folder: URL(fileURLWithPath: CommandLine.arguments[i + 1])) {
            openEditor(ref)
        } else {
            showRecorder()
        }
        NSApp.activate(ignoringOtherApps: true)

        // Test hook: `FC_TEST=pill` shows the recording controls without recording.
        if ProcessInfo.processInfo.environment["FC_TEST"] == "pill" { showPill() }

        // ⌥⌘R starts or stops a recording and ⌥⌘P pauses it, from any app.
        HotKeys.register(id: 1, keyCode: 15) { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                switch self.recorder.state {
                case .recording: await self.recorder.stop()
                case .idle: if self.recorder.canRecord { await self.recorder.start() } else { self.showRecorder() }
                default: break
                }
            }
        }
        HotKeys.register(id: 2, keyCode: 35) { [weak self] in
            Task { @MainActor in self?.recorder.togglePause() }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showRecorder() }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        editors.values.forEach { $0.model.close() }
        recorder.camera.shutdown()
    }

    // MARK: Windows

    @objc func showRecorder() {
        guard recorder.state == .idle else { return }
        if recorderWindow == nil {
            let window = KeyableWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = true
            window.level = .floating
            window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            let host = NSHostingView(rootView: RecorderBar(
                model: recorder, library: library,
                selectArea: { [weak self] in self?.selectArea() },
                open: { [weak self] ref in self?.openEditor(ref) },
                close: { [weak self] in self?.hideRecorder() },
                resized: { [weak self] size in self?.resizeBar(to: size) }))
            host.sizingOptions = []
            window.contentView = host
            let size = host.fittingSize
            if let screen = NSScreen.main {
                window.setFrame(CGRect(x: screen.visibleFrame.midX - size.width / 2, y: screen.visibleFrame.minY + 90,
                                       width: size.width, height: size.height), display: false)
            }
            recorderWindow = window
        }
        library.reload()
        recorder.setPreview(active: true)
        Task { await recorder.refreshContent() }
        recorderWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        updateBubble()
    }

    private func hideRecorder() {
        recorderWindow?.orderOut(nil)
        if recorder.state == .idle { recorder.setPreview(active: false) }
        updateBubble()
    }

    /// Keeps the bar's window exactly as large as its content, growing from its centre,
    /// so nothing (like the Record button) is ever clipped off the edge.
    private func resizeBar(to size: CGSize) {
        guard let window = recorderWindow, size.width > 10, size.height > 10 else { return }
        let old = window.frame
        guard abs(old.width - size.width) > 0.5 || abs(old.height - size.height) > 0.5 else { return }
        var frame = CGRect(x: old.midX - size.width / 2, y: old.minY, width: size.width, height: size.height)
        if let visible = (window.screen ?? NSScreen.main)?.visibleFrame {
            frame.origin.x = min(max(frame.minX, visible.minX + 8), visible.maxX - frame.width - 8)
        }
        window.setFrame(frame, display: true)
    }

    private var bubbleSide: CGFloat {
        let saved = UserDefaults.standard.double(forKey: "bubbleSide")
        return saved >= 120 ? CGFloat(saved) : 260
    }

    /// Shows the camera preview whenever a camera is chosen and the recorder is up or running.
    private func updateBubble() {
        let busy: Bool
        switch recorder.state {
        case .countdown, .recording: busy = true
        default: busy = false
        }
        let visible = recorder.cameraID != nil && (busy || recorderWindow?.isVisible == true)
        guard visible else { bubbleWindow?.orderOut(nil); return }
        if bubbleWindow == nil { buildBubble(keepingCorner: nil) }
        bubbleWindow?.orderFrontRegardless()
    }

    /// Creates the preview window. It opens in the bottom-right corner unless the user has
    /// moved it; `keepingCorner` pins the bottom-right corner when only the size changes.
    private func buildBubble(keepingCorner corner: CGPoint?) {
        if let old = bubbleWindow {
            NotificationCenter.default.removeObserver(self, name: NSWindow.didMoveNotification, object: old)
            old.orderOut(nil)
        }
        let window = floatingWindow(CameraBubble(session: recorder.camera.session, side: bubbleSide) { [weak self] side in
            guard let self, let current = self.bubbleWindow else { return }
            UserDefaults.standard.set(Double(side), forKey: "bubbleSide")
            self.buildBubble(keepingCorner: CGPoint(x: current.frame.maxX, y: current.frame.minY))
            self.bubbleWindow?.orderFrontRegardless()
        })
        window.level = .floating
        let size = window.frame.size
        let visible = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        var origin = CGPoint(x: visible.maxX - size.width - 8, y: visible.minY + 8)
        let defaults = UserDefaults.standard
        if let corner {
            origin = CGPoint(x: corner.x - size.width, y: corner.y)
        } else if defaults.object(forKey: "bubbleX") != nil {
            let saved = CGPoint(x: defaults.double(forKey: "bubbleX"), y: defaults.double(forKey: "bubbleY"))
            // Ignore a saved spot that is no longer on any screen.
            if NSScreen.screens.contains(where: { $0.frame.intersects(CGRect(origin: saved, size: size)) }) { origin = saved }
        }
        window.setFrameOrigin(origin)
        NotificationCenter.default.addObserver(self, selector: #selector(bubbleMoved(_:)),
                                               name: NSWindow.didMoveNotification, object: window)
        bubbleWindow = window
        if corner != nil { bubbleMoved(Notification(name: NSWindow.didMoveNotification, object: window)) }
    }

    @objc private func bubbleMoved(_ note: Notification) {
        guard let window = note.object as? NSWindow else { return }
        UserDefaults.standard.set(Double(window.frame.minX), forKey: "bubbleX")
        UserDefaults.standard.set(Double(window.frame.minY), forKey: "bubbleY")
    }

    private func selectArea() {
        recorderWindow?.orderOut(nil)
        bubbleWindow?.orderOut(nil)
        areaFrame.hide()
        areaSelector.begin { [weak self] selection in
            guard let self else { return }
            if let selection { self.recorder.area = selection }
            else if let existing = self.recorder.area { self.areaFrame.show(existing.rect) }
            self.recorderWindow?.makeKeyAndOrderFront(nil)
            self.updateBubble()
        }
    }

    private func openEditor(_ ref: ProjectRef) {
        if let existing = editors[ref.id] {
            existing.window.makeKeyAndOrderFront(nil)
            return
        }
        let model = EditorModel(ref: ref)
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1300, height: 800),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.title = ref.project.name
        window.isReleasedWhenClosed = false
        window.identifier = NSUserInterfaceItemIdentifier(ref.id.uuidString)
        window.delegate = self
        window.contentView = NSHostingView(rootView: EditorView(model: model))
        window.center()
        model.window = window
        editors[ref.id] = (window, model)
        hideRecorder()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              let raw = window.identifier?.rawValue, let id = UUID(uuidString: raw),
              let entry = editors[id] else { return }
        entry.model.close()
        editors[id] = nil
        // Give the folder in Finder the recording's name too.
        ProjectStore.renameFolder(entry.model.ref)
        library.reload()
        // Back to the recorder once the last editor is closed.
        if editors.isEmpty { DispatchQueue.main.async { [weak self] in self?.showRecorder() } }
    }

    // MARK: Recording state

    private func stateChanged(_ state: RecorderState) {
        switch state {
        case .countdown(let n):
            recorderWindow?.orderOut(nil)
            showCountdown(n)
        case .recording:
            recorderWindow?.orderOut(nil)
            hideCountdown()
            showPill()
            statusItem?.menu = nil
            statusItem?.button?.image = NSImage(systemSymbolName: "stop.circle.fill", accessibilityDescription: "Stop recording")
            statusItem?.button?.contentTintColor = .white
        case .finishing:
            break
        case .idle:
            hideCountdown()
            pillWindow?.orderOut(nil)
            statusItem?.button?.title = ""
            statusItem?.button?.contentTintColor = .white
            statusItem?.button?.image = NSImage(systemSymbolName: "record.circle", accessibilityDescription: "Framecast")
            statusItem?.menu = statusMenu()
            // A failed start comes back to idle with an error: bring the recorder back to show it.
            // After a discard or a failed start there is no editor to go to: bring the bar back.
            DispatchQueue.main.async { [weak self] in
                guard let self, self.recorder.state == .idle, self.editors.isEmpty,
                      self.recorderWindow?.isVisible != true else { return }
                self.showRecorder()
            }
        }
        updateBubble()
    }

    private func floatingWindow<V: View>(_ view: V) -> NSWindow {
        let host = NSHostingView(rootView: view)
        let window = NSPanel(contentRect: CGRect(origin: .zero, size: host.fittingSize),
                             styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .statusBar
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.contentView = host
        return window
    }

    private func showCountdown(_ n: Int) {
        hideCountdown()
        let window = floatingWindow(CountdownView(number: n))
        window.ignoresMouseEvents = true
        if let screen = NSScreen.main {
            window.setFrameOrigin(CGPoint(x: screen.frame.midX - window.frame.width / 2,
                                          y: screen.frame.midY - window.frame.height / 2))
        }
        window.orderFrontRegardless()
        countdownWindow = window
    }

    private func hideCountdown() {
        countdownWindow?.orderOut(nil)
        countdownWindow = nil
    }

    private func showPill() {
        if pillWindow == nil {
            let window = floatingWindow(StopPillView(model: recorder))
            window.isMovableByWindowBackground = true
            pillWindow = window
        }
        if let window = pillWindow, let screen = NSScreen.main {
            window.setFrameOrigin(CGPoint(x: screen.visibleFrame.midX - window.frame.width / 2,
                                          y: screen.visibleFrame.minY + 24))
            window.orderFrontRegardless()
        }
    }

    // MARK: Menus

    private func buildStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "record.circle", accessibilityDescription: "Framecast")
        item.button?.imagePosition = .imageOnly
        item.button?.contentTintColor = .white
        item.button?.target = self
        item.button?.action = #selector(statusClicked)
        item.menu = statusMenu()
        statusItem = item
    }

    private func statusMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: "New Recording", action: #selector(showRecorder), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Open Recordings Folder", action: #selector(openFolder), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Framecast", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        return menu
    }

    @objc private func statusClicked() {
        if recorder.state == .recording { Task { await recorder.stop() } }
    }

    @objc private func openFolder() { NSWorkspace.shared.open(ProjectStore.root) }

    private func buildMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Framecast", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Framecast", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Quit Framecast", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let fileItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(withTitle: "New Recording", action: #selector(showRecorder), keyEquivalent: "n").target = self
        fileMenu.addItem(withTitle: "Open Recordings Folder", action: #selector(openFolder), keyEquivalent: "").target = self
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        fileItem.submenu = fileMenu
        main.addItem(fileItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        main.addItem(editItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowItem.submenu = windowMenu
        main.addItem(windowItem)
        NSApp.windowsMenu = windowMenu

        NSApp.mainMenu = main
    }
}
