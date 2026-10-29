import AppKit
import SidebarCore

extension WorkspaceStore {
    /// Capture the configured target once per drop, before any file is copied.
    func importDroppedFiles(_ urls: [URL], target: NoteInsertionTarget? = nil) async {
        let files = urls.filter(\.isFileURL)
        guard let first = files.first else { return }
        let target = target ?? captureNoteTarget(for: fileDropNoteDestination)
        let pageID = resolveNoteTarget(target, title: first.deletingPathExtension().lastPathComponent)
        for url in files { await importFile(url, to: pageID) }
    }

    /// Explicit new-note import remains available independently of the user's drop preference.
    func importFilesAsNewNote(_ urls: [URL]) async {
        await importDroppedFiles(urls, target: .newNote)
    }

    func importFile(_ source: URL, to pageID: UUID) async {
        guard pages.contains(where: { $0.id == pageID }) else { return }
        let access = source.startAccessingSecurityScopedResource()
        defer { if access { source.stopAccessingSecurityScopedResource() } }
        do {
            let folder = try storage.directory(.files)
            let folderID = storage.fileFolderID
            let originalName = source.lastPathComponent
            let basename = source.deletingPathExtension().lastPathComponent
                .components(separatedBy: .controlCharacters.union(CharacterSet(charactersIn: "/:\\[]|#^"))).joined(separator: "-")
            let safeExtension = source.pathExtension.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(String.init).joined()
            let ext = safeExtension.isEmpty ? "" : "." + String(safeExtension.prefix(20))
            let filename = String(basename.prefix(80)) + "-" + UUID().uuidString + ext
            let destination = folder.appendingPathComponent(filename)
            try await Task.detached {
                let values = try source.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                guard values.isRegularFile == true, values.isSymbolicLink != true else {
                    throw StorageLocations.StorageError(L10n.text("请拖入普通文件；暂不支持文件夹或符号链接。"))
                }
                do { try FileManager.default.copyItem(at: source, to: destination) }
                catch { try? FileManager.default.removeItem(at: destination); throw error }
            }.value
            guard let index = pages.firstIndex(where: { $0.id == pageID }) else { return }
            pages[index].files.append(NoteFile(filename: filename, originalName: originalName, folderID: folderID))
            pages[index].content += "\n\n![[\(filename)]]\n"
        } catch { message = L10n.text("文件未能加入笔记：{0}", String(describing: error.localizedDescription)) }
    }

    func openFile(_ file: NoteFile) {
        do { NSWorkspace.shared.open(try storage.fileURL(file)) }
        catch { message = error.localizedDescription }
    }

}
