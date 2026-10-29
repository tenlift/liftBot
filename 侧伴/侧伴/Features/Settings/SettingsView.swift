import SidebarCore
import SwiftUI

struct SettingsView: View {
    @AppStorage(AppLanguage.preferenceKey) private var interfaceLanguage = "system"
    @Environment(WorkspaceStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @AppStorage("appearanceMode") private var appearanceMode = "system"
    @AppStorage("speechLanguage") private var speechLanguage = "zh-CN"

    var body: some View {
        @Bindable var store = self.store
        @Bindable var storage = store.storage
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text(L10n.text("设置")).font(.title2.weight(.semibold))
                Spacer()
                Button(L10n.text("完成")) { dismiss() }.keyboardShortcut(.defaultAction)
            }
            Form {
                Section(L10n.text("语言")) {
                    Picker(L10n.text("界面语言"), selection: $interfaceLanguage) {
                        Text(L10n.text("跟随系统")).tag("system")
                        Text("简体中文").tag("zh-Hans")
                        Text("English").tag("en")
                    }
                    Text(L10n.text("切换立即生效，不会更改笔记内容或语音识别语言。"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section(L10n.text("外观")) {
                    Picker(L10n.text("界面主题"), selection: $appearanceMode) {
                        Text(L10n.text("跟随系统")).tag("system")
                        Text(L10n.text("浅色")).tag("light")
                        Text(L10n.text("深色")).tag("dark")
                    }.pickerStyle(.segmented)
                }
                Section(L10n.text("通知提醒")) {
                    LabeledContent(L10n.text("通知状态")) {
                        Text(store.notifications.authorization == .allowed ? L10n.text("已允许") : L10n.text("尚未允许")).foregroundStyle(.secondary)
                    }
                    ViewThatFits(in: .horizontal) {
                        HStack { notificationButtons }
                        VStack(alignment: .leading, spacing: 8) { notificationButtons }
                    }
                    Text(L10n.text("待办到时、专注或休息结束时发送系统通知。暂停、重置计时，或完成、删除待办会取消对应提醒。声音与横幅遵循系统通知及专注模式设置。"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                ShortcutSettingsSection()
                Section(L10n.text("笔记保存方式")) {
                    Picker(L10n.text("录音完成后"), selection: $store.recordingNoteDestination) {
                        Text(L10n.text("当前笔记")).tag(NoteDestination.currentNote)
                        Text(L10n.text("新笔记")).tag(NoteDestination.newNote)
                    }.pickerStyle(.segmented)
                    Picker(L10n.text("拖入文件时"), selection: $store.fileDropNoteDestination) {
                        Text(L10n.text("当前笔记")).tag(NoteDestination.currentNote)
                        Text(L10n.text("新笔记")).tag(NoteDestination.newNote)
                    }.pickerStyle(.segmented)
                    Text(L10n.text("选择当前笔记会追加附件；选择新笔记会新建并切换。同次拖入的多个文件保存在同一页，录音转写始终追加到录音所在笔记。"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section(L10n.text("录音转文字")) {
                    Picker(L10n.text("识别语言"), selection: $speechLanguage) {
                        Text(L10n.text("普通话")).tag("zh-CN")
                        Text("English").tag("en-US")
                    }
                    Text(L10n.text("录音停止后按保存方式加入笔记并在本机转写。macOS 26 及以上优先使用新引擎，首次由系统下载语言模型，音频不会上传。旧系统需要启用对应语言的听写资源。失败时保留音频，可重试。"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section(L10n.text("节假日与调休")) {
                    Text(store.holidays.description).font(.caption)
                    Link(L10n.text("查看 2026 年官方安排"), destination: URL(string: HolidayCalendar.official2026)!)
                    Button(L10n.text("导入年度日历 JSON…")) { store.holidays.importCalendar() }
                    Text(L10n.text("当前内置 2026 年官方安排，离线可用。后续年份可导入更新；缺少年份时明确标注按双休估算。"))
                        .font(.caption).foregroundStyle(.secondary)
                    if let issue = store.holidays.issue { Text(issue).font(.caption).foregroundStyle(.orange) }
                }
                Section(L10n.text("本机附件存放位置")) {
                    ForEach([StorageLocations.Kind.files, .recordings], id: \.rawValue) { kind in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(kind == .files ? L10n.text("文件附件") : L10n.text("录音文件")).font(.subheadline)
                            Text(storage.label(kind)).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                            HStack {
                                Button(L10n.text("选择目录…")) { storage.select(kind); store.audio.reload() }
                                Button(L10n.text("恢复默认")) { storage.useDefault(kind); store.audio.reload() }
                            }.disabled(kind == .recordings && store.audio.isRecording)
                        }
                    }
                    Text(L10n.text("更改目录影响新附件；旧文件保留在原目录并继续可用。导入会复制文件，不移动原文件。"))
                        .font(.caption).foregroundStyle(.secondary)
                    if let issue = storage.issue { Text(issue).font(.caption).foregroundStyle(.orange) }
                }
                Section("Obsidian") {
                    LabeledContent(L10n.text("仓库位置")) {
                        Text(store.vaultName).foregroundStyle(.secondary).lineLimit(1)
                        Button(L10n.text("选择文件夹…")) { store.selectVault() }
                    }
                    if let url = store.vaultURL {
                        Text(url.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                    TextField(L10n.text("文件附件目录"), text: $storage.attachmentExportPath)
                    TextField(L10n.text("录音附件目录"), text: $storage.recordingExportPath)
                    Text(L10n.text("附件目录填写相对仓库根目录的路径，例如 Sidebar/Attachments。"))
                        .font(.caption).foregroundStyle(.secondary)
                    Text(L10n.text("请选择 Obsidian 仓库的根目录。Note 只保存笔记正文到 Sidebar；待办通过独立按钮保存到 Sidebar/Tasks。每次保存生成新文件。"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section(L10n.text("关于这份预览")) {
                    Text(L10n.text("待办与速记自动保存在本机。番茄钟支持专注和短休息；录音停止后自动保存在本机，可在录音记录中回放或保存到 Obsidian。"))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.formStyle(.grouped).scrollContentBackground(.hidden)
        }.padding(20).frame(width: 390, height: 620)
            .background { SidebarSurface().ignoresSafeArea() }
            .onChange(of: appearanceMode) { _, mode in
                NSApp.appearance = mode == "system" ? nil : NSAppearance(named: mode == "dark" ? .darkAqua : .aqua)
            }
            .task { await store.notifications.refreshAuthorization() }
    }

    @ViewBuilder private var notificationButtons: some View {
        Button(L10n.text("启用通知")) { store.notifications.enable() }
        Button(L10n.text("系统通知设置…")) {
            if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
                NSWorkspace.shared.open(url)
            }
        }
    }

}
