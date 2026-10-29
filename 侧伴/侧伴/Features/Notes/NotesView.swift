import SidebarCore
import SwiftUI

struct NotesView: View {
    @AppStorage(AppLanguage.preferenceKey) private var interfaceLanguage = "system"
    @Binding var isExpanded: Bool
    @Environment(WorkspaceStore.self) private var store
    @Environment(\.colorScheme) private var colorScheme
    @State private var pageToDelete: NotePage?
    @State private var preview = false
    @State private var showingSpeechHelp = false

    var body: some View {
        @Bindable var store = store
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(L10n.text("笔记"), systemImage: "square.and.pencil").font(.headline)
                Spacer()
                Button { preview.toggle() } label: { Image(systemName: preview ? "pencil" : "eye") }
                    .buttonStyle(.plain).help(preview ? L10n.text("编辑 Markdown") : L10n.text("预览 Markdown"))
                Text(L10n.text("本地自动保存")).font(.caption2).foregroundStyle(.tertiary)
                Button { isExpanded.toggle() } label: {
                    Image(systemName: isExpanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                }.buttonStyle(.plain)
                    .help(isExpanded ? L10n.text("收起 Note") : L10n.text("展开 Note，专注长文记录"))
                    .accessibilityLabel(isExpanded ? L10n.text("收起 Note") : L10n.text("展开 Note"))
            }
            HStack(spacing: 6) {
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        ForEach(store.pages) { page in
                            HStack(spacing: 5) {
                                Button { store.selectedPageID = page.id } label: {
                                    HStack(spacing: 5) {
                                        Circle().fill(page.color.tint).frame(width: 6, height: 6)
                                        Text(page.title.isEmpty ? L10n.text("未命名") : page.title).lineLimit(1).frame(maxWidth: 100)
                                    }.padding(.vertical, 7)
                                }.buttonStyle(.plain)
                                Button { pageToDelete = page } label: {
                                    Image(systemName: "xmark").font(.system(size: 9, weight: .semibold))
                                        .foregroundStyle(.secondary).frame(width: 18, height: 24)
                                        .contentShape(Rectangle())
                                }.buttonStyle(.plain).help(L10n.text("删除笔记"))
                                    .accessibilityLabel(L10n.text("删除笔记：") + (page.title.isEmpty ? L10n.text("未命名") : page.title))
                            }.font(.caption).padding(.leading, 10).padding(.trailing, 5)
                                .background(page.color.tint.opacity(store.currentPage?.id == page.id ? 0.18 : 0.05), in: RoundedRectangle(cornerRadius: 7))
                                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(page.color.tint.opacity(store.currentPage?.id == page.id ? 0.5 : 0)))
                                .contextMenu {
                                    Button(L10n.text("删除笔记…"), role: .destructive) { pageToDelete = page }
                                }
                        }
                    }
                }.scrollIndicators(.hidden)
                Button { store.addPage(); preview = false } label: { Image(systemName: "plus") }
                    .buttonStyle(.plain).help(L10n.text("新增笔记页面")).accessibilityLabel(L10n.text("新增笔记页面"))
            }
            if let page = store.currentPage {
                HStack {
                    TextField(L10n.text("页面名称"), text: Binding(get: { store.currentPage?.title ?? "" }, set: { title in
                        if let index = store.pages.firstIndex(where: { $0.id == page.id }) { store.pages[index].title = title }
                    })).textFieldStyle(.plain).font(.subheadline.weight(.medium))
                    HStack(spacing: 7) {
                        ForEach(NoteColor.allCases) { color in
                            Button {
                                if let index = store.pages.firstIndex(where: { $0.id == page.id }) { store.pages[index].color = color }
                            } label: {
                                Circle().fill(color.tint.gradient)
                                    .overlay {
                                        if page.color == color {
                                            Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                                        }
                                    }
                                    .frame(width: 18, height: 18)
                                    .padding(2)
                                    .overlay(Circle().strokeBorder(page.color == color ? color.tint : .clear, lineWidth: 1))
                            }.buttonStyle(.plain).help(L10n.text(color.title))
                                .accessibilityLabel(L10n.text(color.title))
                                .accessibilityAddTraits(page.color == color ? .isSelected : [])
                        }
                    }
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(page.files) { file in
                            Button { store.openFile(file) } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "doc.fill").foregroundStyle(page.color.tint)
                                    Text(file.originalName).font(.caption).lineLimit(2)
                                    Spacer(minLength: 0)
                                    Image(systemName: "arrow.up.right").font(.caption2).foregroundStyle(.secondary)
                                }.padding(9).background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 7))
                            }.buttonStyle(.plain).help(L10n.text("打开附件：") + file.originalName)
                        }
                        ForEach(page.attachments) { attachment in
                            audioRow(attachment, pageID: page.id)
                        }
                        if preview {
                            MarkdownPreview(source: page.content).frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            ZStack(alignment: .topLeading) {
                                NoteTextEditor(text: $store.note)
                                if page.content.isEmpty {
                                    Text(L10n.text("用 Markdown 记下灵感…\n录音停止后也会自动放在这里。"))
                                        .font(.body).foregroundStyle(.tertiary).padding(.top, 8).padding(.leading, 9).allowsHitTesting(false)
                                }
                            }
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.trailing, 4)
                }.id(page.id).frame(minHeight: 60, maxHeight: .infinity)
            }
            HStack {
                Text(L10n.text("{0} 字 · Markdown", String(describing: store.note.count))).font(.caption2).foregroundStyle(.tertiary)
                Spacer()
                Button { store.exportMarkdown() } label: { Label(L10n.text("保存到 Obsidian"), systemImage: "arrow.up.doc") }
                    .controlSize(.small).disabled(store.note.isEmpty)
            }
        }.padding(16)
            .background {
                SidebarCardSurface(cornerRadius: 14, tint: store.currentPage?.color.tint ?? .blue)
            }
            .alert(L10n.text("删除笔记？"), isPresented: Binding(get: { pageToDelete != nil }, set: { if !$0 { pageToDelete = nil } }), presenting: pageToDelete) { page in
                Button(L10n.text("取消"), role: .cancel) { pageToDelete = nil }
                Button(L10n.text("删除"), role: .destructive) {
                    store.removePage(id: page.id)
                    pageToDelete = nil
                }
            } message: { page in
                Text(L10n.text("将删除“{0}”及其笔记内容，无法撤销。本机附件和已导出的文件会保留。", String(describing: page.title.isEmpty ? L10n.text("未命名") : page.title)))
            }
            .alert(L10n.text("语音识别帮助"), isPresented: $showingSpeechHelp) {
                Button(L10n.text("打开键盘设置")) {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") { NSWorkspace.shared.open(url) }
                }
                Button(L10n.text("好"), role: .cancel) {}
            } message: {
                Text(L10n.text("音频已保留。macOS 26 及以上优先使用新本地识别引擎，首次需要下载语言模型。旧系统若出现 1101，请检查系统设置 → 键盘 → 听写，启用对应语言并等待资源就绪，再重试；同时确认语音识别权限。"))
            }
    }

    private func audioRow(_ attachment: NoteAudio, pageID: UUID) -> some View {
        HStack(spacing: 8) {
            Button {
                if let recording = store.audio.recording(named: attachment.filename) { store.audio.play(recording) }
            } label: {
                Image(systemName: store.audio.playingID == attachment.filename ? "stop.circle.fill" : "play.circle.fill")
            }.buttonStyle(.plain).disabled(store.audio.isRecording).help(L10n.text("回放录音"))
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.text("录音 · {0}", String(describing: attachment.createdAt.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(AppLanguage.current().locale))))).font(.caption)
                Text(attachment.error ?? statusTitle(attachment.status)).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                    .help(attachment.error ?? statusTitle(attachment.status))
            }
            Spacer(minLength: 0)
            if [.queued, .transcribing].contains(attachment.status) { ProgressView().controlSize(.mini) }
            if attachment.status == .failed {
                VStack(spacing: 4) {
                    Button(L10n.text("重试")) { store.retryTranscription(pageID: pageID, filename: attachment.filename) }.controlSize(.mini)
                    Button(L10n.text("帮助")) { showingSpeechHelp = true }.buttonStyle(.plain).font(.caption2)
                }
            }
        }.padding(8).background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 7))
    }

    private func statusTitle(_ status: TranscriptionStatus) -> String {
        switch status {
        case .queued: L10n.text("等待转写")
        case .transcribing: L10n.text("正在转写…")
        case .completed: L10n.text("转写已加入笔记")
        case .failed: L10n.text("转写失败，音频已保留")
        }
    }
}

/// Lightweight native preview for headings, lists, quotes, fenced code and inline Markdown.
private struct MarkdownPreview: View {
    @AppStorage(AppLanguage.preferenceKey) private var interfaceLanguage = "system"
    let source: String
    private var lines: [PreviewLine] {
        var code = false
        return source.components(separatedBy: .newlines).enumerated().map { index, text in
            if text.hasPrefix("```") { code.toggle(); return PreviewLine(id: index, text: "", style: .separator) }
            if code { return PreviewLine(id: index, text: text, style: .code) }
            for level in (1...6).reversed() {
                let prefix = String(repeating: "#", count: level) + " "
                if text.hasPrefix(prefix) { return PreviewLine(id: index, text: String(text.dropFirst(prefix.count)), style: .heading(level)) }
            }
            if text.hasPrefix("![[") { return PreviewLine(id: index, text: L10n.text("📎 附件（可在上方打开或回放）"), style: .quote) }
            if text.hasPrefix("> ") { return PreviewLine(id: index, text: String(text.dropFirst(2)), style: .quote) }
            if text.hasPrefix("- [ ] ") { return PreviewLine(id: index, text: "☐ " + text.dropFirst(6), style: .body) }
            if text.hasPrefix("- [x] ") { return PreviewLine(id: index, text: "☑ " + text.dropFirst(6), style: .body) }
            if text.hasPrefix("- ") || text.hasPrefix("* ") { return PreviewLine(id: index, text: "• " + text.dropFirst(2), style: .body) }
            return PreviewLine(id: index, text: text, style: .body)
        }
    }
    var body: some View {
        LazyVStack(alignment: .leading, spacing: 6) {
            ForEach(lines) { line in
                switch line.style {
                case .separator: EmptyView()
                case .heading(let level):
                    inline(line.text).font(level == 1 ? .title2 : (level == 2 ? .title3 : .headline)).fontWeight(.semibold).padding(.top, 6)
                case .code:
                    Text(line.text.isEmpty ? " " : line.text).font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading).padding(6).background(.primary.opacity(0.04))
                case .quote:
                    inline(line.text).foregroundStyle(.secondary).padding(.leading, 10)
                        .overlay(alignment: .leading) { Rectangle().fill(.secondary.opacity(0.3)).frame(width: 2) }
                case .body: inline(line.text.isEmpty ? " " : line.text)
                }
            }
        }.textSelection(.enabled).padding(.vertical, 4)
    }
    private func inline(_ text: String) -> Text {
        Text((try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text))
    }
    private struct PreviewLine: Identifiable {
        let id: Int
        let text: String
        let style: Style
    }
    private enum Style { case body, heading(Int), quote, code, separator }
}
