import SidebarCore
import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Captured before asynchronous file providers or copying can change the selected page.
enum NoteInsertionTarget {
    case existingNote(UUID)
    case newNote
}

/// Local drafts stay available independently of the selected Obsidian vault.
@MainActor @Observable final class WorkspaceStore {
    static let recordingDestinationKey = "recordingNoteDestination"
    static let fileDropDestinationKey = "fileDropNoteDestination"
    var recordingNoteDestination: NoteDestination {
        didSet { defaults.set(recordingNoteDestination.rawValue, forKey: Self.recordingDestinationKey) }
    }
    var fileDropNoteDestination: NoteDestination {
        didSet { defaults.set(fileDropNoteDestination.rawValue, forKey: Self.fileDropDestinationKey) }
    }

    var tasks: [TaskItem] = [] { didSet {
        persist()
        if !isLoading { notifications.updateTasks(tasks) }
    } }
    var pages: [NotePage] = [] { didSet { persist() } }
    var selectedPageID: UUID? { didSet { defaults.set(selectedPageID?.uuidString, forKey: "selectedPageID") } }
    var currentPage: NotePage? { pages.first { $0.id == selectedPageID } ?? pages.first }
    var note: String {
        get { currentPage?.content ?? "" }
        set {
            guard let id = currentPage?.id, let index = pages.firstIndex(where: { $0.id == id }) else { return }
            pages[index].content = newValue
        }
    }
    @ObservationIgnored private let speech: any TranscriptionProviding
    @ObservationIgnored private var processingSpeech = false

    var vaultName: String { vaultURL?.lastPathComponent ?? L10n.text("尚未连接") }
    var vaultURL: URL?
    var message: String?
    let timer: PomodoroTimer
    let holidays: HolidayCalendar
    let storage: StorageLocations
    let notifications: NotificationService
    let audio: RecordingStore
    @ObservationIgnored private var isLoading = true
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard, audio: RecordingStore? = nil, speech: (any TranscriptionProviding)? = nil, notifications: NotificationService? = nil, storage: StorageLocations? = nil) {
        self.defaults = defaults
        self.recordingNoteDestination = NoteDestination(rawValue: defaults.string(forKey: Self.recordingDestinationKey) ?? "") ?? .currentNote
        self.fileDropNoteDestination = NoteDestination(rawValue: defaults.string(forKey: Self.fileDropDestinationKey) ?? "") ?? .newNote
        self.holidays = HolidayCalendar(defaults: defaults)
        self.storage = storage ?? StorageLocations(defaults: defaults)
        let notificationService = notifications ?? NotificationService()
        self.notifications = notificationService
        self.timer = PomodoroTimer(defaults: defaults, notifications: notificationService)
        self.audio = audio ?? RecordingStore()
        self.speech = speech ?? SpeechTranscriber()
        if let data = defaults.data(forKey: "tasks"),
           let saved = try? JSONDecoder().decode([TaskItem].self, from: data) { tasks = saved }
        if let data = defaults.data(forKey: "notePages"),
           let saved = try? JSONDecoder().decode([NotePage].self, from: data), !saved.isEmpty {
            pages = saved
        } else {
            pages = [NotePage(title: L10n.text("随手记"), content: defaults.string(forKey: "note") ?? "")]
        }
        selectedPageID = defaults.string(forKey: "selectedPageID").flatMap(UUID.init(uuidString:))
        if !pages.contains(where: { $0.id == selectedPageID }) { selectedPageID = pages.first?.id }
        for pageIndex in pages.indices {
            for attachmentIndex in pages[pageIndex].attachments.indices {
                if [.queued, .transcribing].contains(pages[pageIndex].attachments[attachmentIndex].status) {
                    pages[pageIndex].attachments[attachmentIndex].status = .failed
                    pages[pageIndex].attachments[attachmentIndex].error = L10n.text("上次识别未完成，点击重试。")
                }
            }
        }
        self.audio.directoryProvider = { [storage = self.storage] in try storage.directory(.recordings) }
        self.audio.additionalDirectories = { [storage = self.storage] in storage.recordingDirectories }
        self.audio.reload()
        self.audio.onRecorded = { [weak self] recording in self?.attach(recording) }
        isLoading = false
        persist()
        self.notifications.updateTasks(tasks, requestPermission: false)
        if let bookmark = defaults.data(forKey: "vaultBookmark") {
            do {
                var stale = false
                let url = try URL(resolvingBookmarkData: bookmark, options: .withSecurityScope, bookmarkDataIsStale: &stale)
                vaultURL = url
                if stale { try saveBookmark(url) }
            } catch { message = L10n.text("请在设置中重新选择 Obsidian 仓库。") }
        }
    }

    /// Mutate a detached value, then publish once. UI callbacks must not read array bindings during an in-place mutation.
    func updateTask(id: UUID, change: (inout TaskItem) -> Void) {
        var snapshot = tasks
        guard let index = snapshot.firstIndex(where: { $0.id == id }) else { return }
        var task = snapshot[index]
        change(&task)
        snapshot[index] = task
        tasks = snapshot
    }

    func removeTask(id: UUID) {
        let snapshot = tasks
        tasks = snapshot.filter { $0.id != id }
    }

    private func persist() {
        guard !isLoading else { return }
        defaults.set(try? JSONEncoder().encode(tasks), forKey: "tasks")
        defaults.set(try? JSONEncoder().encode(pages), forKey: "notePages")
    }

    func addPage() {
        let page = NotePage(title: L10n.text("笔记 {0}", String(describing: pages.count + 1)), color: NoteColor.allCases[pages.count % NoteColor.allCases.count])
        pages.append(page)
        selectedPageID = page.id
    }

    func removePage(id: UUID) {
        guard let index = pages.firstIndex(where: { $0.id == id }) else { return }
        let selectedID = currentPage?.id
        var remaining = pages.filter { $0.id != id }
        if remaining.isEmpty { remaining = [NotePage(title: L10n.text("随手记"))] }
        pages = remaining
        if selectedID == id {
            selectedPageID = remaining[min(index, remaining.count - 1)].id
        }
    }

    func captureNoteTarget(for destination: NoteDestination) -> NoteInsertionTarget {
        if destination == .currentNote, let id = currentPage?.id { return .existingNote(id) }
        return .newNote
    }

    /// A deleted destination falls back to a new page, never to an unrelated selected page.
    func resolveNoteTarget(_ target: NoteInsertionTarget, title: String) -> UUID {
        if case .existingNote(let id) = target, pages.contains(where: { $0.id == id }) { return id }
        let page = NotePage(title: title, color: NoteColor.allCases[pages.count % NoteColor.allCases.count])
        pages.append(page)
        selectedPageID = page.id
        return page.id
    }

    private func attach(_ recording: AudioRecording) {
        let target = captureNoteTarget(for: recordingNoteDestination)
        let title = L10n.text("录音 {0}", recording.createdAt.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(AppLanguage.current().locale)))
        let id = resolveNoteTarget(target, title: title)
        guard let index = pages.firstIndex(where: { $0.id == id }) else { return }
        pages[index].attachments.append(NoteAudio(filename: recording.id, createdAt: recording.createdAt))
        pages[index].content += L10n.text("\n\n## 录音 {0}\n\n![[{1}]]\n", String(describing: recording.createdAt.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(AppLanguage.current().locale))), String(describing: recording.id))
        processTranscriptions()
    }

    func retryTranscription(pageID: UUID, filename: String) {
        guard let p = pages.firstIndex(where: { $0.id == pageID }),
              let a = pages[p].attachments.firstIndex(where: { $0.filename == filename }),
              pages[p].attachments[a].status == .failed else { return }
        pages[p].attachments[a].status = .queued
        pages[p].attachments[a].error = nil
        processTranscriptions()
    }

    private func processTranscriptions() {
        guard !processingSpeech else { return }
        processingSpeech = true
        Task { [weak self] in
            guard let self else { return }
            defer { self.processingSpeech = false }
            while let page = self.pages.first(where: { $0.attachments.contains { $0.status == .queued } }),
                  let attachment = page.attachments.first(where: { $0.status == .queued }) {
                self.updateAudio(page.id, attachment.filename, status: .transcribing)
                do {
                    guard let recording = self.audio.recording(named: attachment.filename) else {
                        throw SpeechTranscriber.Failure(L10n.text("本机音频文件不存在。"))
                    }
                    let language = self.defaults.string(forKey: "speechLanguage") ?? "zh-CN"
                    let text = try await self.speech.transcribe(recording.url, locale: language)
                    if let index = self.pages.firstIndex(where: { $0.id == page.id }) {
                        self.pages[index].content += L10n.text("\n\n### 录音转写（{0}）\n\n{1}\n", String(describing: attachment.createdAt.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(AppLanguage.current().locale))), String(describing: text))
                    }
                    self.updateAudio(page.id, attachment.filename, status: .completed)
                } catch {
                    self.updateAudio(page.id, attachment.filename, status: .failed, error: error.localizedDescription)
                }
            }
        }
    }

    private func updateAudio(_ pageID: UUID, _ filename: String, status: TranscriptionStatus, error: String? = nil) {
        guard let p = pages.firstIndex(where: { $0.id == pageID }),
              let a = pages[p].attachments.firstIndex(where: { $0.filename == filename }) else { return }
        pages[p].attachments[a].status = status
        pages[p].attachments[a].error = error
    }

    private func saveBookmark(_ url: URL) throws {
        let data = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        defaults.set(data, forKey: "vaultBookmark")
    }

    func selectVault() {
        let panel = NSOpenPanel()
        panel.title = L10n.text("选择 Obsidian 仓库文件夹")
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try saveBookmark(url); vaultURL = url }
        catch { message = L10n.text("无法保存文件夹授权：{0}", String(describing: error.localizedDescription)) }
    }

}
