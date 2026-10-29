import SwiftUI

struct SpeedWarningStatusView: View {
    @ObservedObject var engine: SpeedWarningEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text((engine.hasFreshLocation && engine.hasSpeedMeasurement) ? String(format: "%.0f km/h", engine.currentSpeed) : "-- km/h").font(.headline)
                if let limit = engine.currentSpeedLimit {
                    Text("Giới hạn ước tính: \(limit)")
                        .foregroundColor(engine.isOverSpeeding ? .red : .secondary)
                } else { Text("Chưa rõ giới hạn").foregroundColor(.secondary) }
            }.font(.caption)
            if engine.isOverSpeeding {
                Text("Có thể vượt tốc độ · \(Int(engine.overspeedingDuration)) giây").font(.caption.bold()).foregroundColor(.red)
            }
            if let warning = engine.closestWarning {
                Text("\(label(warning.node.type)) · khoảng \(Int(warning.distance.rounded())) m")
                    .font(.caption.bold())
                    .foregroundColor(engine.isClosestWithinWarningDistance ? .orange : .secondary)
            }
            if !engine.hasFreshLocation { Text("Chưa có vị trí GPS mới").font(.caption2) }
            else if !engine.hasReliableHeading { Text("Chưa xác định được hướng di chuyển").font(.caption2) }
            if let error = engine.lastError { Text(error).font(.caption2).foregroundColor(.red) }
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func label(_ type: NodeType) -> String {
        switch type {
        case .speedCamera: return "Camera tốc độ"
        case .redLightCamera: return "Camera đèn đỏ"
        case .speedLimit: return "Biển tốc độ"
        case .residentialIn: return "Vào khu dân cư"
        case .residentialOut: return "Ra khu dân cư"
        case .tollBooth: return "Trạm thu phí"
        case .railwayCrossing: return "Giao cắt đường sắt"
        case .noOvertaking: return "Cấm vượt"
        case .noLeftTurn: return "Cấm rẽ trái"
        case .noRightTurn: return "Cấm rẽ phải"
        case .incident: return "Sự cố giao thông"
        }
    }
}
