import SwiftUI

struct UpcomingWarningCard: View {
    let warning: WarningItem
    @AppStorage("vn.distanceUnit") private var unit = "km"
    var body: some View {
        VStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 19, weight: .bold)).foregroundStyle(VNTheme.warning)
                .frame(width: 36, height: 31)
            Text(title).font(.system(size: 10, weight: .bold)).multilineTextAlignment(.center).lineLimit(2)
            if let limit = warning.node.speedLimit {
                VStack(spacing: -2) {
                    Text("\(limit)").font(.system(size: 12, weight: .heavy))
                    Text("km/h").font(.system(size: 6, weight: .bold))
                }.foregroundStyle(VNTheme.text)
                    .frame(width: 32, height: 32).background(Circle().fill(VNTheme.surface).overlay(Circle().stroke(VNTheme.danger, lineWidth: 3)))
            }
            Text(NavigationFormat.distance(warning.distance, unit: unit)).font(.system(size: 13, weight: .bold, design: .rounded)).foregroundStyle(VNTheme.accent)
        }
        .foregroundStyle(VNTheme.text).frame(width: 82).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 16).fill(VNTheme.surface).shadow(color: VNTheme.shadow.opacity(0.16), radius: 8, y: 4))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), cách khoảng \(NavigationFormat.distance(warning.distance, unit: unit))\(warning.node.speedLimit.map { ", giới hạn trên biển \($0) ki lô mét một giờ" } ?? "")")
    }
    private var title: String {
        switch warning.node.type {
        case .speedCamera: return "CAMERA TỐC ĐỘ"
        case .redLightCamera: return "CAMERA ĐÈN ĐỎ"
        case .tollBooth: return "TRẠM THU PHÍ"
        case .railwayCrossing: return "ĐƯỜNG SẮT"
        case .speedLimit: return "BIỂN TỐC ĐỘ"
        case .residentialIn: return "VÀO KHU DÂN CƯ"
        case .residentialOut: return "RA KHU DÂN CƯ"
        case .noOvertaking: return "CẤM VƯỢT"
        case .incident: return "SỰ CỐ GIAO THÔNG"
        }
    }
    private var icon: String {
        switch warning.node.type {
        case .speedCamera, .redLightCamera: return "camera.fill"
        case .tollBooth: return "creditcard.fill"
        case .railwayCrossing: return "tram.fill"
        case .speedLimit: return "speedometer"
        default: return "exclamationmark.triangle.fill"
        }
    }
}
struct UpcomingWarningCard_Previews: PreviewProvider {
    static var previews: some View {
        UpcomingWarningCard(warning: WarningItem(id: 1, node: TrafficNode(id: 1, type: .speedCamera, latitude: 21, longitude: 105, speedLimit: 60), distance: 320, bearing: 0, hasAnnounced: false)).padding().previewLayout(.sizeThatFits)
    }
}
