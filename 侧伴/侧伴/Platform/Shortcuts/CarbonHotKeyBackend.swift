import AppKit
import Carbon
import SidebarCore

/// Registers only the explicitly configured combinations; no global keyboard monitor or Accessibility access.
@MainActor final class CarbonHotKeyBackend: HotKeyRegistering {
    var onAction: ((ShortcutAction) -> Void)?
    private var references: [ShortcutAction: EventHotKeyRef] = [:]
    private var pressed: Set<ShortcutAction> = []
    private var handler: EventHandlerRef?
    private var localMonitor: Any?
    private var bindings: [ShortcutAction: KeyboardShortcutBinding] = [:]
    private static let signature: OSType = 0x4342484B // CBHK

    func register(_ binding: KeyboardShortcutBinding, for action: ShortcutAction) -> Bool {
        guard installHandler() else { return false }
        unregister(action)
        var modifiers: UInt32 = 0
        if binding.modifiers.contains(.command) { modifiers |= UInt32(cmdKey) }
        if binding.modifiers.contains(.control) { modifiers |= UInt32(controlKey) }
        if binding.modifiers.contains(.option) { modifiers |= UInt32(optionKey) }
        if binding.modifiers.contains(.shift) { modifiers |= UInt32(shiftKey) }
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(binding.keyCode, modifiers,
                                        EventHotKeyID(signature: Self.signature, id: action.hotKeyID),
                                        GetApplicationEventTarget(), 0, &reference)
        guard status == noErr, let reference else { return false }
        references[action] = reference
        bindings[action] = binding
        installLocalFallback()
        return true
    }

    func unregister(_ action: ShortcutAction) {
        if let reference = references.removeValue(forKey: action) { UnregisterEventHotKey(reference) }
        pressed.remove(action)
        bindings.removeValue(forKey: action)
    }

    /// Targeted key events (including keyboard access tools) may bypass the WindowServer hotkey path.
    /// The same held-key set deduplicates local events and Carbon events.
    private func installLocalFallback() {
        guard localMonitor == nil else { return }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            guard let self else { return event }
            if event.type == .keyUp,
               let action = self.bindings.first(where: { $0.value.keyCode == UInt32(event.keyCode) && self.pressed.contains($0.key) })?.key {
                self.receive(id: action.hotKeyID, isPressed: false)
                return nil
            }
            let flags = event.modifierFlags.intersection([.command, .control, .option, .shift])
            var modifiers: ShortcutModifiers = []
            if flags.contains(.command) { modifiers.insert(.command) }
            if flags.contains(.control) { modifiers.insert(.control) }
            if flags.contains(.option) { modifiers.insert(.option) }
            if flags.contains(.shift) { modifiers.insert(.shift) }
            guard let action = self.bindings.first(where: { $0.value.keyCode == UInt32(event.keyCode) && $0.value.modifiers == modifiers })?.key else { return event }
            if event.type == .keyDown {
                if !event.isARepeat { self.receive(id: action.hotKeyID, isPressed: true) }
            } else { self.receive(id: action.hotKeyID, isPressed: false) }
            return nil
        }
    }

    private func installHandler() -> Bool {
        if handler != nil { return true }
        var events = [EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
                      EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))]
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var identifier = EventHotKeyID()
            guard GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                    nil, MemoryLayout<EventHotKeyID>.size, nil, &identifier) == noErr,
                  identifier.signature == 0x4342484B else { return OSStatus(eventNotHandledErr) }
            let backend = Unmanaged<CarbonHotKeyBackend>.fromOpaque(context).takeUnretainedValue()
            let id = identifier.id
            let isPressed = GetEventKind(event) == UInt32(kEventHotKeyPressed)
            // The Carbon application target dispatches on the main event loop.
            return MainActor.assumeIsolated {
                backend.receive(id: id, isPressed: isPressed) ? noErr : OSStatus(eventNotHandledErr)
            }
        }, events.count, &events, Unmanaged.passUnretained(self).toOpaque(), &handler)
        return status == noErr
    }

    @discardableResult private func receive(id: UInt32, isPressed: Bool) -> Bool {
        guard let action = ShortcutAction.allCases.first(where: { $0.hotKeyID == id }), references[action] != nil else { return false }
        if isPressed {
            guard pressed.insert(action).inserted else { return true }
            onAction?(action)
        } else { pressed.remove(action) }
        return true
    }

    deinit {
        for reference in references.values { UnregisterEventHotKey(reference) }
        if let handler { RemoveEventHandler(handler) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
    }
}
