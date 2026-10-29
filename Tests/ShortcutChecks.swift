import Foundation
import SidebarCore

@MainActor private final class FakeHotKeyBackend: HotKeyRegistering {
    var onAction: ((ShortcutAction) -> Void)?
    var registered: [ShortcutAction: KeyboardShortcutBinding] = [:]
    var rejectedKey: UInt32?
    var registerCalls = 0
    func register(_ binding: KeyboardShortcutBinding, for action: ShortcutAction) -> Bool {
        registerCalls += 1
        guard binding.keyCode != rejectedKey else { return false }
        registered[action] = binding
        return true
    }
    func unregister(_ action: ShortcutAction) { registered.removeValue(forKey: action) }
}

@MainActor func checkShortcuts() throws {
    let suite = "SidebarShortcutChecks-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let backend = FakeHotKeyBackend()
    let manager = ShortcutManager(defaults: defaults, backend: backend)
    var fired: [ShortcutAction] = []
    manager.connect(actions: Dictionary(uniqueKeysWithValues: ShortcutAction.allCases.map { action in
        (action, { fired.append(action) })
    }))
    precondition(backend.registered.count == 3 && manager.issues.isEmpty)
    for action in ShortcutAction.allCases { backend.onAction?(action) }
    precondition(fired == ShortcutAction.allCases, "all three actions route independently")
    let registrationCount = backend.registerCalls
    manager.connect(actions: [.focus: { fired.append(.focus) }])
    precondition(backend.registerCalls == registrationCount, "reappearing views must not duplicate registration")
    manager.beginRecording(.focus)
    precondition(backend.registered.isEmpty, "capture suspends global combinations")
    backend.onAction?(.focus)
    precondition(fired.count == 3, "stale events do not fire during capture")
    let previous = manager.bindings[.focus]!
    let originalData = defaults.data(forKey: ShortcutManager.preferenceKey)
    let bareKey = KeyboardShortcutBinding(keyCode: 0, modifiers: [], keyLabel: "A")
    precondition(manager.assign(bareKey, to: .focus) == .invalid)
    precondition(!KeyboardShortcutBinding(keyCode: 0, modifiers: .shift, keyLabel: "A").isValid)
    precondition(!KeyboardShortcutBinding(keyCode: 8, modifiers: .command, keyLabel: "C").isValid, "standard copy shortcut is protected")
    let duplicate = manager.bindings[.recording]!
    let relabeled = KeyboardShortcutBinding(keyCode: duplicate.keyCode, modifiers: duplicate.modifiers, keyLabel: "不同布局")
    precondition(manager.assign(relabeled, to: .focus) == .duplicate, "conflicts match physical keys, not display labels")
    precondition(defaults.data(forKey: ShortcutManager.preferenceKey) == originalData, "rejected combinations never overwrite saved bindings")
    let replacement = KeyboardShortcutBinding(keyCode: 17, modifiers: [.command, .option, .shift], keyLabel: "T")
    backend.rejectedKey = replacement.keyCode
    precondition(manager.assign(replacement, to: .focus) == .unavailable)
    precondition(manager.bindings[.focus] == previous)
    manager.endRecording(.focus)
    precondition(backend.registered[.focus] == previous, "cancel restores the old working binding")
    backend.onAction?(.focus)
    precondition(fired.count == 4)
    manager.beginRecording(.focus)
    backend.rejectedKey = nil
    precondition(manager.assign(replacement, to: .focus) == nil)
    precondition(manager.recordingAction == .focus, "actions remain suspended until capture ends")
    backend.onAction?(.focus)
    precondition(fired.count == 4)
    manager.endRecording(.focus)
    precondition(backend.registered[.focus] == replacement)
    manager.beginRecording(.recording)
    manager.endRecording(.focus)
    precondition(manager.recordingAction == .recording, "old recorder cannot end another recorder's session")
    manager.endRecording()
    precondition(manager.assign(nil, to: .recording) == nil)
    precondition(backend.registered[.recording] == nil)
    let reopened = ShortcutManager(defaults: UserDefaults(suiteName: suite)!, backend: FakeHotKeyBackend())
    precondition(reopened.bindings[.focus] == replacement && reopened.bindings[.recording] == nil && reopened.bindings[.sidebar] != nil,
                 "custom keys and explicitly cleared actions persist")
    defaults.removeObject(forKey: ShortcutManager.preferenceKey)
    defaults.set("commandShiftT", forKey: "timerShortcut")
    let migrated = ShortcutManager(defaults: defaults, backend: FakeHotKeyBackend())
    precondition(migrated.bindings[.focus]?.keyCode == 17 && migrated.bindings[.focus]?.modifiers == [.command, .shift])
    defaults.removeObject(forKey: ShortcutManager.preferenceKey)
    defaults.set("space", forKey: "timerShortcut")
    let spaceMigrated = ShortcutManager(defaults: defaults, backend: FakeHotKeyBackend())
    precondition(spaceMigrated.bindings[.focus] == .defaults(for: .focus), "legacy bare Space becomes a safe global combination")
    let unavailableBackend = FakeHotKeyBackend()
    unavailableBackend.rejectedKey = 35
    let unavailable = ShortcutManager(defaults: defaults, backend: unavailableBackend)
    unavailable.connect(actions: [.focus: { preconditionFailure("unregistered action must never fire") }])
    precondition(unavailable.issues[.focus] == .unavailable)
    unavailableBackend.onAction?(.focus)
    print("PASS: custom global shortcut persistence, migration, action dispatch, capture suppression, duplicate/reserved-key validation, conflict rollback and clearing")
}
