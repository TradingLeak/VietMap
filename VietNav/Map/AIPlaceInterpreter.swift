import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Extract a search phrase only. The model never chooses a coordinate or a route.
enum AIPlaceInterpreter {
    enum Failure: LocalizedError {
        case unavailable, badInput, badOutput
        var errorDescription: String? {
            switch self {
            case .unavailable: return "AI trên thiết bị chưa sẵn sàng hoặc không được hỗ trợ. Bạn vẫn có thể nhập tên địa điểm trực tiếp."
            case .badInput: return "Nhập yêu cầu từ 2 đến 300 ký tự."
            case .badOutput: return "Không xác định được tên địa điểm. Hãy nhập trực tiếp hoặc thử lại."
            }
        }
    }
    @MainActor static func extract(_ input: String) async throws -> String {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (2...300).contains(text.count) else { throw Failure.badInput }
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            guard case .available = SystemLanguageModel.default.availability else { throw Failure.unavailable }
            let session = LanguageModelSession(instructions: """
            Extract only the destination name from the user's travel request. Return only the name, in the user's language, without quotation marks or explanation. Do not invent locations, addresses or coordinates. If no destination is specified, return NONE. The output is only a search phrase and never a route.
            """)
            let response = try await session.respond(to: text)
            let candidate = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !candidate.isEmpty, candidate.count <= 100,
                  candidate.uppercased() != "NONE", !candidate.contains("\n") else { throw Failure.badOutput }
            return candidate
        }
        #endif
        throw Failure.unavailable
    }
}
