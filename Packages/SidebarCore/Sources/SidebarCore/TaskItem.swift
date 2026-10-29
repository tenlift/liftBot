import Foundation

public struct TaskItem: Identifiable, Codable {
    public var id = UUID()
    public var title: String
    public var isCompleted = false
    public var reminderAt: Date?
    public init(id: UUID = UUID(), title: String, isCompleted: Bool = false, reminderAt: Date? = nil) {
        self.id = id; self.title = title; self.isCompleted = isCompleted; self.reminderAt = reminderAt
    }
}

