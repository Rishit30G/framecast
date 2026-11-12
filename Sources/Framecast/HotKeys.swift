import AppKit
import Carbon.HIToolbox

/// System-wide keyboard shortcuts that work while another app is in front.
enum HotKeys {
    private static var actions: [UInt32: () -> Void] = [:]
    private static var installed = false

    /// `keyCode` is a virtual key code (kVK_…); the shortcut is ⌥⌘ + that key.
    static func register(id: UInt32, keyCode: Int, action: @escaping () -> Void) {
        if !installed {
            installed = true
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
                var hotKey = EventHotKeyID()
                GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                  nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKey)
                let id = hotKey.id
                DispatchQueue.main.async { HotKeys.actions[id]?() }
                return noErr
            }, 1, &spec, nil, nil)
        }
        actions[id] = action
        var ref: EventHotKeyRef?
        RegisterEventHotKey(UInt32(keyCode), UInt32(cmdKey | optionKey),
                            EventHotKeyID(signature: OSType(0x4643_5354), id: id),
                            GetApplicationEventTarget(), 0, &ref)
    }
}
