import Foundation

@MainActor
public protocol NavigationAnnouncing {
    func announce(_ text: String)
    func stop()
}

/// Adapter dẫn đường sử dụng hàng đợi chung, không ngắt cảnh báo ưu tiên cao.
@MainActor
public final class SpeechNavigationAnnouncer: NavigationAnnouncing {
    public static let shared = SpeechNavigationAnnouncer()
    private let audio: AudioAlertManager
    public init(audio: AudioAlertManager) { self.audio = audio }
    private convenience init() { self.init(audio: .shared) }
    public func announce(_ text: String) {
        audio.submit(AlertRequest(priority: .high, text: text, category: .navigation, maxAge: 15))
    }
    public func stop() { audio.cancel(category: .navigation) }
}
