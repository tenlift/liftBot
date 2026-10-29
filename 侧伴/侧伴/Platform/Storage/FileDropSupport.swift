import SidebarCore
import AppKit
import UniformTypeIdentifiers

extension WorkspaceStore {
    func receiveFiles(_ providers: [NSItemProvider]) -> Bool {
        let files = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        guard !files.isEmpty else { return false }
        let target = captureNoteTarget(for: fileDropNoteDestination)
        Task {
            var urls: [URL] = []
            for provider in files {
                let url: URL? = await withCheckedContinuation { continuation in
                    provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                        let url: URL?
                        if let value = item as? URL { url = value }
                        else if let data = item as? Data { url = URL(dataRepresentation: data, relativeTo: nil) }
                        else if let string = item as? String { url = URL(string: string) }
                        else { url = nil }
                        continuation.resume(returning: url)
                    }
                }
                if let url, url.isFileURL { urls.append(url) }
                else { message = L10n.text("无法读取拖入的文件，请从 Finder 拖入本地文件。") }
            }
            await importDroppedFiles(urls, target: target)
        }
        return true
    }

    /// The collapsed AppKit tab and expanded SwiftUI window share this import behavior.
    func receiveFileURLs(_ urls: [URL]) -> Bool {
        let files = urls.filter(\.isFileURL)
        guard !files.isEmpty else { return false }
        let target = captureNoteTarget(for: fileDropNoteDestination)
        Task { await importDroppedFiles(files, target: target) }
        return true
    }
}
