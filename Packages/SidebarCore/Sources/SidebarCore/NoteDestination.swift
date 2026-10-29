/// Independent insertion preferences for finished recordings and dropped files.
public enum NoteDestination: String, CaseIterable, Codable, Identifiable, Sendable {
    case currentNote, newNote
    public var id: String { rawValue }
}
