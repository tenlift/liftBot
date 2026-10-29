import SidebarCore
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @AppStorage(AppLanguage.preferenceKey) private var interfaceLanguage = "system"
    @Environment(WorkspaceStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @Environment(SidebarWindowController.self) private var windowController
    @AppStorage("appearanceMode") private var appearanceMode = "system"
    @State private var dropTargeted = false
    @State private var showingSettings = false
    @State private var notesExpanded = false
    @State private var taskDraft = ""
    @AppStorage("taskPaneRatio") private var taskPaneRatio = 0.28
    @State private var dragStartHeight: CGFloat?
    @State private var dividerHovered = false

    var body: some View {
        @Bindable var store = store
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.text("侧伴")).font(.system(size: 25, weight: .bold, design: .rounded))
                    WeeklyRestView()
                }
                Spacer()
                Button { windowController.isPinned.toggle() } label: {
                    Image(systemName: windowController.isPinned ? "pin.fill" : "pin")
                        .foregroundStyle(windowController.isPinned ? Color.accentColor : Color.secondary)
                }.buttonStyle(.plain).help(windowController.isPinned ? L10n.text("取消窗口置顶") : L10n.text("窗口置顶"))
                    .accessibilityLabel(windowController.isPinned ? L10n.text("取消窗口置顶") : L10n.text("窗口置顶"))
                Button { windowController.collapse() } label: { Image(systemName: "sidebar.right") }
                    .buttonStyle(.plain).foregroundStyle(.secondary).help(L10n.text("靠边收起，点击边缘标识可恢复"))
                    .accessibilityLabel(L10n.text("靠边收起"))
                    .contextMenu {
                        Toggle(L10n.text("靠边自动收起"), isOn: Binding(get: { windowController.autoCollapse }, set: { windowController.autoCollapse = $0 }))
                        Button(L10n.text("吸附左侧并收起")) { windowController.collapse(toward: .left) }
                        Button(L10n.text("吸附右侧并收起")) { windowController.collapse(toward: .right) }
                        if windowController.dockedEdge != nil { Button(L10n.text("取消吸附")) { windowController.undock() } }
                    }
                Button { showingSettings = true } label: { Image(systemName: "gearshape").font(.title3) }
                    .buttonStyle(.plain).foregroundStyle(.secondary).help(L10n.text("设置"))
                    .accessibilityLabel(L10n.text("打开设置"))
            }.padding(.leading, 64).padding(.trailing, 2)

            // Keep these view identities in place so expanding Note never resets a timer or recording.
            HStack(alignment: .top, spacing: notesExpanded ? 8 : 12) {
                PomodoroView(isCompact: notesExpanded).frame(maxWidth: .infinity)
                RecordingView(isCompact: notesExpanded)
                if notesExpanded {
                    Label(L10n.text("待办 {0}", String(describing: store.tasks.filter { !$0.isCompleted }.count)), systemImage: "checklist")
                        .font(.caption).lineLimit(1).padding(.horizontal, 10).frame(height: 44).card()
                        .accessibilityLabel(L10n.text("待办事项，{0} 项未完成", String(describing: store.tasks.filter { !$0.isCompleted }.count)))
                }
            }


            if let issue = store.notifications.issue {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "bell.slash").foregroundStyle(.orange)
                    Text(issue).font(.caption).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Button(L10n.text("设置")) { showingSettings = true }.controlSize(.mini)
                }
            }

            GeometryReader { geometry in
                let available = max(0, geometry.size.height - 16)
                let taskHeight = clampedTaskHeight(available * taskPaneRatio, available: available)
                VStack(spacing: 0) {
                    if !notesExpanded {
                        taskSection.frame(height: taskHeight)
                        Capsule()
                            .fill(dividerHovered || dragStartHeight != nil ? Color.accentColor : Color.secondary.opacity(0.3))
                            .frame(width: 36, height: 4)
                            .frame(maxWidth: .infinity).frame(height: 16)
                            .contentShape(Rectangle())
                            .onHover { dividerHovered = $0 }
                            .overlay {
                                PaneResizeHandle(onResize: { translation, ended in
                                    if dragStartHeight == nil { dragStartHeight = taskHeight }
                                    let height = clampedTaskHeight((dragStartHeight ?? taskHeight) + translation, available: available)
                                    taskPaneRatio = Double(height / max(1, available))
                                    if ended { dragStartHeight = nil }
                                }, onReset: { taskPaneRatio = 0.28; dragStartHeight = nil })
                            }
                            .help(L10n.text("上下拖动，调整待办与笔记的大小；双击恢复默认"))
                            .accessibilityLabel(L10n.text("调整待办与笔记大小"))
                            .accessibilityAdjustableAction { direction in
                                let delta: Double = direction == .increment ? 0.05 : -0.05
                                taskPaneRatio = Double(clampedTaskHeight(available * (taskPaneRatio + delta), available: available) / max(1, available))
                            }
                    }
                    NotesView(isExpanded: $notesExpanded)
                        .frame(maxHeight: .infinity, alignment: .top)
                }.coordinateSpace(name: "panes")
            }

            HStack(spacing: 6) {
                Circle().fill(store.vaultURL == nil ? Color.secondary : Color.green).frame(width: 5, height: 5)
                Text(store.vaultURL == nil ? L10n.text("连接 Obsidian，让记录有处可去") : "Obsidian · \(store.vaultName)")
                Spacer()
            }.font(.caption2).foregroundStyle(.secondary).padding(.horizontal, 3)
        }
        // Place the header beside the traffic lights instead of reserving an empty strip.
        .padding(.horizontal, 20).padding(.bottom, 20).padding(.top, 8).frame(minWidth: 420, idealWidth: 420, maxWidth: 520, minHeight: 620, idealHeight: 800, maxHeight: .infinity, alignment: .topLeading)
        .background { SidebarSurface().ignoresSafeArea() }
        .background(SidebarWindowAccessor(controller: windowController).frame(width: 0, height: 0))
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $dropTargeted) { store.receiveFiles($0) }
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 16).strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [8]))
                    .overlay {
                        Label(store.fileDropNoteDestination == .currentNote ? L10n.text("松开以添加到当前笔记") : L10n.text("松开以新建笔记并添加文件"), systemImage: "paperclip")
                            .padding(14).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                    }.padding(8).allowsHitTesting(false)
            }
        }
        .onAppear { applyAppearance() }
        .onChange(of: appearanceMode) { _, _ in applyAppearance() }
        .task { await store.notifications.refreshAuthorization() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await store.notifications.refreshAuthorization() } }
        }
        .sheet(isPresented: $showingSettings) { SettingsView() }
        .alert(L10n.text("保存提示"), isPresented: Binding(get: { store.message != nil }, set: { if !$0 { store.message = nil } })) {
            Button(L10n.text("好"), role: .cancel) { store.message = nil }
        } message: { Text(store.message ?? "") }
    }

    private func clampedTaskHeight(_ height: CGFloat, available: CGFloat) -> CGFloat {
        let maximum = max(124, available - 200)
        return min(max(124, height), maximum)
    }

    private var taskSection: some View {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label(L10n.text("待办事项"), systemImage: "checklist").font(.headline)
                        Button { store.exportTasks() } label: { Image(systemName: "arrow.up.doc") }
                            .buttonStyle(.plain).foregroundStyle(.secondary).disabled(store.tasks.isEmpty)
                            .help(L10n.text("将待办单独保存到 Obsidian")).accessibilityLabel(L10n.text("将待办单独保存到 Obsidian"))
                        Spacer()
                        Text(L10n.text("{0} 项待完成", String(describing: store.tasks.filter { !$0.isCompleted }.count)))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    HStack {
                        Image(systemName: "plus").foregroundStyle(.secondary)
                        TextField(L10n.text("添加待办，按回车确认"), text: $taskDraft).textFieldStyle(.plain).onSubmit(addTask)
                        if !taskDraft.trimmingCharacters(in: .whitespaces).isEmpty {
                            Button(action: addTask) { Image(systemName: "arrow.turn.down.left") }.buttonStyle(.plain).help(L10n.text("添加待办"))
                        }
                    }.padding(10).background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
                    if store.tasks.isEmpty {
                        Text(L10n.text("把脑海里的事，先放在这里"))
                            .font(.caption).foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(store.tasks) { task in
                                    HStack(spacing: 10) {
                                        Button { store.updateTask(id: task.id) { $0.isCompleted.toggle() } } label: {
                                            Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                                                .foregroundStyle(task.isCompleted ? Color.accentColor : Color.secondary)
                                        }.buttonStyle(.plain).accessibilityLabel(task.isCompleted ? L10n.text("标为未完成") : L10n.text("完成待办"))
                                        VStack(alignment: .leading, spacing: 3) {
                                            TextField(L10n.text("待办内容"), text: Binding(
                                                get: { store.tasks.first { $0.id == task.id }?.title ?? task.title },
                                                set: { title in store.updateTask(id: task.id) { $0.title = title } }
                                            )).textFieldStyle(.plain)
                                                .strikethrough(task.isCompleted).foregroundStyle(task.isCompleted ? .secondary : .primary)
                                            if let reminder = task.reminderAt, !task.isCompleted {
                                                Text(reminder, format: .dateTime.month().day().hour().minute())
                                                    .font(.caption2).foregroundStyle(reminder < .now ? Color.orange : Color.secondary)
                                            }
                                        }
                                        TaskReminderView(task: task) { date in
                                            store.updateTask(id: task.id) { $0.reminderAt = date }
                                        }
                                        Button { store.removeTask(id: task.id) } label: { Image(systemName: "xmark").font(.caption2) }
                                            .buttonStyle(.plain).foregroundStyle(.tertiary).help(L10n.text("删除待办"))
                                    }.padding(.vertical, 9)
                                }
                            }
                        }
                        .frame(maxHeight: .infinity, alignment: .top)
                    }
                }.padding(16)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).card()
    }

    private func applyAppearance() {
        NSApp.appearance = appearanceMode == "system" ? nil : NSAppearance(named: appearanceMode == "dark" ? .darkAqua : .aqua)
    }

    private func addTask() {
        let title = taskDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        store.tasks.append(TaskItem(title: title))
        taskDraft = ""
    }
}

/// Native mouse tracking keeps resize drags separate from AppKit window dragging.
private struct PaneResizeHandle: NSViewRepresentable {
    @AppStorage(AppLanguage.preferenceKey) private var interfaceLanguage = "system"
    var onResize: (CGFloat, Bool) -> Void
    var onReset: () -> Void
    func makeNSView(context: Context) -> ResizeView { ResizeView() }
    func updateNSView(_ view: ResizeView, context: Context) {
        view.onResize = onResize
        view.onReset = onReset
    }
    final class ResizeView: NSView {
        var onResize: ((CGFloat, Bool) -> Void)?
        var onReset: (() -> Void)?
        private var startY: CGFloat?
        override var mouseDownCanMoveWindow: Bool { false }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func resetCursorRects() { addCursorRect(bounds, cursor: .resizeUpDown) }
        override func mouseDown(with event: NSEvent) {
            if event.clickCount == 2 { startY = nil; onReset?(); return }
            startY = event.locationInWindow.y
            onResize?(0, false)
        }
        override func mouseDragged(with event: NSEvent) {
            guard let startY else { return }
            onResize?(startY - event.locationInWindow.y, false)
        }
        override func mouseUp(with event: NSEvent) {
            guard let startY else { return }
            onResize?(startY - event.locationInWindow.y, true)
            self.startY = nil
        }
    }
}

private struct CardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.background { SidebarCardSurface() }
    }
}
extension View {
    func card() -> some View { modifier(CardModifier()) }
}

#Preview { ContentView().environment(WorkspaceStore()).environment(SidebarWindowController()).environment(ShortcutManager()) }
