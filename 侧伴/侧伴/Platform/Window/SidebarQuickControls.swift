import SidebarCore
import SwiftUI

struct SidebarQuickControls: View {
    @AppStorage(AppLanguage.preferenceKey) private var interfaceLanguage = "system"
    let timer: PomodoroTimer
    let audio: RecordingStore
    var didAct: () -> Void
    var expand: () -> Void
    var dismiss: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(L10n.text("快捷控制")).font(.subheadline.weight(.semibold))
                    Spacer()
                    Button(action: expand) { Image(systemName: "arrow.up.left.and.arrow.down.right") }
                        .buttonStyle(.plain).help(L10n.text("展开侧栏")).accessibilityLabel(L10n.text("展开侧栏"))
                    Button(action: dismiss) { Image(systemName: "xmark").font(.caption) }
                        .buttonStyle(.plain).help(L10n.text("关闭快捷面板")).accessibilityLabel(L10n.text("关闭快捷面板"))
                }
                HStack(spacing: 9) {
                    Image(systemName: timer.isBreak ? "cup.and.saucer.fill" : "flame.fill")
                        .foregroundStyle(timer.isBreak ? Color.green : Color.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(timer.isBreak ? L10n.text("休息") : L10n.text("专注")).font(.caption).foregroundStyle(.secondary)
                        Text(time(timer.seconds())).font(.system(.title3, design: .rounded).weight(.semibold)).monospacedDigit()
                    }
                    Spacer()
                    Button(timer.isRunning ? L10n.text("暂停") : (timer.hasStarted && timer.seconds() > 0 ? L10n.text("继续") : L10n.text("开始"))) { timer.toggle(); didAct() }
                        .controlSize(.small)
                    if timer.hasStarted {
                        Button { timer.reset(); didAct() } label: { Image(systemName: "stop.fill") }
                            .controlSize(.small).help(L10n.text("结束计时")).accessibilityLabel(L10n.text("结束计时"))
                    }
                }
                if !timer.hasStarted {
                    HStack {
                        Spacer()
                        Button(timer.isBreak ? L10n.text("开始专注") : L10n.text("开始休息")) { timer.start(isBreak: !timer.isBreak); didAct() }
                            .buttonStyle(.plain).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Divider()
                HStack(spacing: 9) {
                    Image(systemName: "mic.fill").foregroundStyle(audio.isRecording ? Color.red : Color.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(audio.isRecording ? L10n.text("正在录音") : L10n.text("快捷录音")).font(.caption).foregroundStyle(.secondary)
                        Text(audio.isRecording ? time(Int(audio.elapsed)) : L10n.text("随时记录灵感"))
                            .font(.system(.caption, design: .rounded)).monospacedDigit()
                            .lineLimit(1).minimumScaleFactor(0.8)
                    }
                    Spacer()
                    Button(audio.isRecording ? L10n.text("停止") : L10n.text("开始")) {
                        if audio.isRecording { audio.stop(); didAct() }
                        else { Task { await audio.start(); didAct() } }
                    }.controlSize(.small).disabled(audio.isRequestingPermission)
                }
                if let error = audio.errorMessage {
                    Text(error).font(.caption2).foregroundStyle(.orange).lineLimit(2).help(error)
                }
            }.padding(12).frame(width: SidebarGeometry.quickControlsSize.width, height: SidebarGeometry.quickControlsSize.height, alignment: .topLeading)
                .background { SidebarSurface() }
        }.environment(\.locale, AppLanguage.current().locale)
    }
    private func time(_ seconds: Int) -> String { String(format: "%02d:%02d", seconds / 60, seconds % 60) }
}
