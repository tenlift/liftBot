import SidebarCore
import AppKit
import AVFoundation
import Observation

struct AudioRecording: Identifiable {
    let url: URL
    let createdAt: Date
    var id: String { url.lastPathComponent }
}

/// Owns microphone capture and playback. Audio stays local until explicitly exported.
@MainActor @Observable final class RecordingStore: NSObject, AVAudioRecorderDelegate, AVAudioPlayerDelegate {
    private(set) var recordings: [AudioRecording] = []
    private(set) var isRecording = false
    private(set) var isRequestingPermission = false
    private(set) var elapsed: TimeInterval = 0
    private(set) var level: Float = 0
    private(set) var playingID: String?
    var errorMessage: String?
    @ObservationIgnored var onRecorded: ((AudioRecording) -> Void)?
    @ObservationIgnored private var recorder: AVAudioRecorder?
    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var meterTask: Task<Void, Never>?

    @ObservationIgnored var directoryProvider: (() throws -> URL)?
    @ObservationIgnored var additionalDirectories: (() -> [URL])?
    @ObservationIgnored private let directoryOverride: URL?

    init(directoryURL: URL? = nil) {
        directoryOverride = directoryURL
        super.init()
        reload()
        NotificationCenter.default.addObserver(self, selector: #selector(willTerminate), name: NSApplication.willTerminateNotification, object: nil)
    }

    var directory: URL {
        get throws {
            if let directoryOverride {
                try FileManager.default.createDirectory(at: directoryOverride, withIntermediateDirectories: true)
                return directoryOverride
            }
            if let directoryProvider { return try directoryProvider() }
            let root = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let folder = root.appendingPathComponent(Bundle.main.bundleIdentifier ?? "Sidebar", isDirectory: true).appendingPathComponent("Recordings", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            return folder
        }
    }

    func start() async {
        guard !isRecording, !isRequestingPermission else { return }
        isRequestingPermission = true
        defer { isRequestingPermission = false }
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        let allowed: Bool
        switch status {
        case .authorized: allowed = true
        case .notDetermined: allowed = await AVCaptureDevice.requestAccess(for: .audio)
        default: allowed = false
        }
        guard allowed else {
            errorMessage = L10n.text("无法使用麦克风。请在系统设置 → 隐私与安全性 → 麦克风中允许侧伴访问，然后重试。")
            return
        }
        stopPlayback()
        do {
            let filename = "录音-\(Int(Date().timeIntervalSince1970))-\(UUID().uuidString.prefix(8)).m4a"
            let url = try directory.appendingPathComponent(filename)
            let capture = try AVAudioRecorder(url: url, settings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ])
            capture.delegate = self
            capture.isMeteringEnabled = true
            guard capture.prepareToRecord(), capture.record() else {
                try? FileManager.default.removeItem(at: url)
                errorMessage = L10n.text("无法启动录音，请检查麦克风是否连接或被其他应用独占。")
                return
            }
            recorder = capture
            isRecording = true
            elapsed = 0
            meterTask = Task { [weak self] in
                while !Task.isCancelled {
                    guard let self, let recorder = self.recorder, self.isRecording else { return }
                    recorder.updateMeters()
                    self.elapsed = recorder.currentTime
                    self.level = max(0, min(1, pow(10, recorder.averagePower(forChannel: 0) / 20)))
                    try? await Task.sleep(for: .milliseconds(100))
                }
            }
        } catch { errorMessage = L10n.text("录音失败：{0}", String(describing: error.localizedDescription)) }
    }

    func stop(publishRecording: Bool = true) {
        guard isRecording else { return }
        elapsed = recorder?.currentTime ?? elapsed
        let url = recorder?.url
        recorder?.stop()
        recorder = nil
        finishCapture()
        if publishRecording, let url { publish(url) }
    }

    private func publish(_ url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        onRecorded?(AudioRecording(url: url, createdAt: .now))
    }

    func recording(named filename: String) -> AudioRecording? {
        recordings.first { $0.id == filename }
    }

    private func finishCapture() {
        isRecording = false
        level = 0
        meterTask?.cancel()
        meterTask = nil
        reload()
    }

    @objc private func willTerminate() { stop(publishRecording: false); stopPlayback() }

    func reload() {
        do {
            let main = try directory
            let directories = Set([main] + (additionalDirectories?() ?? []))
            let files = directories.flatMap { url in
                (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.creationDateKey], options: .skipsHiddenFiles)) ?? []
            }
            recordings = files
                .filter { $0.pathExtension == "m4a" }
                .map { AudioRecording(url: $0, createdAt: (try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast) }
                .sorted { $0.createdAt > $1.createdAt }
        } catch { errorMessage = L10n.text("无法读取本机录音：{0}", String(describing: error.localizedDescription)) }
    }

    func play(_ recording: AudioRecording) {
        guard !isRecording else { return }
        if playingID == recording.id { stopPlayback(); return }
        stopPlayback()
        do {
            let playback = try AVAudioPlayer(contentsOf: recording.url)
            playback.delegate = self
            guard playback.play() else { errorMessage = L10n.text("无法播放这段录音。"); return }
            player = playback
            playingID = recording.id
        } catch { errorMessage = L10n.text("播放失败：{0}", String(describing: error.localizedDescription)) }
    }

    func stopPlayback() { player?.stop(); player = nil; playingID = nil }

    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        let identity = ObjectIdentifier(recorder)
        Task { @MainActor [weak self] in
            guard let self, let current = self.recorder, ObjectIdentifier(current) == identity, self.isRecording else { return }
            self.recorder = nil
            self.finishCapture()
            self.publish(current.url)
            if !flag { self.errorMessage = L10n.text("录音意外中断，请检查已保存的音频。") }
        }
    }

    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        let identity = ObjectIdentifier(recorder)
        Task { @MainActor [weak self] in
            guard let self, let current = self.recorder, ObjectIdentifier(current) == identity else { return }
            self.stop()
            self.errorMessage = L10n.text("音频编码失败，请检查麦克风后重试。")
        }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let identity = ObjectIdentifier(player)
        Task { @MainActor [weak self] in
            guard let self, let current = self.player, ObjectIdentifier(current) == identity else { return }
            self.stopPlayback()
            if !flag { self.errorMessage = L10n.text("播放中断，请重试。") }
        }
    }
}
