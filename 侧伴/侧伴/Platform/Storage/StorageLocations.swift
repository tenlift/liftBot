import SidebarCore
import AppKit
import Observation

struct StoredFolder: Identifiable, Codable {
    let id: UUID
    let kind: String
    var bookmark: Data
    var originalPath: String?
}

@MainActor @Observable final class StorageLocations {
    enum Kind: String { case files, recordings }
    private(set) var fileFolderID: UUID?
    private(set) var recordingFolderID: UUID?
    var attachmentExportPath: String { didSet { defaults.set(attachmentExportPath, forKey: "attachmentExportPath") } }
    var recordingExportPath: String { didSet { defaults.set(recordingExportPath, forKey: "recordingExportPath") } }
    var issue: String?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let baseURL: URL?
    @ObservationIgnored private var folders: [StoredFolder] = []
    @ObservationIgnored private var resolved: [UUID: URL] = [:]
    @ObservationIgnored private var scopes: [URL] = []

    init(defaults: UserDefaults = .standard, baseURL: URL? = nil) {
        self.defaults = defaults
        self.baseURL = baseURL
        attachmentExportPath = defaults.string(forKey: "attachmentExportPath") ?? "Sidebar/Attachments"
        recordingExportPath = defaults.string(forKey: "recordingExportPath") ?? "Sidebar/Recordings"
        if let data = defaults.data(forKey: "storageFolders"), let saved = try? JSONDecoder().decode([StoredFolder].self, from: data) { folders = saved }
        fileFolderID = defaults.string(forKey: "fileFolderID").flatMap(UUID.init(uuidString:))
        recordingFolderID = defaults.string(forKey: "recordingFolderID").flatMap(UUID.init(uuidString:))
        for index in folders.indices {
            do {
                var stale = false
                let url = try URL(resolvingBookmarkData: folders[index].bookmark, options: .withSecurityScope, bookmarkDataIsStale: &stale)
                if url.startAccessingSecurityScopedResource() { scopes.append(url) }
                resolved[folders[index].id] = url
                if stale { folders[index].bookmark = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) }
            } catch { issue = L10n.text("部分附件目录授权已失效，请重新选择原文件夹。") }
        }
        save()
    }

    var recordingDirectories: [URL] {
        var urls = folders.filter { $0.kind == Kind.recordings.rawValue }.compactMap { resolved[$0.id] }
        if let fallback = try? defaultDirectory(.recordings) { urls.append(fallback) }
        return urls
    }

    func folderID(_ kind: Kind) -> UUID? { kind == .files ? fileFolderID : recordingFolderID }
    func label(_ kind: Kind) -> String {
        guard let id = folderID(kind) else { return L10n.text("应用本地目录") }
        return resolved[id]?.path ?? L10n.text("目录授权已失效")
    }

    func directory(_ kind: Kind, folderID: UUID? = nil) throws -> URL {
        let id = folderID ?? self.folderID(kind)
        if let id {
            guard let url = resolved[id] else { throw StorageError(L10n.text("附件目录不可用，请重新选择原文件夹。")) }
            return url
        }
        return try defaultDirectory(kind)
    }

    // A nil file folder ID means the original application directory, independent of current selection.
    func fileURL(_ file: NoteFile) throws -> URL {
        let parent: URL
        if let id = file.folderID {
            guard let url = resolved[id] else { throw StorageError(L10n.text("文件目录授权失效：{0}", String(describing: file.originalName))) }
            parent = url
        } else { parent = try defaultDirectory(.files) }
        return parent.appendingPathComponent(file.filename)
    }

    private func defaultDirectory(_ kind: Kind) throws -> URL {
        let root: URL
        if let baseURL { root = baseURL }
        else {
            root = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                .appendingPathComponent(Bundle.main.bundleIdentifier ?? "Sidebar", isDirectory: true)
        }
        let url = root.appendingPathComponent(kind == .files ? "Attachments" : "Recordings", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func select(_ kind: Kind) {
        let panel = NSOpenPanel()
        panel.title = kind == .files ? L10n.text("选择文件附件存放目录") : L10n.text("选择录音存放目录")
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let bookmark = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            let existing = resolved.first { $0.value.standardizedFileURL == url.standardizedFileURL }?.key
                ?? folders.first { $0.kind == kind.rawValue && $0.originalPath == url.path }?.id
            let id = existing ?? UUID()
            if let index = folders.firstIndex(where: { $0.id == id && $0.kind == kind.rawValue }) { folders[index].bookmark = bookmark; folders[index].originalPath = url.path }
            else { folders.append(StoredFolder(id: id, kind: kind.rawValue, bookmark: bookmark, originalPath: url.path)) }
            if url.startAccessingSecurityScopedResource() { scopes.append(url) }
            resolved[id] = url
            if kind == .files { fileFolderID = id } else { recordingFolderID = id }
            issue = nil
            save()
        } catch { issue = L10n.text("无法授权目录：{0}", String(describing: error.localizedDescription)) }
    }

    func useDefault(_ kind: Kind) {
        if kind == .files { fileFolderID = nil } else { recordingFolderID = nil }
        save()
    }

    func exportDirectory(in vault: URL, path: String) throws -> URL {
        let value = path.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = value.split(separator: "/", omittingEmptySubsequences: false)
        guard !value.isEmpty, !value.hasPrefix("/"), !value.contains("\\"),
              parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw StorageError(L10n.text("附件保存路径必须是仓库内的相对目录，不能包含 .. 或空目录名。"))
        }
        let root = vault.resolvingSymlinksInPath().standardizedFileURL
        var url = root
        // Resolve each existing ancestor; resolving a whole not-yet-existing path can leave an intermediate symlink untouched.
        for part in parts {
            let next = url.appendingPathComponent(String(part), isDirectory: true)
            if let link = try? FileManager.default.destinationOfSymbolicLink(atPath: next.path) {
                let target = link.hasPrefix("/") ? URL(fileURLWithPath: link, isDirectory: true) : url.appendingPathComponent(link, isDirectory: true)
                url = target.resolvingSymlinksInPath().standardizedFileURL
            } else { url = next.standardizedFileURL }
            guard url.path == root.path || url.path.hasPrefix(root.path + "/") else {
                throw StorageError(L10n.text("附件目录必须位于 Obsidian 仓库内。"))
            }
        }
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func save() {
        defaults.set(try? JSONEncoder().encode(folders), forKey: "storageFolders")
        defaults.set(fileFolderID?.uuidString, forKey: "fileFolderID")
        defaults.set(recordingFolderID?.uuidString, forKey: "recordingFolderID")
    }

    struct StorageError: LocalizedError {
        let errorDescription: String?
        init(_ message: String) { errorDescription = message }
    }
}
