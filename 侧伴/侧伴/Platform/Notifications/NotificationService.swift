import SidebarCore
import Foundation
import UserNotifications
import Observation

struct ScheduledAlert: Equatable {
    let id: String
    let title: String
    let body: String
    let date: Date
}

enum NotificationAccess { case notDetermined, denied, allowed }

@MainActor protocol NotificationBackend {
    func access() async -> NotificationAccess
    func requestAccess() async throws -> Bool
    func pendingIDs() async -> [String]
    func add(_ alert: ScheduledAlert) async throws
    func remove(_ ids: [String])
    func removeDelivered(_ ids: [String])
}

@MainActor final class SystemNotificationBackend: NotificationBackend {
    private let center: UNUserNotificationCenter
    private let delegate = ForegroundNotificationDelegate()

    init() {
        center = .current()
        center.delegate = delegate
    }

    func access() async -> NotificationAccess {
        switch await center.notificationSettings().authorizationStatus {
        case .authorized, .provisional, .ephemeral: .allowed
        case .denied: .denied
        default: .notDetermined
        }
    }
    func requestAccess() async throws -> Bool { try await center.requestAuthorization(options: [.alert, .sound]) }
    func pendingIDs() async -> [String] { await center.pendingNotificationRequests().map(\.identifier) }
    func add(_ alert: ScheduledAlert) async throws {
        let content = UNMutableNotificationContent()
        content.title = alert.title
        content.body = alert.body
        content.sound = .default
        // Absolute calendar dates avoid postponing a reminder when unrelated text is edited.
        var calendar = Calendar.current
        calendar.timeZone = .current
        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: Date(timeIntervalSince1970: ceil(alert.date.timeIntervalSince1970)))
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        try await center.add(UNNotificationRequest(identifier: alert.id, content: content, trigger: trigger))
    }
    func remove(_ ids: [String]) { center.removePendingNotificationRequests(withIdentifiers: ids) }
    func removeDelivered(_ ids: [String]) { center.removeDeliveredNotifications(withIdentifiers: ids) }
}

private final class ForegroundNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }
}

/// Serial reconciliation makes complete/delete/pause win over an in-flight authorization or add.
@MainActor @Observable final class NotificationService {
    static let taskPrefix = "sidebar.task."
    static let timerID = "sidebar.pomodoro"
    private(set) var authorization = NotificationAccess.notDetermined
    private(set) var issue: String?
    private(set) var isSynchronizing = false
    @ObservationIgnored private let backend: any NotificationBackend
    @ObservationIgnored private var desired: [String: ScheduledAlert] = [:]
    @ObservationIgnored private var knownTaskIDs: Set<String> = []
    @ObservationIgnored private var managesTimer = false
    @ObservationIgnored private var timerIsBreak = false
    @ObservationIgnored private var revision = 0
    @ObservationIgnored private var askPermission = false

    init(backend: (any NotificationBackend)? = nil) { self.backend = backend ?? SystemNotificationBackend() }

    func updateTasks(_ tasks: [TaskItem], requestPermission: Bool = true) {
        let ids = Set(tasks.map { Self.taskPrefix + $0.id.uuidString })
        let inactive = Set(tasks.filter { $0.isCompleted || $0.reminderAt == nil }.map { Self.taskPrefix + $0.id.uuidString })
        backend.removeDelivered(Array(knownTaskIDs.subtracting(ids).union(inactive)))
        knownTaskIDs = ids
        desired = desired.filter { !$0.key.hasPrefix(Self.taskPrefix) }
        for task in tasks where !task.isCompleted {
            guard let date = task.reminderAt, date > .now else { continue }
            let id = Self.taskPrefix + task.id.uuidString
            desired[id] = ScheduledAlert(id: id, title: L10n.text("待办提醒"), body: task.title.isEmpty ? L10n.text("你有一项待办需要处理") : task.title, date: date)
        }
        synchronize(requestPermission: requestPermission && desired.keys.contains { $0.hasPrefix(Self.taskPrefix) })
    }

    func setPomodoro(deadline: Date?, isBreak: Bool) {
        timerIsBreak = isBreak
        managesTimer = true
        backend.removeDelivered([Self.timerID])
        if let deadline {
            desired[Self.timerID] = ScheduledAlert(id: Self.timerID, title: isBreak ? L10n.text("休息结束") : L10n.text("专注完成"), body: isBreak ? L10n.text("休息结束，准备开始下一轮专注吧。") : L10n.text("这一轮专注已完成，休息一下吧。"), date: deadline)
        } else { desired.removeValue(forKey: Self.timerID) }
        synchronize(requestPermission: deadline != nil)
    }

    /// Keep notification IDs and deadlines unchanged when replacing their translated copy.
    func refreshLanguage(tasks: [TaskItem]) {
        if let alert = desired[Self.timerID] {
            desired[Self.timerID] = ScheduledAlert(id: alert.id,
                title: timerIsBreak ? L10n.text("休息结束") : L10n.text("专注完成"),
                body: timerIsBreak ? L10n.text("休息结束，准备开始下一轮专注吧。") : L10n.text("这一轮专注已完成，休息一下吧。"),
                date: alert.date)
        }
        updateTasks(tasks, requestPermission: false)
    }

    func refreshAuthorization() async {
        authorization = await backend.access()
        synchronize(requestPermission: false)
    }

    func enable() { synchronize(requestPermission: true) }

    private func synchronize(requestPermission: Bool) {
        revision += 1
        askPermission = askPermission || requestPermission
        guard !isSynchronizing else { return }
        isSynchronizing = true
        Task {
            defer { self.isSynchronizing = false }
            var processed = -1
            while processed != self.revision {
                let version = self.revision
                let shouldAsk = self.askPermission
                self.askPermission = false
                do {
                    self.authorization = await self.backend.access()
                    if shouldAsk && self.authorization == .notDetermined {
                        _ = try await self.backend.requestAccess()
                        self.authorization = await self.backend.access()
                    }
                    guard version == self.revision else { continue }
                    let pending = await self.backend.pendingIDs()
                    guard version == self.revision else { continue }
                    let obsolete = pending.filter { id in
                        let managed = id.hasPrefix(Self.taskPrefix) || (self.managesTimer && id == Self.timerID)
                        return managed && self.desired[id] == nil
                    }
                    self.backend.remove(obsolete)
                    if self.authorization == .allowed {
                        for alert in self.desired.values.sorted(by: { $0.id < $1.id }) where alert.date > .now {
                            guard version == self.revision else { break }
                            try await self.backend.add(alert)
                        }
                        self.issue = nil
                    } else if !self.desired.isEmpty || shouldAsk {
                        self.issue = L10n.text("通知尚未允许，请在系统设置中开启侧伴的通知。")
                    } else { self.issue = nil }
                } catch { self.issue = L10n.text("提醒未能安排：{0}。请检查通知设置后重试。", String(describing: error.localizedDescription)) }
                processed = version
            }
        }
    }
}
