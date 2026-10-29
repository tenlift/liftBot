import Foundation

public struct NotePage: Identifiable, Codable {
    public init(id: UUID = UUID(), title: String, color: NoteColor = .blue, content: String = "", attachments: [NoteAudio] = [], files: [NoteFile] = []) { self.id = id; self.title = title; self.color = color; self.content = content; self.attachments = attachments; self.files = files }

    public var id = UUID()
    public var title: String
    public var color: NoteColor = .blue
    public var content = ""
    public var attachments: [NoteAudio] = []
    public var files: [NoteFile] = []
}

public struct NoteAudio: Identifiable, Codable {
    public init(filename: String, createdAt: Date, status: TranscriptionStatus = .queued, error: String? = nil) { self.filename = filename; self.createdAt = createdAt; self.status = status; self.error = error }

    public var id: String { filename }
    public let filename: String
    public let createdAt: Date
    public var status: TranscriptionStatus = .queued
    public var error: String?
}

public enum TranscriptionStatus: String, Codable {
    case queued, transcribing, completed, failed
}

public enum NoteColor: String, CaseIterable, Codable, Identifiable {
    case blue, green, orange, pink, purple, gray
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .blue: "蓝色"
        case .green: "绿色"
        case .orange: "橙色"
        case .pink: "粉色"
        case .purple: "紫色"
        case .gray: "灰色"
        }
    }

}

public struct NoteFile: Identifiable, Codable {
    public init(id: UUID = UUID(), filename: String, originalName: String, folderID: UUID?) { self.id = id; self.filename = filename; self.originalName = originalName; self.folderID = folderID }

    public var id = UUID()
    public let filename: String
    public let originalName: String
    public let folderID: UUID?
}

extension NotePage {
    private enum CodingKeys: String, CodingKey { case id, title, color, content, attachments, files }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        title = try values.decode(String.self, forKey: .title)
        color = try values.decodeIfPresent(NoteColor.self, forKey: .color) ?? .blue
        content = try values.decodeIfPresent(String.self, forKey: .content) ?? ""
        attachments = try values.decodeIfPresent([NoteAudio].self, forKey: .attachments) ?? []
        files = try values.decodeIfPresent([NoteFile].self, forKey: .files) ?? []
    }
}
