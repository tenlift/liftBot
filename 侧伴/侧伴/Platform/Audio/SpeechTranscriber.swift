import SidebarCore
import Speech
import AVFoundation

/// One file at a time, on device only. No audio upload fallback.
@MainActor protocol TranscriptionProviding {
    func transcribe(_ url: URL, locale: String) async throws -> String
}

@MainActor final class SpeechTranscriber: TranscriptionProviding {
    private var jobID: UUID?
    private var recognizer: SFSpeechRecognizer?
    private var recognition: SFSpeechRecognitionTask?
    private var timeout: Task<Void, Never>?
    private var completion: CheckedContinuation<String, Error>?

    func transcribe(_ url: URL, locale: String) async throws -> String {
        let authorization = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard authorization == .authorized else {
            throw Failure(L10n.text("未获得语音识别权限。请在系统设置 → 隐私与安全性 → 语音识别中允许访问，再点击重试。"))
        }
        if #available(macOS 26.0, *), Speech.SpeechTranscriber.isAvailable,
           let supportedLocale = await Speech.SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: locale)) {
            do { return try await transcribeWithAnalyzer(url, locale: supportedLocale) }
            catch { throw Failure(Self.readableError(error)) }
        }
        return try await transcribeLegacy(url, locale: locale)
    }

    @available(macOS 26.0, *)
    private func transcribeWithAnalyzer(_ url: URL, locale: Locale) async throws -> String {
        let module = Speech.SpeechTranscriber(locale: locale, preset: .transcription)
        if let installation = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
            try await installation.downloadAndInstall()
        }
        let analyzer = SpeechAnalyzer(modules: [module])
        do {
            return try await withThrowingTaskGroup(of: String.self) { group in
                group.addTask {
                    let audioFile = try AVAudioFile(forReading: url)
                    try await analyzer.start(inputAudioFile: audioFile, finishAfterFile: true)
                    var text = ""
                    for try await result in module.results { text += String(result.text.characters) }
                    let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !cleaned.isEmpty else { throw Failure(L10n.text("未识别到语音，音频已保留。")) }
                    return cleaned
                }
                group.addTask {
                    try await Task.sleep(for: .seconds(120))
                    await analyzer.cancelAndFinishNow()
                    throw Failure(L10n.text("识别超时，音频已保留，可重试；长录音建议分段。"))
                }
                do {
                    let result = try await group.next() ?? ""
                    group.cancelAll()
                    return result
                } catch {
                    group.cancelAll()
                    await analyzer.cancelAndFinishNow()
                    throw error
                }
            }
        } catch {
            await analyzer.cancelAndFinishNow()
            throw error
        }
    }

    private func transcribeLegacy(_ url: URL, locale: String) async throws -> String {
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: locale)),
              recognizer.supportsOnDeviceRecognition else {
            throw Failure(L10n.text("此设备或当前语言暂不支持本地识别。请检查系统语言资源，或在设置中更换识别语言后重试。"))
        }
        guard recognizer.isAvailable else { throw Failure(L10n.text("语音识别暂不可用，请稍后重试。")) }
        self.recognizer = recognizer
        let request = SFSpeechURLRecognitionRequest(url: url)
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = false
        request.taskHint = .dictation
        return try await withCheckedThrowingContinuation { continuation in
            let id = UUID()
            jobID = id
            completion = continuation
            recognition = recognizer.recognitionTask(with: request) { [weak self] result, error in
                let text = result?.isFinal == true ? result?.bestTranscription.formattedString : nil
                let reason = error.map { Self.readableError($0) }
                Task { @MainActor [weak self] in
                    if let text {
                        self?.finish(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .failure(Failure(L10n.text("未识别到语音，可以重试或直接编辑笔记。"))) : .success(text), id: id)
                    } else if let reason { self?.finish(.failure(Failure(reason)), id: id) }
                }
            }
            timeout = Task { [weak self] in
                try? await Task.sleep(for: .seconds(120))
                guard !Task.isCancelled else { return }
                self?.finish(.failure(Failure(L10n.text("识别超时，音频已保留，可点击重试。长录音建议分段录制。"))), id: id)
            }
        }
    }

    private func finish(_ result: Result<String, Error>, id: UUID) {
        guard jobID == id, let continuation = completion else { return }
        jobID = nil
        completion = nil
        timeout?.cancel(); timeout = nil
        recognition?.cancel(); recognition = nil
        recognizer = nil
        continuation.resume(with: result)
    }

    nonisolated static func readableError(_ error: Error) -> String {
        if let failure = error as? Failure { return failure.errorDescription ?? L10n.text("识别失败") }
        let systemError = error as NSError
        let detail = "（\(systemError.domain) · \(systemError.code)）"
        switch (systemError.domain, systemError.code) {
        case ("kAFAssistantErrorDomain", 1101), ("kAFAssistantErrorDomain", 1107):
            return L10n.text("本地语音服务连接中断。音频已保留；请检查键盘设置中的听写语言资源及语音识别权限，再重试。") + detail
        case ("kLSRErrorDomain", 102):
            return L10n.text("尚未安装识别语言资源，请联网下载对应语言模型后重试。") + detail
        case ("kLSRErrorDomain", 201):
            return L10n.text("系统听写未启用，请到键盘设置启用听写后重试。") + detail
        case ("kAFAssistantErrorDomain", 1110):
            return L10n.text("未识别到语音，请检查录音音量或切换识别语言后重试。") + detail
        case ("kAFAssistantErrorDomain", 1700):
            return L10n.text("语音识别未获授权，请在系统隐私设置中允许访问。") + detail
        default:
            return error.localizedDescription + detail
        }
    }

    struct Failure: LocalizedError {
        let errorDescription: String?
        init(_ message: String) { errorDescription = message }
    }
}
