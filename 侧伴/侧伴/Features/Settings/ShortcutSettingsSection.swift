import SwiftUI
import AppKit
import SidebarCore

extension ShortcutAction {
    var title: String {
        switch self {
        case .focus: L10n.text("开始 / 暂停专注")
        case .recording: L10n.text("开始 / 结束录音")
        case .sidebar: L10n.text("快速打开侧边栏")
        }
    }
}

extension KeyboardShortcutBinding {
    var displayTitle: String { modifiers.symbols + (keyLabel == "Space" ? L10n.text("空格") : keyLabel) }

    init(event: NSEvent) {
        var modifiers: ShortcutModifiers = []
        if event.modifierFlags.contains(.command) { modifiers.insert(.command) }
        if event.modifierFlags.contains(.control) { modifiers.insert(.control) }
        if event.modifierFlags.contains(.option) { modifiers.insert(.option) }
        if event.modifierFlags.contains(.shift) { modifiers.insert(.shift) }
        let special: [UInt16: String] = [36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 53: "⎋", 76: "⌤", 117: "⌦",
                                       123: "←", 124: "→", 125: "↓", 126: "↑", 115: "↖", 119: "↘", 116: "⇞", 121: "⇟",
                                       122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12"]
        let characters = (event.charactersIgnoringModifiers ?? "").uppercased()
        let printable = characters.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }.map(String.init).joined()
        self.init(keyCode: UInt32(event.keyCode), modifiers: modifiers,
                  keyLabel: special[event.keyCode] ?? (printable.isEmpty ? "Key \(event.keyCode)" : printable))
    }
}

struct ShortcutSettingsSection: View {
    @AppStorage(AppLanguage.preferenceKey) private var interfaceLanguage = "system"
    @Environment(ShortcutManager.self) private var shortcuts

    var body: some View {
        Section(L10n.text("快捷键")) {
            ForEach(ShortcutAction.allCases) { action in
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text(action.title).font(.subheadline)
                        Spacer(minLength: 4)
                        ShortcutCaptureButton(action: action, shortcuts: shortcuts)
                            .frame(width: 128, height: 28)
                        Button {
                            _ = shortcuts.assign(nil, to: action)
                            shortcuts.endRecording()
                        } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                            .buttonStyle(.plain).disabled(shortcuts.bindings[action] == nil)
                            .help(L10n.text("清除快捷键"))
                            .accessibilityLabel(L10n.text("清除{0}快捷键", action.title))
                    }
                    if let issue = shortcuts.issues[action] {
                        Text(issue.message).font(.caption).foregroundStyle(.orange)
                    }
                }.padding(.vertical, 3)
            }
            Text(L10n.text("点击输入框后按下组合键，松开按键保存。Esc 取消，Delete 清除。应用运行时全局生效，无需辅助功能权限；与系统或其他应用冲突时请重新设置。"))
                .font(.caption).foregroundStyle(.secondary)
        }
        .onDisappear { shortcuts.endRecording() }
    }
}

private struct ShortcutCaptureButton: NSViewRepresentable {
    let action: ShortcutAction
    let shortcuts: ShortcutManager

    func makeNSView(context: Context) -> RecordingButton { RecordingButton() }

    func updateNSView(_ button: RecordingButton, context: Context) {
        button.savedTitle = shortcuts.bindings[action]?.displayTitle ?? L10n.text("点击录入")
        button.setAccessibilityLabel(action.title)
        button.toolTip = L10n.text("点击后按下你想使用的组合键")
        button.onBegin = { shortcuts.beginRecording(action) }
        button.onCommit = { binding in shortcuts.assign(binding, to: action) }
        button.onEnd = { shortcuts.endRecording(action) }
        if button.isRecording, shortcuts.recordingAction != action { button.finish(notify: false) }
        if !button.isRecording { button.title = button.savedTitle }
    }

    static func dismantleNSView(_ button: RecordingButton, coordinator: ()) { button.finish() }

    final class RecordingButton: NSButton {
        var savedTitle = ""
        var onBegin: (() -> Void)?
        var onCommit: ((KeyboardShortcutBinding?) -> ShortcutIssue?)?
        var onEnd: (() -> Void)?
        private(set) var isRecording = false
        private var pending: KeyboardShortcutBinding?
        private var monitor: Any?
        override var acceptsFirstResponder: Bool { true }

        init() {
            super.init(frame: .zero)
            bezelStyle = .rounded
            font = .monospacedSystemFont(ofSize: 11, weight: .medium)
            target = self
            action = #selector(startRecording)
            setAccessibilityRole(.button)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

        @objc private func startRecording() {
            guard !isRecording, let window, window.makeFirstResponder(self) else { return }
            isRecording = true
            pending = nil
            onBegin?()
            title = L10n.text("请按快捷键…")
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { [weak self] event in
                guard let self, self.isRecording, event.window === self.window else { return event }
                if event.type == .flagsChanged { return event }
                if event.type == .keyDown {
                    if event.isARepeat { return nil }
                    let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
                    if event.keyCode == 53, modifiers.isEmpty { self.finish(); return nil }
                    if event.keyCode == 48, modifiers.isEmpty { self.finish(); return event }
                    if [51, 117].contains(event.keyCode), modifiers.isEmpty {
                        _ = self.onCommit?(nil)
                        self.finish()
                        return nil
                    }
                    let binding = KeyboardShortcutBinding(event: event)
                    self.pending = binding
                    self.title = binding.displayTitle
                    return nil
                }
                if let binding = self.pending, UInt32(event.keyCode) == binding.keyCode {
                    self.pending = nil
                    if self.onCommit?(binding) == nil { self.finish() }
                    else { self.title = L10n.text("请重新录入…") }
                    return nil
                }
                return event
            }
        }

        func finish(notify: Bool = true) {
            guard isRecording else { return }
            isRecording = false
            pending = nil
            if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
            if notify { onEnd?() }
            title = savedTitle
        }

        override func resignFirstResponder() -> Bool {
            finish()
            return super.resignFirstResponder()
        }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window == nil { finish() }
        }
        deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
    }
}
