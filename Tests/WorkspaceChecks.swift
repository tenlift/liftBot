import SidebarCore
import Foundation
import CoreGraphics

@MainActor final class FakeSpeech: TranscriptionProviding {
    var pending: CheckedContinuation<String, Error>?
    func transcribe(_ url: URL, locale: String) async throws -> String {
        try await withCheckedThrowingContinuation { pending = $0 }
    }
    func succeed(_ text: String) { let callback = pending; pending = nil; callback?.resume(returning: text) }
    func fail() { let callback = pending; pending = nil; callback?.resume(throwing: SpeechTranscriber.Failure("模拟识别失败")) }
}

@main struct WorkspaceChecks {
    @MainActor static func main() async throws {
        try checkShortcuts()
        try await checkLocalization()
        UserDefaults.standard.setVolatileDomain([AppLanguage.preferenceKey: "zh-Hans"], forName: UserDefaults.argumentDomain)
        try await checkNoteDestinations()
        let disconnected = SpeechTranscriber.readableError(NSError(domain: "kAFAssistantErrorDomain", code: 1101))
        precondition(disconnected.contains("连接中断") && disconnected.contains("1101"), "1101 has actionable recovery text")
        let missingAssets = SpeechTranscriber.readableError(NSError(domain: "kLSRErrorDomain", code: 102))
        precondition(missingAssets.contains("语言资源"), "missing model has actionable recovery text")
        let noSpeech = SpeechTranscriber.readableError(NSError(domain: "kAFAssistantErrorDomain", code: 1110))
        precondition(noSpeech.contains("未识别到语音"), "silence is distinct from service failure")
        let suite = "SidebarChecks-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        defer { try? FileManager.default.removeItem(at: root) }
        let audioFolder = root.appendingPathComponent("Audio")
        try FileManager.default.createDirectory(at: audioFolder, withIntermediateDirectories: true)
        let audioURL = audioFolder.appendingPathComponent("fixture.m4a")
        // Export tests copy opaque fixture bytes; no microphone or playback is used.
        try Data("audio-fixture".utf8).write(to: audioURL)
        defaults.set("旧笔记 **完整保留**", forKey: "note")
        let audio = RecordingStore(directoryURL: audioFolder)
        let speech = FakeSpeech()
        let workspaceBackend = FakeNotificationBackend()
        let store = WorkspaceStore(defaults: defaults, audio: audio, speech: speech, notifications: NotificationService(backend: workspaceBackend), storage: StorageLocations(defaults: defaults, baseURL: root.appendingPathComponent("Local")))
        precondition(store.pages.count == 1 && store.note == "旧笔记 **完整保留**", "legacy migration")
        let originalID = store.currentPage!.id
        audio.onRecorded?(AudioRecording(url: audioURL, createdAt: .now))
        precondition(store.note.contains("![[fixture.m4a]]"), "recording attachment inserted")
        await wait { speech.pending != nil }
        store.addPage()
        store.note = "另一个页面"
        store.pages[1].color = .pink
        speech.succeed("识别出的文字")
        await wait { store.pages[0].attachments[0].status == .completed }
        precondition(store.note == "另一个页面", "switching tabs must not redirect transcription")
        precondition(store.pages[0].content.contains("识别出的文字"), "transcript appended to source page")
        let document = root.appendingPathComponent("拖入的文档[1].pdf")
        try Data("document-fixture".utf8).write(to: document)
        await store.importFile(document, to: originalID)
        precondition(store.note == "另一个页面" && store.pages[0].files.count == 1, "drop keeps the captured target tab")
        let importedFile = store.pages[0].files[0]
        let importedURL = try store.storage.fileURL(importedFile)
        let importedData = try Data(contentsOf: importedURL)
        precondition(importedData == Data("document-fixture".utf8) && FileManager.default.fileExists(atPath: document.path), "file drop copies without moving original")
        precondition(!importedFile.filename.contains("[") && store.pages[0].content.contains("![[" + importedFile.filename + "]]"), "drop inserts safe Obsidian embed")
        let oldPageData = Data("{\"id\":\"301C511F-99FB-46B3-B9AA-9C5C691794A0\",\"title\":\"旧页面\",\"content\":\"旧内容\",\"attachments\":[]}".utf8)
        let oldPage = try JSONDecoder().decode(NotePage.self, from: oldPageData)
        precondition(oldPage.files.isEmpty && oldPage.content == "旧内容", "old pages migrate without file metadata")
        store.selectedPageID = originalID
        audio.onRecorded?(AudioRecording(url: audioFolder.appendingPathComponent("missing.m4a"), createdAt: .now))
        await wait { store.pages[0].attachments.last?.status == .failed }
        // Remove the deliberately missing fixture before testing successful export.
        store.pages[0].attachments.removeLast()
        let vault = root.appendingPathComponent("Vault")
        store.vaultURL = vault
        store.tasks = [TaskItem(title: "独立待办导出测试"), TaskItem(title: "已经完成", isCompleted: true, reminderAt: Date().addingTimeInterval(3600))]
        store.exportMarkdown()
        let sidebar = vault.appendingPathComponent("Sidebar")
        let copied = sidebar.appendingPathComponent("Recordings/fixture.m4a")
        let copiedData = try Data(contentsOf: copied)
        precondition(copiedData == Data("audio-fixture".utf8), "audio copied with note")
        let exports = try FileManager.default.contentsOfDirectory(at: sidebar, includingPropertiesForKeys: nil).filter { $0.pathExtension == "md" }
        precondition(exports.count == 1, "markdown exported")
        let exportedText = try String(contentsOf: exports[0], encoding: .utf8)
        precondition(exportedText.contains("识别出的文字") && exportedText.contains("![[fixture.m4a]]"), "export includes transcription and embed")
        precondition(exportedText == store.note, "note export is exactly the Markdown body without wrappers")
        precondition(!exportedText.contains("独立待办导出测试") && !exportedText.contains("待办事项"), "note file excludes tasks")
        precondition(!FileManager.default.fileExists(atPath: sidebar.appendingPathComponent("Tasks").path), "note action does not export tasks")
        store.exportTasks()
        let taskDirectory = sidebar.appendingPathComponent("Tasks")
        let taskExports = try FileManager.default.contentsOfDirectory(at: taskDirectory, includingPropertiesForKeys: nil)
        precondition(taskExports.count == 1, "separate task file created")
        let taskExportText = try String(contentsOf: taskExports[0], encoding: .utf8)
        precondition(taskExportText.contains("- [ ] 独立待办导出测试") && taskExportText.contains("- [x] 已经完成") && taskExportText.contains("提醒："), "task export retains completion and reminder")
        precondition(!taskExportText.contains("识别出的文字") && !taskExportText.contains("fixture.m4a"), "task file excludes note and audio")
        let unchangedNote = try String(contentsOf: exports[0], encoding: .utf8)
        precondition(unchangedNote == exportedText, "task export leaves existing note untouched")
        let copiedDocument = sidebar.appendingPathComponent("Attachments").appendingPathComponent(importedFile.filename)
        precondition(FileManager.default.fileExists(atPath: copiedDocument.path), "note export includes dropped files")
        store.storage.attachmentExportPath = "Assets/Files"
        store.storage.recordingExportPath = "Assets/Audio"
        store.exportMarkdown()
        precondition(FileManager.default.fileExists(atPath: vault.appendingPathComponent("Assets/Files").appendingPathComponent(importedFile.filename).path), "custom attachment export path")
        precondition(FileManager.default.fileExists(atPath: vault.appendingPathComponent("Assets/Audio/fixture.m4a").path), "custom recording export path")
        for invalid in ["../Escape", "/tmp/Escape", "Assets//Files", "Assets/./Files"] {
            do {
                _ = try store.storage.exportDirectory(in: vault, path: invalid)
                preconditionFailure("invalid export path accepted")
            } catch { }
        }
        let outside = root.appendingPathComponent("Outside")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: vault.appendingPathComponent("Escape"), withDestinationURL: outside)
        do {
            _ = try store.storage.exportDirectory(in: vault, path: "Escape/Deep")
            preconditionFailure("symlink escape accepted")
        } catch { }
        let restoredStorage = StorageLocations(defaults: defaults, baseURL: root.appendingPathComponent("Local"))
        precondition(restoredStorage.attachmentExportPath == "Assets/Files" && restoredStorage.recordingExportPath == "Assets/Audio", "storage paths persist")
        let holidays = HolidayCalendar(defaults: defaults)
        let regularWeek = holidays.summary(at: HolidayCalendar.parse("2026-10-28")!)
        precondition(regularWeek.daysUntilFirstRest == 3 && regularWeek.restCount == 2 && !regularWeek.isEstimated, "Monday to Sunday ordinary week")
        let makeupWeek = holidays.summary(at: HolidayCalendar.parse("2026-09-18")!)
        precondition(makeupWeek.restCount == 1 && makeupWeek.days.last?.isOff == false, "Sunday makeup workday is not a rest day")
        let nationalWeek = holidays.summary(at: HolidayCalendar.parse("2026-10-01")!)
        precondition(nationalWeek.restCount == 4 && nationalWeek.daysUntilFirstRest == 0, "holiday spanning weeks counts only this week")
        let nextWeek = holidays.summary(at: HolidayCalendar.parse("2026-10-08")!)
        precondition(nextWeek.restCount == 4 && nextWeek.days.first { $0.weekday == "周六" }?.isOff == false, "Saturday makeup excluded even during national holiday week")
        let unknownYear = holidays.summary(at: HolidayCalendar.parse("2027-01-04")!)
        precondition(unknownYear.isEstimated && unknownYear.text.contains("估算"), "missing annual schedule is explicitly an estimate")
        do {
            try holidays.importData(Data("{\"year\":2027,\"source\":\"fixture\",\"days\":[{\"date\":\"2027-02-30\",\"isOff\":true,\"name\":\"invalid\"}]}".utf8))
            preconditionFailure("invalid holiday date accepted")
        } catch { }
        try holidays.importData(Data("{\"year\":2027,\"source\":\"fixture\",\"days\":[{\"date\":\"2027-01-04\",\"isOff\":true,\"name\":\"测试假日\"},{\"date\":\"2027-01-09\",\"isOff\":false,\"name\":\"调休\"}]}".utf8))
        let importedWeek = holidays.summary(at: HolidayCalendar.parse("2027-01-04")!)
        precondition(!importedWeek.isEstimated && importedWeek.restCount == 2 && importedWeek.daysUntilFirstRest == 0, "annual calendar import overrides holidays and makeup days")
        let reloadedHolidays = HolidayCalendar(defaults: defaults)
        precondition(!reloadedHolidays.summary(at: HolidayCalendar.parse("2027-01-04")!).isEstimated, "annual calendar import persists")
        let restored = WorkspaceStore(defaults: defaults, audio: RecordingStore(directoryURL: audioFolder), speech: FakeSpeech(), notifications: NotificationService(backend: FakeNotificationBackend()), storage: StorageLocations(defaults: defaults, baseURL: root.appendingPathComponent("Local")))
        precondition(restored.pages.count == 2 && restored.pages[1].color == .pink && restored.pages[1].content == "另一个页面", "tabs persisted")
        precondition(restored.currentPage?.id == originalID, "selected tab persisted")
        precondition(restored.pages[0].files.first?.filename == importedFile.filename, "file metadata persists across relaunch")
        // Retry transitions from failure to queue, then completes without erasing an edited draft.
        store.pages[0].attachments[0].status = .failed
        store.retryTranscription(pageID: originalID, filename: "fixture.m4a")
        await wait { speech.pending != nil }
        store.note += "\n转写期间手动补充"
        speech.fail()
        await wait { store.pages[0].attachments[0].status == .failed }
        precondition(store.note.contains("转写期间手动补充"), "failure preserves user edits")
        // Older task JSON has no reminder field; retain its identity and content.
        let oldTask = try JSONDecoder().decode(TaskItem.self, from: Data("{\"id\":\"301C511F-99FB-46B3-B9AA-9C5C691794A0\",\"title\":\"旧待办\",\"isCompleted\":false}".utf8))
        precondition(oldTask.reminderAt == nil && oldTask.title == "旧待办", "legacy tasks retain content")
        let backend = FakeNotificationBackend()
        backend.authorization = .notDetermined
        let notifications = NotificationService(backend: backend)
        notifications.updateTasks([], requestPermission: false)
        await wait { !notifications.isSynchronizing }
        precondition(backend.requests == 0, "launch does not prompt for permission")
        var reminderTask = TaskItem(title: "买咖啡", reminderAt: Date().addingTimeInterval(600))
        let reminderID = NotificationService.taskPrefix + reminderTask.id.uuidString
        notifications.updateTasks([reminderTask])
        await wait { !notifications.isSynchronizing }
        precondition(backend.requests == 1 && backend.alerts[reminderID]?.body == "买咖啡", "first reminder requests permission and schedules")
        let originalDate = backend.alerts[reminderID]!.date
        reminderTask.title = "买茶"
        notifications.updateTasks([reminderTask])
        await wait { !notifications.isSynchronizing }
        precondition(backend.alerts.count == 1 && backend.alerts[reminderID]?.date == originalDate && backend.alerts[reminderID]?.body == "买茶", "editing title does not duplicate or postpone reminder")
        reminderTask.isCompleted = true
        notifications.updateTasks([reminderTask])
        await wait { !notifications.isSynchronizing }
        precondition(backend.alerts[reminderID] == nil && backend.removedDelivered.contains(reminderID), "completion clears notification")
        reminderTask.isCompleted = false
        reminderTask.reminderAt = .now.addingTimeInterval(-60)
        notifications.updateTasks([reminderTask])
        await wait { !notifications.isSynchronizing }
        precondition(backend.alerts.isEmpty, "overdue reminder is not replayed")
        backend.suspendNextAdd = true
        reminderTask.reminderAt = .now.addingTimeInterval(1200)
        notifications.updateTasks([reminderTask])
        await wait { backend.suspendedAdd != nil }
        notifications.updateTasks([])
        backend.resumeAdd()
        await wait { !notifications.isSynchronizing }
        precondition(backend.alerts.isEmpty, "delete wins over in-flight scheduling")
        let deadline = Date().addingTimeInterval(1500)
        notifications.setPomodoro(deadline: deadline, isBreak: false)
        await wait { !notifications.isSynchronizing }
        precondition(backend.alerts[NotificationService.timerID]?.date == deadline && backend.alerts[NotificationService.timerID]?.title == "专注完成", "focus completion scheduled at deadline")
        notifications.setPomodoro(deadline: nil, isBreak: false)
        await wait { !notifications.isSynchronizing }
        precondition(backend.alerts[NotificationService.timerID] == nil, "pause or reset cancels timer notification")
        backend.suspendNextAdd = true
        notifications.setPomodoro(deadline: deadline, isBreak: true)
        await wait { backend.suspendedAdd != nil }
        notifications.setPomodoro(deadline: nil, isBreak: true)
        backend.resumeAdd()
        await wait { !notifications.isSynchronizing }
        precondition(backend.alerts.isEmpty, "reset wins over in-flight timer add")
        backend.authorization = .denied
        notifications.setPomodoro(deadline: deadline, isBreak: false)
        await wait { !notifications.isSynchronizing }
        precondition(notifications.issue != nil && backend.alerts.isEmpty, "denial provides actionable feedback")
        backend.authorization = .allowed
        backend.addError = NSError(domain: "Fixture", code: 1)
        await notifications.refreshAuthorization()
        await wait { !notifications.isSynchronizing }
        precondition(notifications.issue?.contains("提醒未能安排") == true, "scheduling errors are visible")
        backend.addError = nil
        await notifications.refreshAuthorization()
        await wait { !notifications.isSynchronizing }
        precondition(notifications.issue == nil && backend.alerts.count == 1, "settings retry restores scheduling")
        // Exercise the actual store callbacks used by task rows, not only the scheduler in isolation.
        let edited = TaskItem(title: "移除提醒", reminderAt: Date().addingTimeInterval(600))
        let untouched = TaskItem(title: "另一条提醒", reminderAt: Date().addingTimeInterval(1200))
        store.tasks = [edited, untouched]
        await wait { !store.notifications.isSynchronizing }
        let rowSnapshot = store.tasks[0]
        store.updateTask(id: rowSnapshot.id) { task in
            // Reading the store is safe because only a detached task value is being mutated.
            precondition(store.tasks.count == 2, "task update does not borrow the backing array")
            task.reminderAt = nil
        }
        await wait { !store.notifications.isSynchronizing }
        let removedReminderID = NotificationService.taskPrefix + edited.id.uuidString
        let otherReminderID = NotificationService.taskPrefix + untouched.id.uuidString
        precondition(store.tasks.count == 2 && store.tasks[0].reminderAt == nil, "remove reminder retains task")
        precondition(workspaceBackend.alerts[removedReminderID] == nil && workspaceBackend.alerts[otherReminderID] != nil, "remove reminder cancels only its own notification")
        store.updateTask(id: rowSnapshot.id) { $0.title = "编辑后的待办" }
        store.updateTask(id: rowSnapshot.id) { $0.reminderAt = Date().addingTimeInterval(1800) }
        store.updateTask(id: rowSnapshot.id) { $0.isCompleted = true }
        await wait { !store.notifications.isSynchronizing }
        precondition(store.tasks[0].title == "编辑后的待办" && workspaceBackend.alerts[removedReminderID] == nil, "editing and completing remain safe")
        store.removeTask(id: rowSnapshot.id)
        store.updateTask(id: rowSnapshot.id) { $0.reminderAt = Date().addingTimeInterval(60) }
        store.removeTask(id: rowSnapshot.id)
        await wait { !store.notifications.isSynchronizing }
        precondition(store.tasks.count == 1 && store.tasks[0].id == untouched.id, "stale row callbacks do not revive deleted tasks or modify neighbors")
        precondition(workspaceBackend.alerts[otherReminderID] != nil, "deleting another row retains the remaining reminder")
        // Edge placement uses visible screen bounds, not assumptions about a single origin-(0,0) display.
        let screen = CGRect(x: 0, y: 60, width: 1440, height: 840)
        let leftWindow = CGRect(x: 12, y: 200, width: 420, height: 700)
        precondition(SidebarGeometry.nearbyEdge(frame: leftWindow, screen: screen) == .left, "near left edge snaps")
        let centerWindow = CGRect(x: 500, y: 200, width: 420, height: 700)
        precondition(SidebarGeometry.nearbyEdge(frame: centerWindow, screen: screen) == nil, "ordinary movement does not collapse")
        let rightWindow = CGRect(x: 1010, y: 250, width: 420, height: 700)
        precondition(SidebarGeometry.nearbyEdge(frame: rightWindow, screen: screen) == .right, "near right edge snaps")
        let docked = SidebarGeometry.dockedFrame(rightWindow, screen: screen, edge: .right)
        precondition(docked.maxX == screen.maxX && docked.maxY <= screen.maxY, "docked window avoids menu bar")
        let secondScreen = CGRect(x: -1920, y: -200, width: 1920, height: 1080)
        let secondDock = SidebarGeometry.dockedFrame(leftWindow, screen: secondScreen, edge: .left)
        precondition(secondDock.minX == -1920 && secondDock.minY >= secondScreen.minY, "negative monitor coordinates")
        for edge in [SidebarEdge.left, .right] {
            let handle = SidebarGeometry.handleFrame(window: secondDock, screen: secondScreen, edge: edge)
            precondition(secondScreen.contains(handle) && handle.width >= 24 && handle.height >= 44, "handle stays visible and clickable")
        }
        let smallScreen = CGRect(x: 80, y: 40, width: 800, height: 600)
        let smallDock = SidebarGeometry.dockedFrame(leftWindow, screen: smallScreen, edge: .right)
        precondition(smallScreen.contains(smallDock), "smaller display bounds are respected")
        let timerBackend = FakeNotificationBackend()
        let timerNotifications = NotificationService(backend: timerBackend)
        let sharedTimer = PomodoroTimer(defaults: defaults, notifications: timerNotifications)
        sharedTimer.focusDuration = 1500
        sharedTimer.breakDuration = 300
        precondition(sharedTimer.seconds() == 1500 && !sharedTimer.isRunning, "idle timer shows configured focus duration")
        sharedTimer.toggle()
        await wait { !timerNotifications.isSynchronizing }
        let focusEnd = sharedTimer.deadline!
        precondition(sharedTimer.isRunning && sharedTimer.seconds(at: focusEnd.addingTimeInterval(-42)) == 42, "shared countdown uses deadline even with no visible view")
        sharedTimer.toggle()
        await wait { !timerNotifications.isSynchronizing }
        precondition(!sharedTimer.isRunning && sharedTimer.hasStarted && timerBackend.alerts[NotificationService.timerID] == nil, "quick pause cancels completion notification")
        sharedTimer.toggle()
        await wait { !timerNotifications.isSynchronizing }
        precondition(sharedTimer.isRunning, "quick resume shares existing session")
        sharedTimer.reset()
        sharedTimer.start(isBreak: true)
        await wait { !timerNotifications.isSynchronizing }
        precondition(sharedTimer.isBreak && sharedTimer.isRunning && timerBackend.alerts[NotificationService.timerID]?.title == "休息结束", "quick rest uses same timer and notification service")
        let restEnd = sharedTimer.deadline!
        sharedTimer.finishIfNeeded(at: restEnd.addingTimeInterval(1))
        precondition(!sharedTimer.isRunning && sharedTimer.seconds() == 0 && timerBackend.alerts[NotificationService.timerID] != nil, "finishing without a visible view retains system completion alert")
        sharedTimer.reset()
        await wait { !timerNotifications.isSynchronizing }
        precondition(!sharedTimer.hasStarted && timerBackend.alerts.isEmpty, "quick end cancels timer notification")
        for edge in [SidebarEdge.left, .right] {
            let tab = SidebarGeometry.handleFrame(window: secondDock, screen: secondScreen, edge: edge)
            let quick = SidebarGeometry.quickControlsFrame(handle: tab, screen: secondScreen, edge: edge)
            precondition(secondScreen.contains(quick) && !tab.intersects(quick), "hover controls sit inside display without covering edge tab")
        }
        // Deleting a background tab preserves selection; deleting the last creates a fresh draft.
        let deletionSuite = suite + "-deletion"
        let deletionDefaults = UserDefaults(suiteName: deletionSuite)!
        defer { deletionDefaults.removePersistentDomain(forName: deletionSuite) }
        let deletionStore = WorkspaceStore(defaults: deletionDefaults, audio: audio, speech: FakeSpeech(), notifications: NotificationService(backend: FakeNotificationBackend()))
        let firstPageID = deletionStore.currentPage!.id
        deletionStore.addPage()
        let secondPageID = deletionStore.currentPage!.id
        deletionStore.note = "保留内容"
        deletionStore.removePage(id: firstPageID)
        precondition(deletionStore.currentPage?.id == secondPageID && deletionStore.note == "保留内容", "background deletion keeps selection and content")
        deletionStore.removePage(id: secondPageID)
        precondition(deletionStore.pages.count == 1 && deletionStore.note.isEmpty && deletionStore.currentPage?.id != secondPageID, "last deletion creates an empty draft")
        let persistedPages = try JSONDecoder().decode([NotePage].self, from: deletionDefaults.data(forKey: "notePages")!)
        precondition(persistedPages.count == 1 && persistedPages[0].content.isEmpty && persistedPages[0].id == deletionStore.selectedPageID, "deletion and new selection persist")
        let beforeDropID = deletionStore.currentPage!.id
        deletionStore.note = "当前笔记不应收到拖入文件"
        await deletionStore.importFilesAsNewNote([document, audioURL])
        precondition(deletionStore.pages.count == 2 && deletionStore.currentPage?.id != beforeDropID, "one drop creates and selects one new note")
        precondition(deletionStore.currentPage?.files.count == 2, "multiple files from one drop share the new note")
        precondition(deletionStore.pages.first(where: { $0.id == beforeDropID })?.content == "当前笔记不应收到拖入文件", "drop preserves previous note")
        precondition(deletionStore.currentPage?.title == document.deletingPathExtension().lastPathComponent, "drop names note after first file")
        print("PASS: migration, automatic attachment, tab-safe transcription, failure/retry, speech error recovery, persistence, Markdown/audio export and notification scheduling/cancellation/races; file import/export, storage paths, holiday/makeup weeks; task row exclusivity and stale callbacks; sidebar edge geometry; shared timer and hover panel geometry")
    }

    @MainActor private static func checkLocalization() async throws {
        let suite = "SidebarLanguageChecks-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        precondition(AppLanguage.current(defaults: defaults) == .system)
        defaults.set("en", forKey: AppLanguage.preferenceKey)
        precondition(AppLanguage.current(defaults: UserDefaults(suiteName: suite)!) == .english, "language persists")
        defaults.set("unsupported", forKey: AppLanguage.preferenceKey)
        precondition(AppLanguage.current(defaults: defaults) == .system, "invalid preference safely follows system")
        precondition(AppLanguage.system.resolved(preferredLanguages: ["zh-TW"]) == .chinese)
        precondition(AppLanguage.system.resolved(preferredLanguages: ["fr-FR", "zh-Hans"]) == .english)
        precondition(L10n.render("设置", language: .english) == "Settings")
        precondition(L10n.render("设置", language: .chinese) == "设置")
        precondition(L10n.render("距本周首休还有 {0} 天 · 休 {1} 天", arguments: ["2", "3"], language: .english) == "2 days until this week's first day off · 3 days off")
        precondition(L10n.render("音频及引用笔记已保存到 {0}/{1}。", arguments: ["Vault {1}", "Audio"], language: .english) == "Audio and its linked note were saved to Vault {1}/Audio.", "argument tokens must stay literal")
        for (key, value) in L10n.english {
            let regex = try NSRegularExpression(pattern: #"\{[0-9]+\}"#)
            func tokens(_ text: String) -> [String] {
                let source = text as NSString
                return regex.matches(in: text, range: NSRange(location: 0, length: source.length)).map { source.substring(with: $0.range) }.sorted()
            }
            precondition(!value.isEmpty && tokens(key) == tokens(value), "translation retains every interpolation")
        }

        // The argument domain is process-local; these checks never alter real user preferences.
        let previous = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
        defer { UserDefaults.standard.setVolatileDomain(previous, forName: UserDefaults.argumentDomain) }
        func choose(_ language: String) {
            var arguments = previous
            arguments[AppLanguage.preferenceKey] = language
            UserDefaults.standard.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain)
        }
        choose("zh-Hans")
        let backend = FakeNotificationBackend()
        let service = NotificationService(backend: backend)
        let timer = PomodoroTimer(defaults: defaults, notifications: service)
        let reminder = Date().addingTimeInterval(600)
        let task = TaskItem(title: "Keep my task 原文", reminderAt: reminder)
        service.updateTasks([task], requestPermission: false)
        timer.start(isBreak: false)
        let deadline = timer.deadline!
        await wait { !service.isSynchronizing }
        choose("en")
        precondition(L10n.text("设置") == "Settings", "current preference is read immediately")
        service.refreshLanguage(tasks: [task])
        await wait { !service.isSynchronizing }
        precondition(backend.alerts[NotificationService.timerID]?.title == "Focus Finished")
        precondition(backend.alerts[NotificationService.timerID]?.date == deadline && timer.deadline == deadline && timer.isRunning, "language does not restart the timer")
        let taskID = NotificationService.taskPrefix + task.id.uuidString
        precondition(backend.alerts[taskID]?.title == "Task Reminder" && backend.alerts[taskID]?.body == task.title && backend.alerts[taskID]?.date == reminder, "task content and reminder time are preserved")
        choose("zh-Hans")
        service.refreshLanguage(tasks: [task])
        await wait { !service.isSynchronizing }
        precondition(backend.alerts[NotificationService.timerID]?.title == "专注完成")
        timer.reset()
        await wait { !service.isSynchronizing }
        print("PASS: bilingual copy, interpolation safety, saved language, system fallback, live switching and notification deadlines")
    }

    @MainActor private static func wait(_ condition: () -> Bool) async {
        for _ in 0..<200 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        preconditionFailure("asynchronous check timed out")
    }
}
