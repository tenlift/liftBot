import SidebarCore
import Foundation
import Observation
import AppKit
import UniformTypeIdentifiers

struct HolidayOverride: Codable {
    let date: String
    let isOff: Bool
    let name: String
}
struct HolidayYear: Codable {
    let year: Int
    let source: String
    let days: [HolidayOverride]
}
struct WeekDayStatus: Identifiable {
    let date: Date
    let weekday: String
    let isOff: Bool
    let detail: String
    var id: Date { date }
}
struct WeeklyRestSummary {
    let days: [WeekDayStatus]
    let restCount: Int
    let daysUntilFirstRest: Int?
    let isEstimated: Bool
    let todayIsOff: Bool
    var text: String {
        let suffix = isEstimated ? L10n.text("（估算）") : ""
        guard let distance = daysUntilFirstRest else { return L10n.text("本周无休息日") + suffix }
        if distance > 0 { return L10n.text("距本周首休还有 {0} 天 · 休 {1} 天", String(describing: distance), String(describing: restCount)) + suffix }
        if todayIsOff { return L10n.text("今天休息 · 本周休 {0} 天", String(describing: restCount)) + suffix }
        return L10n.text("本周首休已过 · 共休 {0} 天", String(describing: restCount)) + suffix
    }
}

@MainActor @Observable final class HolidayCalendar {
    private(set) var years: [HolidayYear]
    var issue: String?
    @ObservationIgnored private let defaults: UserDefaults
    static let official2026 = "https://www.beijing.gov.cn/cs/gncs/zcwj/202603/t20260327_4568275.html"
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        calendar.firstWeekday = 2
        return calendar
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        years = [Self.bundled2026]
        if let data = defaults.data(forKey: "holidayYears"), let saved = try? JSONDecoder().decode([HolidayYear].self, from: data) {
            for year in saved { years.removeAll { $0.year == year.year }; years.append(year) }
        }
    }
    var description: String { L10n.text("中国大陆 · 周一至周日 · 已载入 ") + years.map { String($0.year) }.sorted().joined(separator: "、") }

    func summary(at now: Date) -> WeeklyRestSummary {
        let calendar = Self.calendar
        let today = calendar.startOfDay(for: now)
        let offset = (calendar.component(.weekday, from: today) + 5) % 7
        let monday = calendar.date(byAdding: .day, value: -offset, to: today)!
        var estimated = false
        let days = (0..<7).map { index -> WeekDayStatus in
            let date = calendar.date(byAdding: .day, value: index, to: monday)!
            let year = years.first { $0.year == calendar.component(.year, from: date) }
            if year == nil { estimated = true }
            let key = Self.dateKey(date)
            let override = year?.days.first { $0.date == key }
            let weekend = calendar.isDateInWeekend(date)
            return WeekDayStatus(date: date, weekday: [L10n.text("周一"), L10n.text("周二"), L10n.text("周三"), L10n.text("周四"), L10n.text("周五"), L10n.text("周六"), L10n.text("周日")][index], isOff: override?.isOff ?? weekend, detail: override.map { $0.isOff ? L10n.text($0.name) : L10n.text("调休上班") } ?? (weekend ? L10n.text("周末休息") : L10n.text("工作日")))
        }
        let rest = days.filter(\.isOff)
        let distance = rest.first.map { calendar.dateComponents([.day], from: today, to: $0.date).day ?? 0 }
        return WeeklyRestSummary(days: days, restCount: rest.count, daysUntilFirstRest: distance, isEstimated: estimated, todayIsOff: days.first { calendar.isDate($0.date, inSameDayAs: today) }?.isOff ?? false)
    }

    func importCalendar() {
        let panel = NSOpenPanel()
        panel.title = L10n.text("导入年度节假日 JSON")
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size < 2_000_000 else { throw StorageLocations.StorageError(L10n.text("日历文件过大。")) }
            try importData(Data(contentsOf: url))
            issue = nil
        } catch { issue = L10n.text("日历导入失败：{0}", String(describing: error.localizedDescription)) }
    }

    func importData(_ data: Data) throws {
        let year = try JSONDecoder().decode(HolidayYear.self, from: data)
        guard (1900...2200).contains(year.year), !year.source.isEmpty, year.days.count <= 366,
              Set(year.days.map(\.date)).count == year.days.count,
              year.days.allSatisfy({ day in
                  guard let parsed = Self.parse(day.date) else { return false }
                  return Self.calendar.component(.year, from: parsed) == year.year
              }) else { throw StorageLocations.StorageError(L10n.text("日历年份、日期或来源不正确，或存在重复日期。")) }
        years.removeAll { $0.year == year.year }
        years.append(year)
        defaults.set(try JSONEncoder().encode(years), forKey: "holidayYears")
    }

    static func dateKey(_ date: Date) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year!, components.month!, components.day!)
    }
    static func parse(_ text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        guard let date = formatter.date(from: text), dateKey(date) == text else { return nil }
        return date
    }

    static var bundled2026: HolidayYear {
        // 国办发明电〔2025〕7号, published 2025-11-04. Other days follow a Monday–Friday workweek.
        let ranges = [("01-01", "01-03", "元旦"), ("02-15", "02-23", "春节"), ("04-04", "04-06", "清明节"), ("05-01", "05-05", "劳动节"), ("06-19", "06-21", "端午节"), ("09-25", "09-27", "中秋节"), ("10-01", "10-07", "国庆节")]
        var days: [HolidayOverride] = []
        for (start, end, name) in ranges {
            var date = parse("2026-" + start)!
            let last = parse("2026-" + end)!
            while date <= last {
                days.append(HolidayOverride(date: dateKey(date), isOff: true, name: name))
                date = calendar.date(byAdding: .day, value: 1, to: date)!
            }
        }
        for day in ["01-04", "02-14", "02-28", "05-09", "09-20", "10-10"] {
            days.append(HolidayOverride(date: "2026-" + day, isOff: false, name: "调休上班"))
        }
        return HolidayYear(year: 2026, source: official2026, days: days)
    }
}
