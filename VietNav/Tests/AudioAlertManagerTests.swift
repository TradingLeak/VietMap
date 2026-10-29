import XCTest
import AVFoundation
@testable import VietNavCore

@MainActor
final class AudioAlertManagerTests: XCTestCase {
    private func setup() -> (AudioAlertManager, MockAudioOutput, UserDefaults, String) {
        let suite = "vietnav-audio-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let output = MockAudioOutput()
        return (AudioAlertManager(output: output, defaults: defaults), output, defaults, suite)
    }
    func testPriorityFIFOAndCriticalPreemption() {
        let (manager, output, defaults, suite) = setup()
        defer { manager.stopAll(); defaults.removePersistentDomain(forName: suite) }
        XCTAssertEqual(manager.submit(AlertRequest(text: "đang đọc")), .accepted)
        let staleCallback = output.speechCompletion
        XCTAssertEqual(manager.submit(AlertRequest(text: "bình thường 1")), .accepted)
        XCTAssertEqual(manager.submit(AlertRequest(priority: .high, text: "cao 1")), .accepted)
        XCTAssertEqual(manager.submit(AlertRequest(priority: .high, text: "cao 2")), .accepted)
        XCTAssertEqual(manager.submit(AlertRequest(priority: .low, text: "thấp")), .busy)
        XCTAssertEqual(manager.submit(AlertRequest(priority: .critical, text: "khẩn")), .accepted)
        XCTAssertEqual(output.spoken, ["đang đọc", "khẩn"])
        staleCallback?() // Callback từ utterance đã hủy không được kết thúc utterance mới.
        XCTAssertTrue(manager.isPlaying)
        output.finishSpeech(); XCTAssertEqual(output.spoken.last, "cao 1")
        output.finishSpeech(); XCTAssertEqual(output.spoken.last, "cao 2")
        output.finishSpeech(); XCTAssertEqual(output.spoken.last, "bình thường 1")
        output.finishSpeech(); XCTAssertFalse(manager.isPlaying)
        XCTAssertGreaterThan(output.deactivations, 0)
    }
    func testSoundThenSpeechAndMuteCancels() {
        let (manager, output, defaults, suite) = setup()
        defer { manager.stopAll(); defaults.removePersistentDomain(forName: suite) }
        XCTAssertEqual(manager.submit(AlertRequest(text: "camera", sound: .radar, category: .camera)), .accepted)
        XCTAssertEqual(output.sounds, [.radar])
        XCTAssertTrue(output.spoken.isEmpty)
        output.finishSound()
        XCTAssertEqual(output.spoken, ["camera"])
        let staleCallback = output.speechCompletion
        manager.isMuted = true
        staleCallback?()
        XCTAssertFalse(manager.isPlaying)
        XCTAssertEqual(manager.submit(AlertRequest(text: "bị tắt")), .suppressed)
        XCTAssertTrue(defaults.bool(forKey: "audio.muted"))
    }
    func testSettingsAndCategoryCancellation() {
        let (manager, output, defaults, suite) = setup()
        defer { manager.stopAll(); defaults.removePersistentDomain(forName: suite) }
        manager.volume = 0.4; manager.speechRate = 0.48; manager.voiceIdentifier = "test-voice"
        manager.setCategory(.camera, enabled: false)
        XCTAssertEqual(manager.submit(AlertRequest(text: "camera", category: .camera)), .suppressed)
        XCTAssertEqual(manager.submit(AlertRequest(text: "đường", category: .navigation)), .accepted)
        manager.setCategory(.navigation, enabled: false)
        XCTAssertFalse(manager.isPlaying)
        XCTAssertGreaterThan(output.stops, 0)
        let restored = AudioAlertManager(output: MockAudioOutput(), defaults: defaults)
        XCTAssertFalse(restored.isCategoryEnabled(.camera))
        XCTAssertEqual(restored.volume, 0.4, accuracy: 0.001)
        XCTAssertEqual(restored.voiceIdentifier, "test-voice")
    }
    func testExpiredRequestsAndInterruption() {
        let (manager, output, defaults, suite) = setup()
        defer { manager.stopAll(); defaults.removePersistentDomain(forName: suite) }
        XCTAssertEqual(manager.submit(AlertRequest(text: "cũ", createdAt: Date().addingTimeInterval(-40), maxAge: 10)), .suppressed)
        XCTAssertEqual(manager.submit(AlertRequest(text: "đường")), .accepted)
        manager.handleInterruption(began: true)
        XCTAssertFalse(manager.isPlaying)
        XCTAssertEqual(manager.submit(AlertRequest(text: "đang có cuộc gọi")), .busy)
        manager.handleInterruption(began: false)
        XCTAssertEqual(manager.submit(AlertRequest(text: "sau cuộc gọi")), .accepted)
        XCTAssertEqual(output.spoken, ["đường", "sau cuộc gọi"])
    }
    func testQueuedRequestExpiresBeforePlayback() {
        var now = Date()
        let suite = "vietnav-audio-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let output = MockAudioOutput()
        let manager = AudioAlertManager(output: output, defaults: defaults, clock: { now })
        defer { manager.stopAll(); defaults.removePersistentDomain(forName: suite) }
        _ = manager.submit(AlertRequest(text: "đang đọc", createdAt: now, maxAge: 10))
        _ = manager.submit(AlertRequest(text: "đã cũ", createdAt: now, maxAge: 2))
        now.addTimeInterval(3)
        output.finishSpeech()
        XCTAssertEqual(output.spoken, ["đang đọc"])
        XCTAssertFalse(manager.isPlaying)
    }

    func testMicrophoneSuspendsAlertsUntilRecordingEnds() {
        let (manager, _, defaults, suite) = setup()
        defer { manager.stopAll(); defaults.removePersistentDomain(forName: suite) }
        XCTAssertEqual(manager.submit(AlertRequest(text: "đang đọc")), .accepted)
        manager.setRecordingActive(true)
        XCTAssertFalse(manager.isPlaying)
        XCTAssertEqual(manager.submit(AlertRequest(text: "trong khi ghi")), .busy)
        manager.setRecordingActive(false)
        XCTAssertEqual(manager.submit(AlertRequest(text: "ghi xong")), .accepted)
    }

    func testUnavailableSoundFallsBackAndSessionFailureIsReported() {
        let (manager, output, defaults, suite) = setup()
        defer { manager.stopAll(); defaults.removePersistentDomain(forName: suite) }
        output.missingSound = true
        XCTAssertEqual(manager.submit(AlertRequest(text: "thử", sound: .beep)), .accepted)
        XCTAssertEqual(output.spoken, ["thử"])
        output.finishSpeech()
        output.failActivate = true
        XCTAssertEqual(manager.submit(AlertRequest(text: "lỗi")), .busy)
        XCTAssertNotNil(manager.lastError)
        XCTAssertFalse(manager.isPlaying)
    }
}

@MainActor
private final class MockAudioOutput: AlertAudioOutput {
    var spoken: [String] = []
    var sounds: [AlertSound] = []
    var speechCompletion: (() -> Void)?
    var soundCompletion: (() -> Void)?
    var stops = 0
    var deactivations = 0
    var failActivate = false
    var missingSound = false
    func activate() throws { if failActivate { throw NSError(domain: "audio-test", code: 1) } }
    func play(sound: AlertSound, volume: Float, completion: @escaping () -> Void) -> Bool {
        if missingSound { return false }
        sounds.append(sound); soundCompletion = completion; return true
    }
    func speak(_ utterance: AVSpeechUtterance, completion: @escaping () -> Void) {
        spoken.append(utterance.speechString); speechCompletion = completion
    }
    func stop() { stops += 1; speechCompletion = nil; soundCompletion = nil }
    func deactivate() { deactivations += 1 }
    func finishSpeech() { let callback = speechCompletion; speechCompletion = nil; callback?() }
    func finishSound() { let callback = soundCompletion; soundCompletion = nil; callback?() }
}
