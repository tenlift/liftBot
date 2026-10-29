import SidebarCore
import SwiftUI

struct WeeklyRestView: View {
    @AppStorage(AppLanguage.preferenceKey) private var interfaceLanguage = "system"
    @Environment(WorkspaceStore.self) private var store
    @State private var showingWeek = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let summary = store.holidays.summary(at: context.date)
            Button { showingWeek.toggle() } label: {
                Text(summary.text).font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1).minimumScaleFactor(0.8)
            }.buttonStyle(.plain).help(L10n.text("查看本周节假日和调休安排"))
                .popover(isPresented: $showingWeek) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(summary.text).font(.headline)
                        Text(L10n.text("中国大陆 · 周一至周日 · 按日历天计算")).font(.caption).foregroundStyle(.secondary)
                        ForEach(summary.days) { day in
                            HStack {
                                Text(day.weekday).frame(width: 30, alignment: .leading)
                                Text(day.date, format: .dateTime.month().day()).frame(width: 60, alignment: .leading)
                                Spacer()
                                Text(day.detail).foregroundStyle(day.isOff ? Color.green : Color.secondary)
                            }.font(.caption)
                        }
                        if summary.isEstimated {
                            Text(L10n.text("本周涉及未载入年份，暂按周末双休估算，尚未计入该年的法定假日及调休。"))
                                .font(.caption).foregroundStyle(.orange)
                        }
                        Link(L10n.text("2026 年官方安排"), destination: URL(string: HolidayCalendar.official2026)!).font(.caption)
                    }.padding(16).frame(width: 310)
                }
        }
    }
}
