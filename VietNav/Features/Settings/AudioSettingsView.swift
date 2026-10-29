import SwiftUI
import AVFoundation

/// Lựa chọn giọng phụ thuộc các voice thực sự được cài trên thiết bị.
struct AudioSettingsView: View {
    @ObservedObject private var audio = AudioAlertManager.shared
    @Environment(\.dismiss) private var dismiss
    private var voices: [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices().filter { $0.language.lowercased().hasPrefix("vi") }.sorted { $0.name < $1.name }
    }
    var body: some View {
        NavigationView {
            Form {
                Section("Âm thanh") {
                    Toggle("Bật thông báo bằng giọng nói", isOn: Binding(get: { !audio.isMuted }, set: { audio.isMuted = !$0 }))
                    Picker("Giọng tiếng Việt", selection: $audio.voiceIdentifier) {
                        if !voices.contains(where: { $0.identifier == audio.voiceIdentifier }) {
                            Text("Mặc định (Linh nếu có)").tag(audio.voiceIdentifier)
                        }
                        ForEach(voices, id: \.identifier) { voice in
                            Text(voiceLabel(voice)).tag(voice.identifier)
                        }
                    }
                    VStack(alignment: .leading) {
                        Text("Âm lượng: \(Int(audio.volume * 100))%")
                        Slider(value: Binding(get: { Double(audio.volume) }, set: { audio.volume = Float($0) }), in: 0...1)
                    }
                    VStack(alignment: .leading) {
                        Text(String(format: "Tốc độ đọc: %.2f", audio.speechRate))
                        Slider(value: Binding(get: { Double(audio.speechRate) }, set: { audio.speechRate = Float($0) }), in: 0.3...0.6)
                    }
                    Button("Nghe thử") {
                        audio.submit(AlertRequest(text: "Xin chào, VietNav sẵn sàng dẫn đường.", sound: .dingDong, category: .general))
                    }.disabled(audio.isMuted)
                    if let error = audio.lastError { Text(error).font(.caption).foregroundColor(.red) }
                }
                Section("Loại cảnh báo") {
                    ForEach(AlertCategory.allCases, id: \.rawValue) { category in
                        Toggle(category.title, isOn: Binding(get: { audio.isCategoryEnabled(category) },
                                                            set: { audio.setCategory(category, enabled: $0) }))
                    }
                }
                Section {
                    Text("Giọng nam/nữ tùy thuộc voice tiếng Việt đã cài trên thiết bị. Nếu voice đã chọn không có, VietNav dùng giọng tiếng Việt mặc định của hệ thống.")
                        .font(.caption).foregroundColor(.secondary)
                }
            }
            .navigationTitle("Cài đặt âm thanh")
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("Đóng") { dismiss() } } }
        }
    }
    private func voiceLabel(_ voice: AVSpeechSynthesisVoice) -> String {
        let gender: String
        switch voice.gender {
        case .male: gender = "Nam"
        case .female: gender = "Nữ"
        default: gender = "Không rõ"
        }
        return "\(voice.name) · \(gender)"
    }
}
