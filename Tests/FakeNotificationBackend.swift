import SidebarCore
import Foundation

@MainActor final class FakeNotificationBackend: NotificationBackend {
    var authorization = NotificationAccess.allowed
    var alerts: [String: ScheduledAlert] = [:]
    var removedDelivered: Set<String> = []
    var requests = 0
    var suspendNextAdd = false
    var suspendedAdd: CheckedContinuation<Void, Never>?
    var addError: Error?

    func access() async -> NotificationAccess { authorization }
    func requestAccess() async throws -> Bool { requests += 1; authorization = .allowed; return true }
    func pendingIDs() async -> [String] { Array(alerts.keys) }
    func add(_ alert: ScheduledAlert) async throws {
        if suspendNextAdd {
            suspendNextAdd = false
            await withCheckedContinuation { suspendedAdd = $0 }
        }
        if let addError { throw addError }
        alerts[alert.id] = alert
    }
    func resumeAdd() { let continuation = suspendedAdd; suspendedAdd = nil; continuation?.resume() }
    func remove(_ ids: [String]) { for id in ids { alerts.removeValue(forKey: id) } }
    func removeDelivered(_ ids: [String]) { removedDelivered.formUnion(ids) }
}
