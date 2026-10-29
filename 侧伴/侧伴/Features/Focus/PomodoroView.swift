import SidebarCore
import SwiftUI
import AppKit

struct PomodoroView: View {
    @AppStorage(AppLanguage.preferenceKey) private var interfaceLanguage = "system"
    var isCompact = false
    @Environment(WorkspaceStore.self) private var workspace
    @Environment(ShortcutManager.self) private var shortcuts
    private var timer: PomodoroTimer { workspace.timer }
    private var focusDuration: Int {
        get { timer.focusDuration }
        nonmutating set { timer.focusDuration = newValue }
    }
    private var breakDuration: Int {
        get { timer.breakDuration }
        nonmutating set { timer.breakDuration = newValue }
    }
    private var isBreak: Bool {
        get { timer.isBreak }
        nonmutating set { timer.selectMode(isBreak: newValue) }
    }
    private var hasStarted: Bool { timer.hasStarted }
    private var deadline: Date? { timer.deadline }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let seconds = timer.seconds()
            Group {
                if isCompact {
                    compactTimer(seconds: seconds)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(L10n.text("番茄钟"), systemImage: "timer").font(.subheadline.weight(.medium))
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 0) {
                                Spacer(minLength: 0)
                                durationRow(isBreak: false, seconds: isBreak ? focusDuration : seconds)
                                Spacer(minLength: 12)
                                durationRow(isBreak: true, seconds: isBreak ? seconds : breakDuration)
                            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading).layoutPriority(1)
                            VStack(spacing: 10) {
                                Button {
                                    NSApp.keyWindow?.makeFirstResponder(nil)
                                    toggle()
                                } label: {
                                    Image(systemName: deadline == nil ? "play.fill" : "pause.fill")
                                        .frame(width: 20, height: 28)
                                }.buttonStyle(.borderedProminent).controlSize(.small)
                                    .help(L10n.text("{0}（{1}）", String(describing: deadline == nil ? L10n.text("开始 / 继续") : L10n.text("暂停")), String(describing: shortcuts.bindings[.focus]?.displayTitle ?? L10n.text("未设置"))))
                                    .accessibilityLabel(deadline == nil ? L10n.text("开始计时") : L10n.text("暂停计时"))
                                Button { reset() } label: {
                                    Image(systemName: "arrow.counterclockwise").frame(width: 20, height: 28)
                                }.controlSize(.small).help(L10n.text("重置计时")).accessibilityLabel(L10n.text("重置计时"))
                            }
                        }
                    }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(14).frame(height: 164, alignment: .top).card()
                }
            }

        }
        .onChange(of: isCompact) { _, compact in
            if compact && !hasStarted { isBreak = false }
        }
    }

    private func compactTimer(seconds: Int) -> some View {
        HStack(spacing: 6) {
            Image(systemName: isBreak ? "cup.and.saucer.fill" : "timer").foregroundStyle(Color.accentColor)
            Text(String(format: "%02d:%02d", seconds / 60, seconds % 60))
                .monospacedDigit().fontWeight(.semibold).lineLimit(1).minimumScaleFactor(0.8)
            Button {
                NSApp.keyWindow?.makeFirstResponder(nil)
                toggle()
            } label: {
                Image(systemName: deadline == nil ? "play.fill" : "pause.fill")
            }.buttonStyle(.plain).accessibilityLabel(deadline == nil ? L10n.text("开始计时") : L10n.text("暂停计时"))
        }.font(.caption).frame(maxWidth: .infinity).padding(.horizontal, 10).frame(height: 44).card()
            .help(hasStarted ? L10n.text("番茄钟当前倒计时") : L10n.text("专注时间，点击开始"))
    }

    private func durationRow(isBreak rowIsBreak: Bool, seconds: Int) -> some View {
        HStack(alignment: .center, spacing: 7) {
            Button {
                guard !hasStarted else { return }
                isBreak = rowIsBreak
            } label: {
                Image(systemName: rowIsBreak ? "cup.and.saucer.fill" : "flame.fill")
                    .font(.system(size: rowIsBreak ? 12 : 15, weight: .medium))
                    .foregroundStyle(isBreak == rowIsBreak ? Color.accentColor : Color.secondary)
                    .frame(width: 18, height: rowIsBreak ? 22 : 38)
            }.buttonStyle(.plain)
                .accessibilityLabel(rowIsBreak ? L10n.text("选择休息") : L10n.text("选择专注"))
                .help(hasStarted ? L10n.text("重置后可切换模式") : L10n.text("选择{0}", String(describing: rowIsBreak ? L10n.text("休息") : L10n.text("专注"))))
            HStack(spacing: 0) {
                digit(seconds / 60, part: DurationPart(isBreak: rowIsBreak, isSeconds: false))
                Text(":")
                digit(seconds % 60, part: DurationPart(isBreak: rowIsBreak, isSeconds: true))
            }.font(.system(size: rowIsBreak ? 18 : 38, weight: rowIsBreak ? .regular : .bold, design: .rounded)).monospacedDigit()
                .foregroundStyle(rowIsBreak && !isBreak ? .secondary : .primary)
                .fixedSize(horizontal: true, vertical: false)
        }.fixedSize(horizontal: true, vertical: false)
    }

    private func digit(_ value: Int, part: DurationPart) -> some View {
        InlineTimeDigit(
            value: value,
            isSeconds: part.isSeconds,
            isEditable: !hasStarted,
            isCompact: part.isBreak,
            onCommit: { value in
                let old = part.isBreak ? breakDuration : focusDuration
                let updated = part.isSeconds ? old / 60 * 60 + value : value * 60 + old % 60
                guard updated > 0 else { NSSound.beep(); return }
                if part.isBreak { breakDuration = updated } else { focusDuration = updated }
            }
        )
    }

    private func toggle() { timer.toggle() }
    private func reset() { timer.reset() }

}

private struct DurationPart {
    let isBreak: Bool
    let isSeconds: Bool
}

/// Edits the digit in place, retaining its size and typography.
private struct InlineTimeDigit: View {
    @AppStorage(AppLanguage.preferenceKey) private var interfaceLanguage = "system"
    let value: Int
    let isSeconds: Bool
    let isEditable: Bool
    let isCompact: Bool
    var onCommit: (Int) -> Void
    @State private var editing = false
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        Group {
            if editing {
                TextField("", text: $draft)
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.center)
                    .focused($focused)
                    .onSubmit { finish() }
                    .onExitCommand { finish(cancelled: true) }
                    .onChange(of: focused) { _, focused in
                        if !focused { finish() }
                    }
                    .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(Color.accentColor).frame(height: 1)
                    }
            } else {
                Text(String(format: "%02d", value))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2, perform: begin)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction(named: L10n.text("修改时长"), begin)
            }
        }
        .frame(width: digitWidth)
        .help(isEditable ? L10n.text("双击原位修改，回车保存，Esc 取消") : L10n.text("重置后可编辑时长"))
        .accessibilityLabel(isSeconds ? L10n.text("秒数") : L10n.text("分钟"))
    }

    private var digitWidth: CGFloat {
        CGFloat(max(2, editing ? min(3, draft.count) : String(value).count)) * (isCompact ? 12 : 24)
    }

    private func begin() {
        guard isEditable else { return }
        draft = String(format: "%02d", value)
        editing = true
        focused = true
    }

    private func finish(cancelled: Bool = false) {
        guard editing else { return }
        if !cancelled {
            if let number = Int(draft), (0...(isSeconds ? 59 : 180)).contains(number) {
                onCommit(number)
            } else {
                // Invalid entries restore the previous value without interrupting with a dialog.
                NSSound.beep()
            }
        }
        editing = false
        focused = false
    }
}

