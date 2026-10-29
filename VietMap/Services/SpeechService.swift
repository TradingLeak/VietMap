import AVFoundation
import Combine
import VietMapCore

@MainActor
final class SpeechService: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published private(set) var warning: String?
    private let synthesizer = AVSpeechSynthesizer()
    private var pending: [Announcement] = []
    private var currentPriority = 0
    private var currentText: String?
    private var enabled = true
    private var identifier: String?
    private var rate: Float = 0.48

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    var vietnameseVoices: [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("vi") }.sorted { $0.name < $1.name }
    }

    func configure(_ settings: AppSettings) {
        enabled = settings.voiceEnabled
        identifier = settings.voiceIdentifier
        rate = Float(settings.sanitized().speechRate)
        if !enabled { stop() }
    }

    func enqueue(_ messages: [Announcement]) {
        guard enabled else { return }
        for message in messages where !pending.contains(where: { $0.text == message.text }) && message.text != currentText {
            pending.append(message)
        }
        pending.sort { $0.priority > $1.priority }
        pending = Array(pending.prefix(3))
        if synthesizer.isSpeaking, let highest = pending.first, highest.priority >= 3, highest.priority > currentPriority {
            // A fresh overspeed warning may preempt lower-priority narration.
            synthesizer.stopSpeaking(at: .word)
        } else { playNext() }
    }

    func preview() {
        enqueue([Announcement(text: "VietMap đã sẵn sàng. Chúc bạn một hành trình an toàn.", priority: 1)])
    }

    func stop() {
        pending.removeAll()
        currentText = nil
        currentPriority = 0
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        deactivateAudio()
    }

    private func playNext() {
        // Do not interrupt an in-progress safety message with lower priority chatter.
        guard !synthesizer.isSpeaking, !pending.isEmpty, enabled else { return }
        let next = pending.removeFirst()
        let voice = identifier.flatMap(AVSpeechSynthesisVoice.init(identifier:)) ?? AVSpeechSynthesisVoice(language: "vi-VN")
        guard let voice else {
            warning = "Thiếu giọng tiếng Việt. Tải giọng trong Cài đặt iOS → Trợ năng → Nội dung được đọc. Cảnh báo hình ảnh vẫn hoạt động."
            pending.removeAll()
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .voicePrompt, options: [.duckOthers, .mixWithOthers])
            try session.setActive(true)
        } catch {
            warning = "Không kích hoạt được âm thanh. Kiểm tra thiết bị Bluetooth và âm lượng iOS."
            pending.removeAll()
            return
        }
        warning = nil
        currentPriority = next.priority
        currentText = next.text
        let utterance = AVSpeechUtterance(string: next.text)
        utterance.voice = voice
        utterance.rate = rate
        utterance.volume = 1
        synthesizer.speak(utterance)
    }

    private func deactivateAudio() {
        do { try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
        catch { warning = "Không khôi phục được phiên âm thanh. Hãy kiểm tra âm thanh iOS." }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        currentPriority = 0
        currentText = nil
        if pending.isEmpty { deactivateAudio() } else { playNext() }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        currentPriority = 0
        currentText = nil
        if pending.isEmpty { deactivateAudio() } else { playNext() }
    }
}
