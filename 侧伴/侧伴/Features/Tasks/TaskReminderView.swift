import SidebarCore
import SwiftUI

struct TaskReminderView: View {
    @AppStorage(AppLanguage.preferenceKey) private var interfaceLanguage = "system"
    let task: TaskItem
    var setReminder: (Date?) -> Void
    @State private var showingEditor = false
    @State private var reminderDate = Date().addingTimeInterval(3600)
    @State private var validation: String?

    var body: some View {
        Button {
            reminderDate = max(task.reminderAt ?? Date().addingTimeInterval(3600), Date().addingTimeInterval(60))
            validation = nil
            showingEditor = true
        } label: {
            Image(systemName: task.reminderAt == nil ? "bell" : "bell.badge.fill")
                .foregroundStyle(task.reminderAt == nil ? Color.secondary : Color.accentColor)
        }.buttonStyle(.plain).disabled(task.isCompleted)
            .help(task.reminderAt.map { L10n.text("提醒：{0}", String(describing: $0.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(AppLanguage.current().locale)))) } ?? L10n.text("设置提醒时间"))
            .accessibilityLabel(L10n.text("设置待办提醒"))
            .popover(isPresented: $showingEditor) {
                VStack(alignment: .leading, spacing: 14) {
                    Text(L10n.text("待办提醒")).font(.headline)
                    Text(task.title).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    HStack(spacing: 8) {
                        Button(L10n.text("10 分钟后")) { reminderDate = .now.addingTimeInterval(600) }
                        Button(L10n.text("1 小时后")) { reminderDate = .now.addingTimeInterval(3600) }
                    }.controlSize(.small)
                    DatePicker(L10n.text("提醒时间"), selection: $reminderDate, displayedComponents: [.date, .hourAndMinute])
                        .datePickerStyle(.field)
                    if let validation { Text(validation).font(.caption).foregroundStyle(.red) }
                    HStack {
                        if task.reminderAt != nil {
                            Button(L10n.text("移除提醒"), role: .destructive) { setReminder(nil); showingEditor = false }
                        }
                        Spacer()
                        Button(L10n.text("取消")) { showingEditor = false }
                        Button(L10n.text("保存")) {
                            guard reminderDate > .now else { validation = L10n.text("请选择未来的提醒时间。"); return }
                            setReminder(reminderDate)
                            showingEditor = false
                        }.keyboardShortcut(.defaultAction)
                    }
                }.padding(16).frame(width: 320)
            }
    }
}
