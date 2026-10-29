import Foundation
import SidebarCore

@MainActor func checkNoteDestinations() async throws {
    let suite = "SidebarDestinationChecks-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
    defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
    let audioFolder = root.appendingPathComponent("Audio")
    try FileManager.default.createDirectory(at: audioFolder, withIntermediateDirectories: true)
    let audio1 = audioFolder.appendingPathComponent("current.m4a")
    let audio2 = audioFolder.appendingPathComponent("new.m4a")
    let file1 = root.appendingPathComponent("first.txt")
    let file2 = root.appendingPathComponent("second.txt")
    for url in [audio1, audio2, file1, file2] { try Data("fixture".utf8).write(to: url) }
    let audio = RecordingStore(directoryURL: audioFolder)
    let speech = FakeSpeech()
    let store = WorkspaceStore(defaults: defaults, audio: audio, speech: speech,
                               notifications: NotificationService(backend: FakeNotificationBackend()),
                               storage: StorageLocations(defaults: defaults, baseURL: root.appendingPathComponent("Local")))
    func wait(_ condition: () -> Bool) async {
        for _ in 0..<300 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        preconditionFailure("note destination operation timed out")
    }
    precondition(store.recordingNoteDestination == .currentNote && store.fileDropNoteDestination == .newNote, "defaults preserve existing behavior")
    let originalID = store.currentPage!.id
    store.note = "Existing note must stay"
    audio.onRecorded?(AudioRecording(url: audio1, createdAt: .now))
    precondition(store.pages.count == 1 && store.currentPage!.attachments.count == 1 && store.note.hasPrefix("Existing note must stay"))
    await wait { speech.pending != nil }
    store.addPage()
    let otherID = store.currentPage!.id
    store.note = "Unrelated page"
    store.recordingNoteDestination = .newNote
    speech.succeed("First transcript")
    await wait { store.pages.first(where: { $0.id == originalID })?.attachments.first?.status == .completed }
    precondition(store.note == "Unrelated page" && store.pages.count == 2, "settings and tab changes do not redirect in-flight transcription")
    precondition(store.pages.first(where: { $0.id == originalID })!.content.contains("First transcript"))

    audio.onRecorded?(AudioRecording(url: audio2, createdAt: .now))
    let recordingPageID = store.currentPage!.id
    precondition(store.pages.count == 3 && recordingPageID != originalID && recordingPageID != otherID)
    precondition(store.currentPage!.attachments.first?.filename == "new.m4a" && store.currentPage!.title.hasPrefix("录音"), "one recording creates and selects one appropriately named note")
    store.note += "\nManual edit during transcription"
    await wait { speech.pending != nil }
    store.selectedPageID = otherID
    store.recordingNoteDestination = .currentNote
    speech.succeed("Second transcript")
    await wait { store.pages.first(where: { $0.id == recordingPageID })?.attachments.first?.status == .completed }
    let recordedNote = store.pages.first(where: { $0.id == recordingPageID })!
    precondition(recordedNote.content.contains("Second transcript") && recordedNote.content.contains("Manual edit during transcription"))
    precondition(store.note == "Unrelated page" && store.pages.count == 3)

    store.selectedPageID = originalID
    store.fileDropNoteDestination = .currentNote
    let capturedTarget = store.captureNoteTarget(for: store.fileDropNoteDestination)
    store.selectedPageID = otherID
    store.fileDropNoteDestination = .newNote
    await store.importDroppedFiles([file1, file2], target: capturedTarget)
    precondition(store.pages.count == 3 && store.currentPage!.id == otherID, "current-note drop does not create a page or steal selection")
    let targetNote = store.pages.first(where: { $0.id == originalID })!
    precondition(targetNote.files.count == 2 && targetNote.content.hasPrefix("Existing note must stay"))
    precondition(store.note == "Unrelated page", "a delayed file provider cannot redirect attachments to a different tab")

    let newTarget = store.captureNoteTarget(for: .newNote)
    store.fileDropNoteDestination = .currentNote
    await store.importDroppedFiles([file1, file2], target: newTarget)
    let newFilePage = store.currentPage!
    precondition(store.pages.count == 4 && newFilePage.files.count == 2 && newFilePage.title == "first", "one drop creates one note for all files")
    precondition(newFilePage.attachments.isEmpty, "file policy is independent of recording policy")

    // Exercise the actual collapsed-tab entry point before its asynchronous Task runs.
    store.selectedPageID = otherID
    let beforeCount = store.pages.count
    precondition(store.receiveFileURLs([file1]))
    store.selectedPageID = recordingPageID
    store.fileDropNoteDestination = .newNote
    await wait { store.pages.first(where: { $0.id == otherID })?.files.count == 1 }
    precondition(store.pages.count == beforeCount && store.currentPage!.id == recordingPageID,
                 "collapsed-tab drops capture the current note at acceptance, not after expansion or a tab switch")

    // If a captured page disappears while providers load, use a new page rather than another current page.
    let deletedTarget = store.captureNoteTarget(for: .currentNote)
    store.removePage(id: recordingPageID)
    store.selectedPageID = otherID
    await store.importDroppedFiles([file2], target: deletedTarget)
    precondition(store.currentPage!.id != otherID && store.currentPage!.files.count == 1 && store.currentPage!.title == "second")
    precondition(store.pages.first(where: { $0.id == otherID })!.content.hasPrefix("Unrelated page"))

    store.recordingNoteDestination = .newNote
    store.fileDropNoteDestination = .currentNote
    let reopened = WorkspaceStore(defaults: UserDefaults(suiteName: suite)!, audio: RecordingStore(directoryURL: audioFolder), speech: FakeSpeech(),
                                  notifications: NotificationService(backend: FakeNotificationBackend()),
                                  storage: StorageLocations(defaults: defaults, baseURL: root.appendingPathComponent("Local")))
    precondition(reopened.recordingNoteDestination == .newNote && reopened.fileDropNoteDestination == .currentNote, "both independent choices persist")
    let pagesBeforeEmptyImport = store.pages.count
    await store.importDroppedFiles([])
    precondition(store.pages.count == pagesBeforeEmptyImport)
    precondition(FileManager.default.fileExists(atPath: file1.path) && FileManager.default.fileExists(atPath: file2.path), "source files remain untouched")
    print("PASS: independent recording/file destinations, preserved defaults, preference persistence, batch drops, acceptance-time target capture, deleted-target fallback and tab-safe transcription")
}
