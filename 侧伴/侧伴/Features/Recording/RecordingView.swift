import SidebarCore
import SwiftUI

struct RecordingView: View {
    @AppStorage(AppLanguage.preferenceKey) private var interfaceLanguage = "system"
    var isCompact = false
    @Environment(WorkspaceStore.self) private var workspace
    @State private var showingLibrary = false
    private var audio: RecordingStore { workspace.audio }

    var body: some View {
        Group {
            if isCompact { compactRecording } else {
                VStack(alignment: .leading, spacing: 8) {
                    Label(L10n.text("快捷录音"), systemImage: "waveform").font(.subheadline.weight(.medium))
                    Spacer(minLength: 0)
                    if audio.isRecording {
                        Text(duration(audio.elapsed)).font(.system(.title3, design: .rounded).monospacedDigit()).foregroundStyle(.red)
                            .frame(maxWidth: .infinity)
                    }
                    HStack(spacing: 3) {
                        ForEach(0..<13) { index in
                            Capsule().fill(audio.isRecording ? Color.red.opacity(0.75) : Color.secondary.opacity(0.22))
                                .frame(width: 3, height: audio.isRecording ? 5 + CGFloat(audio.level) * CGFloat([18, 30, 22, 36, 26, 32, 40, 28, 34, 24, 30, 20, 16][index]) : 6)
                        }
                    }.frame(maxWidth: .infinity, minHeight: 20, maxHeight: 28)
                        .animation(.easeOut(duration: 0.1), value: audio.level)
                    Spacer(minLength: 0)
                    Button {
                        if audio.isRecording { audio.stop() }
                        else { Task { await audio.start() } }
                    } label: {
                        Label(audio.isRecording ? L10n.text("停止") : (audio.isRequestingPermission ? L10n.text("授权中…") : L10n.text("开始录音")), systemImage: audio.isRecording ? "stop.fill" : "mic.fill")
                            .frame(maxWidth: .infinity)
                    }.controlSize(.small).tint(audio.isRecording ? .red : nil).disabled(audio.isRequestingPermission)
                    Button { showingLibrary = true } label: {
                        Text(audio.recordings.isEmpty ? L10n.text("录音记录") : L10n.text("录音记录 · {0}", String(describing: audio.recordings.count))).font(.caption2)
                            .frame(maxWidth: .infinity)
                    }.buttonStyle(.plain).foregroundStyle(.secondary)
                }.padding(14).frame(width: 124, height: 164).card()
            }
        }
            .sheet(isPresented: $showingLibrary) { library }
            .alert(L10n.text("录音提示"), isPresented: Binding(get: { audio.errorMessage != nil }, set: { if !$0 { audio.errorMessage = nil } })) {
                Button(L10n.text("好"), role: .cancel) { audio.errorMessage = nil }
            } message: { Text(audio.errorMessage ?? "") }
    }

    private var compactRecording: some View {
        Button {
            if audio.isRecording { audio.stop() }
            else { Task { await audio.start() } }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: audio.isRecording ? "stop.circle.fill" : "mic.fill")
                    .foregroundStyle(audio.isRecording ? Color.red : Color.secondary)
                Text(audio.isRecording ? L10n.text("录音 ") + duration(audio.elapsed) : (audio.isRequestingPermission ? L10n.text("授权中…") : L10n.text("开始录音")))
                    .monospacedDigit().lineLimit(1).minimumScaleFactor(0.8)
            }.font(.caption).frame(maxWidth: .infinity).padding(.horizontal, 10).frame(height: 44).card()
        }.buttonStyle(.plain).disabled(audio.isRequestingPermission)
            .help(audio.isRecording ? L10n.text("停止录音并转写到 Note") : L10n.text("开始录音"))
            .accessibilityLabel(audio.isRecording ? L10n.text("停止录音") : L10n.text("开始录音"))
    }

    private var library: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(L10n.text("录音记录")).font(.title2.weight(.semibold))
                Spacer()
                Button(L10n.text("完成")) { audio.stopPlayback(); showingLibrary = false }.keyboardShortcut(.defaultAction)
            }
            Text(L10n.text("停止后自动保存在本机。可回放，或将音频及引用笔记保存到 Obsidian。"))
                .font(.caption).foregroundStyle(.secondary)
            if audio.recordings.isEmpty {
                ContentUnavailableView(L10n.text("还没有录音"), systemImage: "mic", description: Text(L10n.text("点击开始录音，随手记录一个想法。")))
            } else {
                List(audio.recordings) { recording in
                    HStack(spacing: 8) {
                        Button { audio.play(recording) } label: {
                            Image(systemName: audio.playingID == recording.id ? "stop.circle.fill" : "play.circle.fill").font(.title2)
                        }.buttonStyle(.plain).disabled(audio.isRecording)
                            .help(audio.playingID == recording.id ? L10n.text("停止回放") : L10n.text("播放录音"))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(recording.createdAt, format: .dateTime.year().month().day().hour().minute().second())
                                .font(.subheadline).lineLimit(2)
                            Text(recording.url.lastPathComponent).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        Button { NSWorkspace.shared.activateFileViewerSelecting([recording.url]) } label: { Image(systemName: "folder") }.help(L10n.text("在 Finder 中显示"))
                        Button { workspace.exportRecording(recording) } label: { Image(systemName: "arrow.up.doc") }.help(L10n.text("保存到 Obsidian"))
                    }.padding(.vertical, 6)
                }.listStyle(.inset).scrollContentBackground(.hidden)
            }
        }.padding(20).frame(width: 390, height: 420)
            .background { SidebarSurface().ignoresSafeArea() }
            .onDisappear { audio.stopPlayback() }
            .alert(L10n.text("录音提示"), isPresented: Binding(get: { audio.errorMessage != nil }, set: { if !$0 { audio.errorMessage = nil } })) {
                Button(L10n.text("好"), role: .cancel) { audio.errorMessage = nil }
            } message: { Text(audio.errorMessage ?? "") }
            .alert(L10n.text("保存提示"), isPresented: Binding(get: { workspace.message != nil }, set: { if !$0 { workspace.message = nil } })) {
                Button(L10n.text("好"), role: .cancel) { workspace.message = nil }
            } message: { Text(workspace.message ?? "") }
    }

    private func duration(_ seconds: TimeInterval) -> String {
        let value = Int(seconds)
        return String(format: "%02d:%02d", value / 60, value % 60)
    }
}
