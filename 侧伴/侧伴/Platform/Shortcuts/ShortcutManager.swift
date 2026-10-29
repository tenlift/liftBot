import Foundation
import Observation
import SidebarCore

@MainActor protocol HotKeyRegistering: AnyObject {
    var onAction: ((ShortcutAction) -> Void)? { get set }
    func register(_ binding: KeyboardShortcutBinding, for action: ShortcutAction) -> Bool
    func unregister(_ action: ShortcutAction)
}

enum ShortcutIssue: Equatable {
    case invalid, duplicate, unavailable
    var message: String {
        switch self {
        case .invalid: L10n.text("请使用包含 ⌘、⌃ 或 ⌥ 的组合键，并避开常用编辑和系统快捷键。")
        case .duplicate: L10n.text("这个组合已用于其他动作，请换一个。")
        case .unavailable: L10n.text("无法注册这个快捷键，可能已被系统或其他应用占用，请换一个。")
        }
    }
}

@MainActor @Observable final class ShortcutManager {
    static let preferenceKey = "keyboardShortcuts.v1"
    private(set) var bindings: [ShortcutAction: KeyboardShortcutBinding] = [:]
    private(set) var issues: [ShortcutAction: ShortcutIssue] = [:]
    private(set) var recordingAction: ShortcutAction?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let backend: any HotKeyRegistering
    @ObservationIgnored private var connected = false
    @ObservationIgnored private var activeActions: Set<ShortcutAction> = []
    @ObservationIgnored private var actions: [ShortcutAction: () -> Void] = [:]

    init(defaults: UserDefaults = .standard, backend: (any HotKeyRegistering)? = nil) {
        self.defaults = defaults
        self.backend = backend ?? CarbonHotKeyBackend()
        if let data = defaults.data(forKey: Self.preferenceKey),
           let saved = try? JSONDecoder().decode([String: KeyboardShortcutBinding].self, from: data) {
            for action in ShortcutAction.allCases {
                guard let binding = saved[action.rawValue], binding.isValid,
                      !bindings.values.contains(where: { $0.hasSameKeys(as: binding) }) else { continue }
                bindings[action] = binding
            }
        } else {
            bindings = Dictionary(uniqueKeysWithValues: ShortcutAction.allCases.map { ($0, .defaults(for: $0)) })
            // Preserve an explicitly chosen legacy modified shortcut; bare Space becomes ⌃⌥P.
            if let legacy = defaults.string(forKey: "timerShortcut"), ["commandShiftP", "commandShiftT"].contains(legacy) {
                bindings[.focus] = KeyboardShortcutBinding(keyCode: legacy == "commandShiftP" ? 35 : 17,
                                                         modifiers: [.command, .shift], keyLabel: legacy == "commandShiftP" ? "P" : "T")
            }
            persist()
        }
        self.backend.onAction = { [weak self] action in self?.perform(action) }
    }

    func connect(actions: [ShortcutAction: () -> Void]) {
        self.actions = actions
        guard !connected else { return }
        connected = true
        registerAll()
    }

    func perform(_ action: ShortcutAction) {
        guard connected, recordingAction == nil, bindings[action] != nil, activeActions.contains(action) else { return }
        actions[action]?()
    }

    func beginRecording(_ action: ShortcutAction) {
        recordingAction = action
        activeActions.removeAll()
        issues[action] = nil
        for item in ShortcutAction.allCases { backend.unregister(item) }
    }

    func endRecording(_ action: ShortcutAction? = nil) {
        if let action, recordingAction != action { return }
        guard recordingAction != nil else { return }
        recordingAction = nil
        if connected { registerAll() }
    }

    /// Validate before saving. A rejected assignment leaves the previous binding intact.
    @discardableResult
    func assign(_ binding: KeyboardShortcutBinding?, to action: ShortcutAction) -> ShortcutIssue? {
        if let binding {
            guard binding.isValid else { issues[action] = .invalid; return .invalid }
            guard !bindings.contains(where: { $0.key != action && $0.value.hasSameKeys(as: binding) }) else {
                issues[action] = .duplicate; return .duplicate
            }
            let previous = bindings[action]
            backend.unregister(action)
            guard backend.register(binding, for: action) else {
                if recordingAction == nil, let previous {
                    if backend.register(previous, for: action) { activeActions.insert(action) }
                    else { activeActions.remove(action) }
                }
                issues[action] = .unavailable
                return .unavailable
            }
            backend.unregister(action)
            bindings[action] = binding
        } else { bindings.removeValue(forKey: action); backend.unregister(action) }
        issues[action] = nil
        persist()
        if recordingAction == nil, connected { registerAll() }
        return nil
    }

    private func registerAll() {
        activeActions.removeAll()
        for action in ShortcutAction.allCases {
            backend.unregister(action)
            issues[action] = nil
            if let binding = bindings[action] {
                if backend.register(binding, for: action) { activeActions.insert(action) }
                else { issues[action] = .unavailable }
            }
        }
    }

    private func persist() {
        let saved = Dictionary(uniqueKeysWithValues: bindings.map { ($0.key.rawValue, $0.value) })
        defaults.set(try? JSONEncoder().encode(saved), forKey: Self.preferenceKey)
    }
}
