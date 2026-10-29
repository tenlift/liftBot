import Foundation
import SidebarCore

// Snapshot exports never replace existing vault notes.
extension WorkspaceStore {
    func exportRecording(_ recording: AudioRecording) {
        guard let vaultURL else { message = L10n.text("请先在设置中选择 Obsidian 仓库。"); return }
        let granted = vaultURL.startAccessingSecurityScopedResource()
        defer { if granted { vaultURL.stopAccessingSecurityScopedResource() } }
        do {
            let folder = try storage.exportDirectory(in: vaultURL, path: storage.recordingExportPath)
            let destination = folder.appendingPathComponent(recording.url.lastPathComponent)
            // Re-exporting the same recording reuses its audio attachment.
            if !FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.copyItem(at: recording.url, to: destination)
            }
            let noteURL = folder.appendingPathComponent(recording.url.deletingPathExtension().lastPathComponent + ".md")
            if !FileManager.default.fileExists(atPath: noteURL.path) {
                let text = L10n.text("# 快捷录音\n\n{0}\n\n![[{1}]]\n", String(describing: recording.createdAt.formatted(Date.FormatStyle(date: .abbreviated, time: .standard).locale(AppLanguage.current().locale))), String(describing: recording.url.lastPathComponent))
                try text.write(to: noteURL, atomically: true, encoding: .utf8)
            }
            message = L10n.text("音频及引用笔记已保存到 {0}/{1}。", String(describing: vaultName), String(describing: storage.recordingExportPath))
        } catch { message = L10n.text("录音导出失败，本机音频仍保留：{0}", String(describing: error.localizedDescription)) }
    }

    /// Each export creates a new Markdown file; existing vault notes are never replaced.
    func exportMarkdown() {
        guard let url = vaultURL else { message = L10n.text("请先在设置中选择 Obsidian 仓库。"); return }
        let granted = url.startAccessingSecurityScopedResource()
        defer { if granted { url.stopAccessingSecurityScopedResource() } }
        do {
            let directory = url.appendingPathComponent("Sidebar", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if let page = currentPage, !page.attachments.isEmpty {
                let attachmentsFolder = try storage.exportDirectory(in: url, path: storage.recordingExportPath)
                for attachment in page.attachments {
                    let destination = attachmentsFolder.appendingPathComponent(attachment.filename)
                    if !FileManager.default.fileExists(atPath: destination.path) {
                        guard let recording = audio.recording(named: attachment.filename) else {
                            throw SpeechTranscriber.Failure(L10n.text("音频文件缺失：{0}", String(describing: attachment.filename)))
                        }
                        try FileManager.default.copyItem(at: recording.url, to: destination)
                    }
                }
            }
            if let page = currentPage, !page.files.isEmpty {
                let folder = try storage.exportDirectory(in: url, path: storage.attachmentExportPath)
                for file in page.files {
                    let source = try storage.fileURL(file)
                    let destination = folder.appendingPathComponent(file.filename)
                    if source.standardizedFileURL != destination.standardizedFileURL && !FileManager.default.fileExists(atPath: destination.path) {
                        try FileManager.default.copyItem(at: source, to: destination)
                    }
                }
            }
            // Preserve exactly what the user wrote: no task list, wrapper title or timestamp.
            let safeTitle = (currentPage?.title ?? L10n.text("笔记"))
                .components(separatedBy: .controlCharacters.union(CharacterSet(charactersIn: "/:\\")))
                .joined(separator: "-").trimmingCharacters(in: .whitespacesAndNewlines)
            let title = safeTitle.isEmpty ? L10n.text("笔记") : String(safeTitle.prefix(80))
            let filename = "\(title)-\(Int(Date().timeIntervalSince1970))-\(UUID().uuidString.prefix(6)).md"
            try note.write(to: directory.appendingPathComponent(filename), atomically: true, encoding: .utf8)
            message = L10n.text("笔记已保存到 {0}/Sidebar。", String(describing: vaultName))
        } catch { message = L10n.text("保存失败：{0}", String(describing: error.localizedDescription)) }
    }

    /// Task exports have their own action and directory, independent of the selected Note page.
    func exportTasks() {
        guard !tasks.isEmpty else { message = L10n.text("没有待办可保存。"); return }
        guard let url = vaultURL else { message = L10n.text("请先在设置中选择 Obsidian 仓库。"); return }
        let granted = url.startAccessingSecurityScopedResource()
        defer { if granted { url.stopAccessingSecurityScopedResource() } }
        do {
            let directory = url.appendingPathComponent("Sidebar/Tasks", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let taskText = tasks.map { task in
                let title = task.title.components(separatedBy: .newlines).joined(separator: " ")
                let reminder = task.reminderAt.map { L10n.text("（提醒：{0}）", String(describing: $0.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(AppLanguage.current().locale)))) } ?? ""
                return "- [\(task.isCompleted ? "x" : " ")] \(title)\(reminder)"
            }.joined(separator: "\n")
            let filename = L10n.text("待办事项-{0}-{1}.md", String(describing: Int(Date().timeIntervalSince1970)), String(describing: UUID().uuidString.prefix(6)))
            try (L10n.text("# 待办事项\n\n") + taskText + "\n").write(to: directory.appendingPathComponent(filename), atomically: true, encoding: .utf8)
            message = L10n.text("待办已单独保存到 {0}/Sidebar/Tasks。", String(describing: vaultName))
        } catch { message = L10n.text("待办保存失败：{0}", String(describing: error.localizedDescription)) }
    }

}
