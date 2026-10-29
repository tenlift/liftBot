import SidebarCore
import Foundation
import Observation
import AppKit

/// Shared by the full sidebar and edge controls; ticking does not depend on a visible SwiftUI view.
@MainActor @Observable final class PomodoroTimer {
    var focusDuration: Int { didSet { defaults.set(focusDuration, forKey: "focusDuration") } }
    var breakDuration: Int { didSet { defaults.set(breakDuration, forKey: "breakDuration") } }
    private(set) var deadline: Date?
    private(set) var remaining: TimeInterval = 0
    private(set) var isBreak = false
    private(set) var hasStarted = false
    var isRunning: Bool { deadline != nil }
    var duration: Int { isBreak ? breakDuration : focusDuration }
    @ObservationIgnored private let notifications: NotificationService
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var ticker: Task<Void, Never>?

    init(defaults: UserDefaults = .standard, notifications: NotificationService) {
        self.defaults = defaults
        self.notifications = notifications
        focusDuration = max(1, defaults.object(forKey: "focusDuration") as? Int ?? 1500)
        breakDuration = max(1, defaults.object(forKey: "breakDuration") as? Int ?? 300)
    }

    func seconds(at date: Date = .now) -> Int {
        guard hasStarted else { return duration }
        return max(0, Int(ceil(deadline.map { $0.timeIntervalSince(date) } ?? remaining)))
    }

    func selectMode(isBreak: Bool) {
        guard !hasStarted else { return }
        self.isBreak = isBreak
    }

    func toggle() {
        if let deadline {
            remaining = max(0, deadline.timeIntervalSinceNow)
            self.deadline = nil
            ticker?.cancel(); ticker = nil
            notifications.setPomodoro(deadline: nil, isBreak: isBreak)
        } else {
            if !hasStarted || remaining <= 0 { remaining = TimeInterval(duration) }
            hasStarted = true
            deadline = Date().addingTimeInterval(remaining)
            notifications.setPomodoro(deadline: deadline, isBreak: isBreak)
            startTicker()
        }
    }

    func start(isBreak: Bool) {
        reset()
        self.isBreak = isBreak
        toggle()
    }

    func reset() {
        ticker?.cancel(); ticker = nil
        deadline = nil; remaining = 0; hasStarted = false
        notifications.setPomodoro(deadline: nil, isBreak: isBreak)
    }

    func finishIfNeeded(at date: Date = .now) {
        guard let deadline, deadline <= date else { return }
        self.deadline = nil
        remaining = 0
        ticker?.cancel(); ticker = nil
        if notifications.authorization != .allowed { NSSound.beep() }
        // Keep the system's scheduled completion notification; do not cancel it at the deadline.
    }

    private func startTicker() {
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
                guard let self else { return }
                self.finishIfNeeded()
                if self.deadline == nil { return }
            }
        }
    }
}
