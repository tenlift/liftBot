import SidebarCore
import SwiftUI
import AppKit

/// A growing native editor without its own scroll view. The Note page owns vertical scrolling.
struct NoteTextEditor: NSViewRepresentable {
    @AppStorage(AppLanguage.preferenceKey) private var interfaceLanguage = "system"
    @Binding var text: String

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    func makeNSView(context: Context) -> NSTextView {
        let editor = NSTextView(frame: .zero)
        editor.delegate = context.coordinator
        editor.isRichText = false
        editor.importsGraphics = false
        editor.unregisterDraggedTypes()
        editor.drawsBackground = false
        editor.font = .preferredFont(forTextStyle: .body)
        editor.textColor = .labelColor
        editor.insertionPointColor = .labelColor
        editor.textContainerInset = NSSize(width: 4, height: 8)
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.textContainer?.widthTracksTextView = true
        editor.textContainer?.heightTracksTextView = false
        editor.textContainer?.containerSize.height = .greatestFiniteMagnitude
        editor.setAccessibilityLabel(L10n.text("Markdown 笔记内容"))
        editor.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return editor
    }

    func updateNSView(_ editor: NSTextView, context: Context) {
        editor.setAccessibilityLabel(L10n.text("Markdown 笔记内容"))
        context.coordinator.text = $text
        guard editor.string != text else { return }
        let selection = editor.selectedRange()
        let wasAtEnd = NSMaxRange(selection) == (editor.string as NSString).length
        editor.string = text
        let length = (text as NSString).length
        editor.setSelectedRange(NSRange(location: wasAtEnd ? length : min(selection.location, length), length: 0))
        editor.invalidateIntrinsicContentSize()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView editor: NSTextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width > 0,
              let container = editor.textContainer, let layout = editor.layoutManager else { return nil }
        container.containerSize = NSSize(width: max(1, width - editor.textContainerInset.width * 2), height: .greatestFiniteMagnitude)
        layout.ensureLayout(for: container)
        let bottom = max(layout.usedRect(for: container).maxY, layout.extraLineFragmentRect.maxY)
        return CGSize(width: width, height: max(140, ceil(bottom + editor.textContainerInset.height * 2)))
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        init(text: Binding<String>) { self.text = text }
        func textDidChange(_ notification: Notification) {
            guard let editor = notification.object as? NSTextView else { return }
            text.wrappedValue = editor.string
            editor.invalidateIntrinsicContentSize()
        }
    }
}
