import SwiftUI

/// Biểu tượng tham khảo từ dữ liệu OSM, không phải biển báo pháp lý đã xác minh.
struct UpcomingWarningCard: View {
    let warning: WarningItem
    @AppStorage("vn.distanceUnit") private var unit = "km"
    var body: some View {
        VStack(spacing: 1) {
            Image(systemName: icon).font(.system(size: 17, weight: .bold)).foregroundStyle(VNTheme.text)
                .frame(width: 40, height: 40)
                .background(Circle().fill(VNTheme.surface).overlay(Circle().stroke(VNTheme.danger, lineWidth: 4)))
                .overlay {
                    if warning.node.type == .noLeftTurn || warning.node.type == .noRightTurn {
                        Path { path in path.move(to: CGPoint(x: 7, y: 7)); path.addLine(to: CGPoint(x: 33, y: 33)) }
                            .stroke(VNTheme.danger, lineWidth: 3)
                    }
                }
            Text(NavigationFormat.distance(warning.distance, unit: unit))
                .font(.system(size: 13, weight: .heavy)).foregroundStyle(VNTheme.text)
                .padding(.horizontal, 4).background(VNTheme.surface, in: Capsule())
        }.accessibilityElement(children: .ignore)
         .accessibilityLabel("\(title), cách khoảng \(NavigationFormat.distance(warning.distance, unit: unit)), dữ liệu chưa kiểm chứng")
    }
    private var title: String {
        switch warning.node.type {
        case .speedCamera: return "Camera tốc độ"
        case .redLightCamera: return "Camera đèn đỏ"
        case .tollBooth: return "Trạm thu phí"
        case .railwayCrossing: return "Đường sắt"
        case .speedLimit: return "Biển tốc độ"
        case .residentialIn: return "Vào khu dân cư"
        case .residentialOut: return "Ra khu dân cư"
        case .noOvertaking: return "Cấm vượt"
        case .noLeftTurn: return "Cấm rẽ trái"
        case .noRightTurn: return "Cấm rẽ phải"
        case .incident: return "Sự cố giao thông"
        }
    }
    private var icon: String {
        switch warning.node.type {
        case .speedCamera, .redLightCamera: return "camera.fill"
        case .tollBooth: return "creditcard.fill"
        case .railwayCrossing: return "tram.fill"
        case .speedLimit: return "speedometer"
        case .noLeftTurn: return "arrow.turn.up.left"
        case .noRightTurn: return "arrow.turn.up.right"
        default: return "exclamationmark.triangle.fill"
        }
    }
}
struct UpcomingWarningCard_Previews: PreviewProvider {
    static var previews: some View {
        UpcomingWarningCard(warning: WarningItem(id: 1, node: TrafficNode(id: 1, type: .speedCamera, latitude: 21, longitude: 105), distance: 320, bearing: 0, hasAnnounced: false)).padding().previewLayout(.sizeThatFits)
    }
}
