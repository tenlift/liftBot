import SwiftUI
import SidebarCore

extension NoteColor {
    var tint: Color {
        switch self {
        case .blue: .blue
        case .green: .green
        case .orange: .orange
        case .pink: .pink
        case .purple: .purple
        case .gray: .gray
        }
    }
}
