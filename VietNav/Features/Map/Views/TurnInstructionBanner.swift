import SwiftUI
import CoreLocation

struct TurnInstructionBanner: View {
    let step: RouteStep
    let distance: Double
    let nextStep: RouteStep?
    @AppStorage("vn.distanceUnit") private var unit = "km"

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon(step.maneuver)).font(.system(size: 31, weight: .bold))
                .frame(width: 44).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(NavigationFormat.distance(distance, unit: unit)).font(.system(size: 20, weight: .bold, design: .rounded))
                Text(step.instruction).font(.subheadline.weight(.semibold)).lineLimit(2)
            }
            Spacer(minLength: 4)
            if let nextStep {
                VStack(spacing: 3) {
                    Text("TIẾP THEO").font(.system(size: 9, weight: .bold))
                    Image(systemName: icon(nextStep.maneuver)).font(.system(size: 18, weight: .bold))
                }.opacity(0.8).accessibilityLabel("Sau đó: \(nextStep.instruction)")
            }
        }
        .foregroundStyle(VNTheme.text)
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18).fill(VNTheme.surface).shadow(color: VNTheme.shadow.opacity(0.22), radius: 10, y: 5))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(NavigationFormat.distance(distance, unit: unit)), \(step.instruction)")
    }
    private func icon(_ maneuver: Maneuver) -> String {
        switch maneuver {
        case .turnLeft: return "arrow.turn.up.left"
        case .turnRight: return "arrow.turn.up.right"
        case .slightLeft: return "arrow.up.left"
        case .slightRight: return "arrow.up.right"
        case .straight: return "arrow.up"
        case .uTurn: return "arrow.uturn.down"
        case .roundabout, .exitRoundabout: return "arrow.triangle.2.circlepath"
        case .arrive: return "mappin.and.ellipse"
        case .depart: return "location.north.fill"
        case .unknown: return "arrow.up"
        }
    }
}

struct TurnInstructionBanner_Previews: PreviewProvider {
    static var previews: some View {
        TurnInstructionBanner(step: RouteStep(instruction: "Rẽ phải vào Phạm Văn Đồng", distance: 300, duration: 30, maneuver: .turnRight, streetName: "Phạm Văn Đồng", coordinate: .init(latitude: 21, longitude: 105)), distance: 350, nextStep: nil).padding().previewLayout(.sizeThatFits)
    }
}
