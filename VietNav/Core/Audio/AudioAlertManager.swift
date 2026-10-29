import Foundation
import Combine
import AVFoundation

public enum AlertPriority: Int, Comparable, CaseIterable {
    case low = 0, normal, high, critical
    public static func < (lhs: AlertPriority, rhs: AlertPriority) -> Bool { lhs.rawValue < rhs.rawValue }
}
public enum AlertSound: String, CaseIterable { case beep, dingDong, warning, radar }
public enum AlertCategory: String, CaseIterable {
    case navigation, overspeed, camera, roadSign, toll, railway, general
    public var title: String {
        switch self {
        case .navigation: return "Chỉ dẫn đường"
        case .overspeed: return "Vượt tốc độ"
        case .camera: return "Camera"
        case .roadSign: return "Biển báo"
        case .toll: return "Trạm thu phí"
        case .railway: return "Giao cắt đường sắt"
        case .general: return "Thông báo khác"
        }
    }
}
public enum AlertDeliveryResult: Equatable { case accepted, suppressed, busy }

public struct AlertRequest {
    public let priority: AlertPriority
    public let text: String
    public let sound: AlertSound?
    public let interruptsCurrent: Bool
    public let category: AlertCategory
    /// Hết hạn trong hàng đợi để không đọc chỉ dẫn giao thông cũ.
    public let createdAt: Date
    public let maxAge: TimeInterval
    public init(priority: AlertPriority = .normal, text: String, sound: AlertSound? = nil,
                interruptsCurrent: Bool = false, category: AlertCategory = .general,
                createdAt: Date = Date(), maxAge: TimeInterval = 20) {
        self.priority = priority; self.text = text; self.sound = sound; self.interruptsCurrent = interruptsCurrent
        self.category = category; self.createdAt = createdAt; self.maxAge = maxAge
    }
}

/// Backend tách riêng để kiểm thử thứ tự mà không cần loa, audio session hoặc TTS thật.
@MainActor
protocol AlertAudioOutput: AnyObject {
    func activate() throws
    func play(sound: AlertSound, volume: Float, completion: @escaping () -> Void) -> Bool
    func speak(_ utterance: AVSpeechUtterance, completion: @escaping () -> Void)
    func stop()
    func deactivate()
}

/// Một bộ điều phối dùng chung cho điều hướng và cảnh báo giao thông.
@MainActor
public final class AudioAlertManager: NSObject, ObservableObject {
    public static let shared = AudioAlertManager(output: SystemAlertAudioOutput(), defaults: .standard)
    @Published public var isMuted: Bool { didSet { defaults.set(isMuted, forKey: "audio.muted"); if isMuted { stopAll() } } }
    @Published public var volume: Float { didSet { volume = safeVolume; defaults.set(volume, forKey: "audio.volume") } }
    @Published public var speechRate: Float { didSet { speechRate = safeRate; defaults.set(speechRate, forKey: "audio.rate") } }
    @Published public var voiceIdentifier: String { didSet { defaults.set(voiceIdentifier, forKey: "audio.voice") } }
    @Published public private(set) var disabledCategories: Set<AlertCategory>
    @Published public private(set) var isPlaying = false
    @Published public private(set) var lastError: String?

    private let defaults: UserDefaults
    private let output: AlertAudioOutput
    private let clock: () -> Date
    private var alertQueue: [AlertRequest] = []
    private var current: AlertRequest?
    private var currentToken = UUID()
    private var interrupted = false
    private var recordingActive = false
    private var observers: [NSObjectProtocol] = []
    private let queueLimit = 16
    private var safeVolume: Float { volume.isFinite ? min(1, max(0, volume)) : 1 }
    private var safeRate: Float { speechRate.isFinite ? min(AVSpeechUtteranceMaximumSpeechRate, max(AVSpeechUtteranceMinimumSpeechRate, speechRate)) : 0.52 }

    init(output: AlertAudioOutput, defaults: UserDefaults, clock: @escaping () -> Date = Date.init) {
        self.output = output; self.defaults = defaults; self.clock = clock
        isMuted = defaults.bool(forKey: "audio.muted")
        let storedVolume: Float = defaults.object(forKey: "audio.volume") == nil ? 1 : defaults.float(forKey: "audio.volume")
        let storedRate: Float = defaults.object(forKey: "audio.rate") == nil ? 0.52 : defaults.float(forKey: "audio.rate")
        volume = storedVolume.isFinite ? min(1, max(0, storedVolume)) : 1
        speechRate = storedRate.isFinite ? min(AVSpeechUtteranceMaximumSpeechRate, max(AVSpeechUtteranceMinimumSpeechRate, storedRate)) : 0.52
        voiceIdentifier = defaults.string(forKey: "audio.voice") ?? "com.apple.ttsbundle.Linh-compact"
        disabledCategories = Set((defaults.stringArray(forKey: "audio.disabledCategories") ?? []).compactMap(AlertCategory.init(rawValue:)))
        super.init()
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] notification in
                guard let value = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                      let type = AVAudioSession.InterruptionType(rawValue: value) else { return }
                Task { @MainActor [weak self] in self?.handleInterruption(began: type == .began) }
            },
            center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] notification in
                guard let value = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                      let reason = AVAudioSession.RouteChangeReason(rawValue: value), reason == .oldDeviceUnavailable else { return }
                Task { @MainActor [weak self] in self?.stopAll() }
            }
        ]
    }
    deinit { observers.forEach { NotificationCenter.default.removeObserver($0) } }

    public func isCategoryEnabled(_ category: AlertCategory) -> Bool { !disabledCategories.contains(category) }
    public func setCategory(_ category: AlertCategory, enabled: Bool) {
        if enabled { disabledCategories.remove(category) } else { disabledCategories.insert(category); cancel(category: category) }
        defaults.set(disabledCategories.map(\.rawValue).sorted(), forKey: "audio.disabledCategories")
    }

    /// Trả về accepted khi được nhận vào hàng đợi, không bảo đảm đã được nghe.
    @discardableResult
    public func submit(_ request: AlertRequest, onlyIfIdle: Bool = false) -> AlertDeliveryResult {
        guard !isMuted, isCategoryEnabled(request.category), !request.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              request.maxAge.isFinite, request.maxAge > 0, clock().timeIntervalSince(request.createdAt) <= request.maxAge,
              clock().timeIntervalSince(request.createdAt) >= -5 else { return .suppressed }
        guard !interrupted, !recordingActive else { return .busy }
        removeExpired()
        if (onlyIfIdle || request.priority == .low) && (current != nil || !alertQueue.isEmpty) { return .busy }
        let shouldInterrupt = current.map { request.priority == .critical || (request.interruptsCurrent && request.priority >= $0.priority) } ?? false
        if alertQueue.count >= queueLimit && !shouldInterrupt { return .busy }
        if shouldInterrupt { invalidateCurrent() }
        let index = alertQueue.firstIndex { $0.priority < request.priority } ?? alertQueue.endIndex
        alertQueue.insert(request, at: index)
        lastError = nil
        pump()
        return lastError == nil ? .accepted : .busy
    }

    @discardableResult
    public func speak(_ text: String, priority: AlertPriority = .normal) -> AlertDeliveryResult {
        submit(AlertRequest(priority: priority, text: text))
    }
    @discardableResult
    public func playBeepThenSpeak(sound: AlertSound, text: String) -> AlertDeliveryResult {
        submit(AlertRequest(text: text, sound: sound))
    }

    public func cancel(category: AlertCategory) {
        alertQueue.removeAll { $0.category == category }
        if current?.category == category { invalidateCurrent(); pump() }
    }
    public func stopAll() {
        alertQueue.removeAll(); invalidateCurrent(); output.deactivate()
    }
    /// Nhường audio session cho thao tác tìm kiếm bằng microphone.
    public func setRecordingActive(_ active: Bool) {
        recordingActive = active
        if active { stopAll() } else { pump() }
    }
    func handleInterruption(began: Bool) {
        interrupted = began
        if began { stopAll() } // Tránh đọc lại chỉ dẫn cũ sau cuộc gọi.
    }
    private func removeExpired() {
        let now = clock()
        alertQueue.removeAll { now.timeIntervalSince($0.createdAt) > $0.maxAge || !isCategoryEnabled($0.category) }
    }
    private func invalidateCurrent() {
        currentToken = UUID(); current = nil; isPlaying = false; output.stop()
    }
    private func pump() {
        guard current == nil, !interrupted, !recordingActive, !isMuted else { return }
        removeExpired()
        guard !alertQueue.isEmpty else { output.deactivate(); return }
        let request = alertQueue.removeFirst()
        do { try output.activate(); lastError = nil }
        catch {
            lastError = "Không thể bật audio session: \(error.localizedDescription)"
            alertQueue.removeAll(); output.deactivate(); return
        }
        current = request; isPlaying = true
        let token = UUID(); currentToken = token
        if let sound = request.sound, output.play(sound: sound, volume: safeVolume, completion: { [weak self] in self?.speakCurrent(token: token) }) { return }
        speakCurrent(token: token)
    }
    private func speakCurrent(token: UUID) {
        guard token == currentToken, let request = current, !isMuted, !interrupted else { return }
        guard clock().timeIntervalSince(request.createdAt) <= request.maxAge else { finished(token: token); return }
        let utterance = AVSpeechUtterance(string: request.text)
        utterance.voice = AVSpeechSynthesisVoice(identifier: voiceIdentifier) ?? AVSpeechSynthesisVoice(language: "vi-VN")
        utterance.rate = safeRate; utterance.pitchMultiplier = 1; utterance.volume = safeVolume
        utterance.preUtteranceDelay = 0.1; utterance.postUtteranceDelay = 0.3
        output.speak(utterance) { [weak self] in self?.finished(token: token) }
    }
    private func finished(token: UUID) {
        guard currentToken == token else { return }
        current = nil; isPlaying = false; pump()
    }
}

/// AVSpeechSynthesizerDelegate/AVAudioPlayerDelegate không được giả định callback trên main.
@MainActor
private final class SystemAlertAudioOutput: NSObject, AlertAudioOutput, AVSpeechSynthesizerDelegate, AVAudioPlayerDelegate {
    private let synth = AVSpeechSynthesizer()
    private var player: AVAudioPlayer?
    private var utterance: AVSpeechUtterance?
    private var onSpeech: (() -> Void)?
    private var onSound: (() -> Void)?
    private var audioData: [AlertSound: Data] = [:]
    private var active = false
    override init() {
        super.init(); synth.delegate = self
        for sound in AlertSound.allCases {
            if let url = Bundle.module.url(forResource: sound.rawValue, withExtension: "caf"), let data = try? Data(contentsOf: url) { audioData[sound] = data }
        }
    }
    func activate() throws {
        guard !active else { return }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .voicePrompt, options: [.duckOthers, .mixWithOthers])
        try session.setActive(true)
        active = true
    }
    func play(sound: AlertSound, volume: Float, completion: @escaping () -> Void) -> Bool {
        guard let data = audioData[sound], let player = try? AVAudioPlayer(data: data) else { return false }
        self.player = player; onSound = completion; player.delegate = self; player.volume = volume
        guard player.play() else { self.player = nil; onSound = nil; return false }
        return true
    }
    func speak(_ utterance: AVSpeechUtterance, completion: @escaping () -> Void) {
        self.utterance = utterance; onSpeech = completion; synth.speak(utterance)
    }
    func stop() {
        onSound = nil; onSpeech = nil; utterance = nil
        player?.stop(); player = nil; synth.stopSpeaking(at: .immediate)
    }
    func deactivate() {
        guard active else { return }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        active = false
    }
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            guard let self, self.player === player else { return }
            self.player = nil; let callback = self.onSound; self.onSound = nil; callback?()
        }
    }
    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        audioPlayerDidFinishPlaying(player, successfully: false)
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) { complete(utterance) }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) { complete(utterance) }
    nonisolated private func complete(_ utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            guard let self, self.utterance === utterance else { return }
            self.utterance = nil; let callback = self.onSpeech; self.onSpeech = nil; callback?()
        }
    }
}
