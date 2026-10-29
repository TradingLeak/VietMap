import ActivityKit
import Foundation

@available(iOS 16.1, *)
public struct NavigationActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var distanceRemaining: Double
        public var distanceToManeuver: Double
        public var durationRemaining: TimeInterval
        public var currentInstruction: String
        public var nextManeuverIcon: String
        public init(distanceRemaining: Double, distanceToManeuver: Double, durationRemaining: TimeInterval, currentInstruction: String, nextManeuverIcon: String) {
            self.distanceRemaining = distanceRemaining; self.distanceToManeuver = distanceToManeuver
            self.durationRemaining = durationRemaining; self.currentInstruction = currentInstruction; self.nextManeuverIcon = nextManeuverIcon
        }
    }
    public var destinationName: String
    public init(destinationName: String) { self.destinationName = destinationName }
}
