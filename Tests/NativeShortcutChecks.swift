import AppKit
import Carbon
import SidebarCore

// Requires an interactive macOS session; does not synthesize OS key events or access the microphone.
@main struct NativeShortcutChecks {
    @MainActor static func main() {
        _ = NSApplication.shared
        let backend = CarbonHotKeyBackend()
        let binding = KeyboardShortcutBinding(keyCode: 40, modifiers: [.control, .option, .shift], keyLabel: "K")
        var count = 0
        backend.onAction = { action in precondition(action == .focus); count += 1 }
        precondition(backend.register(binding, for: .focus), "OS registration succeeds")
        let conflicting = CarbonHotKeyBackend()
        precondition(!conflicting.register(binding, for: .recording), "OS rejects a conflicting global combination")
        func send(_ kind: UInt32) {
            var eventReference: EventRef?
            precondition(CreateEvent(nil, OSType(kEventClassKeyboard), kind, 0, EventAttributes(kEventAttributeNone), &eventReference) == noErr)
            let event = eventReference!
            defer { ReleaseEvent(event) }
            var id = EventHotKeyID(signature: 0x4342484B, id: ShortcutAction.focus.hotKeyID)
            precondition(SetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), MemoryLayout<EventHotKeyID>.size, &id) == noErr)
            _ = SendEventToEventTarget(event, GetApplicationEventTarget())
        }
        send(UInt32(kEventHotKeyPressed)); send(UInt32(kEventHotKeyPressed))
        precondition(count == 1, "held key does not repeatedly toggle")
        send(UInt32(kEventHotKeyReleased)); send(UInt32(kEventHotKeyPressed))
        precondition(count == 2, "next physical press can toggle again")
        backend.unregister(.focus)
        send(UInt32(kEventHotKeyPressed))
        precondition(count == 2, "unregistered shortcuts ignore stale events")
        print("PASS: OS hotkey registration/conflict, Carbon callback, repeat suppression, release and unregister")
    }
}
