import Foundation

public enum ShortcutAction: String, CaseIterable, Codable, Identifiable, Sendable {
    case focus, recording, sidebar
    public var id: String { rawValue }
    public var hotKeyID: UInt32 {
        switch self { case .focus: 1; case .recording: 2; case .sidebar: 3 }
    }
}

public struct ShortcutModifiers: OptionSet, Codable, Hashable, Sendable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }
    public static let command = Self(rawValue: 1 << 0)
    public static let control = Self(rawValue: 1 << 1)
    public static let option = Self(rawValue: 1 << 2)
    public static let shift = Self(rawValue: 1 << 3)
    public static let all: Self = [.command, .control, .option, .shift]

    public var symbols: String {
        (contains(.control) ? "⌃" : "") + (contains(.option) ? "⌥" : "") +
        (contains(.shift) ? "⇧" : "") + (contains(.command) ? "⌘" : "")
    }
}

public struct KeyboardShortcutBinding: Codable, Equatable, Sendable {
    public let keyCode: UInt32
    public let modifiers: ShortcutModifiers
    public let keyLabel: String

    public init(keyCode: UInt32, modifiers: ShortcutModifiers, keyLabel: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.keyLabel = keyLabel
    }

    /// Global shortcuts must not swallow ordinary typing or the standard editing commands.
    public var isValid: Bool {
        guard keyCode <= 126, ![54, 55, 56, 57, 58, 59, 60, 61, 62, 63].contains(keyCode),
              !keyLabel.isEmpty, keyLabel.count <= 32,
              modifiers.subtracting(.all).isEmpty,
              !modifiers.intersection([.command, .control, .option]).isEmpty else { return false }
        if modifiers == .command {
            let standardCommands: Set<UInt32> = [0, 1, 3, 4, 6, 7, 8, 9, 12, 13, 31, 35, 45, 46, 48, 49]
            if standardCommands.contains(keyCode) { return false }
        }
        if modifiers == [.command, .shift], keyCode == 6 { return false }
        return true
    }

    public func hasSameKeys(as other: Self) -> Bool {
        keyCode == other.keyCode && modifiers == other.modifiers
    }

    public static func defaults(for action: ShortcutAction) -> Self {
        switch action {
        case .focus: Self(keyCode: 35, modifiers: [.control, .option], keyLabel: "P")
        case .recording: Self(keyCode: 15, modifiers: [.control, .option], keyLabel: "R")
        case .sidebar: Self(keyCode: 49, modifiers: [.control, .option], keyLabel: "Space")
        }
    }
}
