import SwiftUI
import CoreLocation

@MainActor
final class NavigationRouteViewModel: ObservableObject {
    @Published private(set) var routes: [Route] = []
    @Published private(set) var selectedRoute: Route?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    private let service: RoutingServiceProtocol
    private var task: Task<Void, Never>?
    private var requestID = UUID()

    init(service: RoutingServiceProtocol = OSRMRoutingService()) { self.service = service }

    func calculate(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) {
        task?.cancel()
        let id = UUID(); requestID = id
        isLoading = true; errorMessage = nil
        task = Task {
            do {
                let found = try await service.calculateRoutes(from: from, to: to, waypoints: [], profile: .car, alternatives: true)
                guard !Task.isCancelled, requestID == id else { return }
                routes = found; selectedRoute = found.first; isLoading = false
            } catch {
                guard !Task.isCancelled, requestID == id else { return }
                routes = []; selectedRoute = nil; errorMessage = error.localizedDescription; isLoading = false
            }
        }
    }
    func select(_ route: Route) { selectedRoute = route }
    func clear() { cancel(); routes = []; selectedRoute = nil; errorMessage = nil }
    func cancel() { task?.cancel(); task = nil; requestID = UUID(); isLoading = false }
}
