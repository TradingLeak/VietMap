import SwiftUI
import WidgetKit
import ActivityKit
import NavigationActivityShared

@available(iOSApplicationExtension 16.1, *)
struct NavigationWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: NavigationActivityAttributes.self) { context in
            HStack(spacing: 14) {
                Image(systemName: context.state.nextManeuverIcon).font(.title)
                VStack(alignment: .leading) {
                    Text(distance(context.state.distanceToManeuver)).font(.headline)
                    Text(context.state.currentInstruction).lineLimit(2)
                    Text("Còn \(distance(context.state.distanceRemaining)) · \(Int(max(0, context.state.durationRemaining) / 60)) phút").font(.caption)
                }
            }.padding().activityBackgroundTint(.black).activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { Image(systemName: context.state.nextManeuverIcon) }
                DynamicIslandExpandedRegion(.trailing) { Text(distance(context.state.distanceToManeuver)) }
                DynamicIslandExpandedRegion(.bottom) { Text(context.state.currentInstruction).lineLimit(2) }
            } compactLeading: { Image(systemName: context.state.nextManeuverIcon) }
              compactTrailing: { Text(distance(context.state.distanceToManeuver)) }
              minimal: { Image(systemName: context.state.nextManeuverIcon) }
        }
    }
    private func distance(_ meters: Double) -> String {
        meters < 1000 ? "\(Int(max(0, meters))) m" : String(format: "%.1f km", meters / 1000)
    }
}

@main
struct NavigationWidgetBundle: WidgetBundle {
    @WidgetBundleBuilder var body: some Widget {
        if #available(iOSApplicationExtension 16.1, *) { NavigationWidget() }
    }
}
