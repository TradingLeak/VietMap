import Foundation
import Combine
import AVFoundation
import Speech

/// Nhận dạng chỉ để điền text; không tự gửi tìm kiếm khi đang nói.
@MainActor
final class VoiceSearchController: ObservableObject {
    @Published private(set) var transcript = ""
    @Published private(set) var isRecording = false
    @Published private(set) var isRequesting = false
    @Published private(set) var error: String?
    private let engine = AVAudioEngine()
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "vi-VN"))
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var generation = UUID()
    private var tapInstalled = false
    private var sessionActive = false
    private var interruptionObserver: NSObjectProtocol?

    init() {
        interruptionObserver = NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] notification in
            guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: raw) == .began else { return }
            Task { @MainActor [weak self] in
                guard let self, self.isRecording || self.isRequesting else { return }
                self.stop(); self.error = "Nhận dạng đã dừng do gián đoạn âm thanh."
            }
        }
    }
    deinit { if let interruptionObserver { NotificationCenter.default.removeObserver(interruptionObserver) } }

    func start() {
        guard !isRecording, !isRequesting else { return }
        let token = UUID(); generation = token; isRequesting = true; error = nil
        Task {
            let speechStatus = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
            }
            guard generation == token else { return }
            guard speechStatus == .authorized else { isRequesting = false; error = "Không có quyền nhận dạng giọng nói. Hãy kiểm tra Cài đặt."; return }
            let mic = await withCheckedContinuation { continuation in
                AVAudioSession.sharedInstance().requestRecordPermission { continuation.resume(returning: $0) }
            }
            guard generation == token else { return }
            guard mic else { isRequesting = false; error = "Microphone bị từ chối. Hãy kiểm tra Cài đặt."; return }
            guard let recognizer, recognizer.isAvailable else { isRequesting = false; error = "Nhận dạng tiếng Việt hiện không khả dụng."; return }
            do {
                AudioAlertManager.shared.setRecordingActive(true)
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .allowBluetooth])
                try session.setActive(true); sessionActive = true
                let input = engine.inputNode
                let format = input.outputFormat(forBus: 0)
                guard format.sampleRate > 0, format.channelCount > 0 else { throw VoiceError.inputUnavailable }
                let request = SFSpeechAudioBufferRecognitionRequest()
                request.shouldReportPartialResults = true
                if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
                self.request = request; transcript = ""
                input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in request.append(buffer) }
                tapInstalled = true
                task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                    Task { @MainActor [weak self] in
                        guard let self, self.generation == token else { return }
                        if let result { self.transcript = result.bestTranscription.formattedString }
                        if let error { self.stop(); self.error = "Không nhận dạng được giọng nói: \(error.localizedDescription)" }
                        else if result?.isFinal == true { self.stop() }
                    }
                }
                engine.prepare(); try engine.start()
                isRequesting = false; isRecording = true
            } catch {
                stop(); self.error = "Không thể bật microphone: \(error.localizedDescription)"
            }
        }
    }
    func stop() {
        generation = UUID(); isRequesting = false; isRecording = false
        if engine.isRunning { engine.stop() }
        if tapInstalled { engine.inputNode.removeTap(onBus: 0); tapInstalled = false }
        request?.endAudio(); request = nil
        task?.cancel(); task = nil
        if sessionActive {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            sessionActive = false
        }
        AudioAlertManager.shared.setRecordingActive(false)
    }
    private enum VoiceError: LocalizedError {
        case inputUnavailable
        var errorDescription: String? { "Thiết bị không có đầu vào âm thanh khả dụng." }
    }
}
