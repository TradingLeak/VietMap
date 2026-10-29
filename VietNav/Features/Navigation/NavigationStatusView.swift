import SwiftUI

struct NavigationStatusView: View {
    @ObservedObject var engine: NavigationEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if engine.isRerouting {
                Label("Đang tính lại lộ trình…", systemImage: "arrow.triangle.2.circlepath")
                    .font(.subheadline.bold())
            } else if engine.isArrived {
                Text("Đã đến nơi").font(.headline)
            } else if engine.isOffRoute {
                Text("Có thể đã lệch tuyến").font(.subheadline.bold()).foregroundColor(.orange)
            }
            if let step = engine.currentStep, !engine.isArrived {
                Text(step.instruction).font(.headline)
                Text(String(format: "Còn %.0f m đến bước tiếp theo", engine.distanceToNextManeuver)).font(.caption)
                if !step.lanes.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(Array(step.lanes.enumerated()), id: \.offset) { _, lane in
                            VStack(spacing: 2) {
                                Image(systemName: symbol(for: lane.indications))
                                if lane.valid == true { Text("✓").font(.caption2) }
                            }
                            .foregroundColor(lane.valid == true ? .green : .secondary)
                            .accessibilityLabel("Làn \(lane.indications.joined(separator: ", "))\(lane.valid == true ? ", được gợi ý" : "")")
                        }
                    }
                    .font(.caption)
                }
            }
            if engine.isNavigating {
                Text(String(format: "Còn %.1f km · %.0f phút", engine.distanceRemaining / 1000, engine.durationRemaining / 60)).font(.caption)
                if let eta = engine.estimatedArrivalTime { Text("Dự kiến đến \(eta.formatted(date: .omitted, time: .shortened))").font(.caption) }
            }
            if let error = engine.lastError { Text(error).font(.caption).foregroundColor(.red) }
            if engine.currentRoute != nil {
                Button(engine.isArrived ? "Đóng" : "Dừng dẫn đường") { engine.stopNavigation() }.font(.caption.bold())
            }
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func symbol(for indications: [String]) -> String {
        // Nhiều hướng trên một làn cần xem nhãn accessibility; không đoán lane hợp lệ.
        if indications.contains("left") || indications.contains("slight_left") || indications.contains("sharp_left") { return "arrow.turn.up.left" }
        if indications.contains("right") || indications.contains("slight_right") || indications.contains("sharp_right") { return "arrow.turn.up.right" }
        if indications.contains("reverse") { return "arrow.uturn.down" }
        if indications.contains("through") || indications.contains("straight") { return "arrow.up" }
        return "arrow.up.and.down"
    }
}
