import Foundation
import CoreLocation
import OSMData

public enum RouteProfile: String, CaseIterable, Hashable {
    case car, motorcycle, truck, bicycle
}

public protocol RoutingServiceProtocol {
    func calculateRoute(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D,
                        waypoints: [CLLocationCoordinate2D], profile: RouteProfile) async throws -> Route
    func calculateRoutes(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D,
                         waypoints: [CLLocationCoordinate2D], profile: RouteProfile,
                         alternatives: Bool) async throws -> [Route]
}

public enum RoutingError: Error, LocalizedError {
    case invalidCoordinates, tooManyWaypoints, unsupportedProfile(RouteProfile), invalidURL
    case httpStatus(Int), server(code: String, message: String?), invalidResponse, noRoute

    public var errorDescription: String? {
        switch self {
        case .invalidCoordinates: return "Tọa độ không hợp lệ."
        case .tooManyWaypoints: return "Quá nhiều điểm trung gian."
        case .unsupportedProfile: return "Máy chủ chưa được cấu hình cho loại phương tiện này."
        case .invalidURL: return "Địa chỉ máy chủ định tuyến không hợp lệ."
        case .httpStatus(let status): return "Máy chủ định tuyến trả về HTTP \(status)."
        case .server(let code, let message): return "OSRM: \(message ?? code)"
        case .invalidResponse: return "Dữ liệu tuyến đường không hợp lệ."
        case .noRoute: return "Không tìm thấy tuyến đường."
        }
    }
}

/// Một OSRM deployment sử dụng profile đã biên dịch sẵn, không đổi bằng tên URL.
public struct OSRMEndpoint {
    public let baseURL: URL
    public let pathProfile: String
    public init(baseURL: URL, pathProfile: String = "driving") {
        self.baseURL = baseURL; self.pathProfile = pathProfile
    }
    public static let publicCarDemo = OSRMEndpoint(baseURL: URL(string: "https://router.project-osrm.org")!)
}

private actor RouteCache {
    private struct Entry { let routes: [Route]; let date: Date }
    private var entries: [String: Entry] = [:]
    private let ttl: TimeInterval
    init(ttl: TimeInterval) { self.ttl = ttl }
    func get(_ key: String) -> [Route]? {
        guard let entry = entries[key], Date().timeIntervalSince(entry.date) < ttl,
              Date().timeIntervalSince(entry.date) >= 0 else { entries[key] = nil; return nil }
        return entry.routes
    }
    func put(_ routes: [Route], key: String) {
        guard ttl > 0 else { return }
        if entries.count >= 64, let oldest = entries.min(by: { $0.value.date < $1.value.date })?.key { entries[oldest] = nil }
        entries[key] = Entry(routes: routes, date: Date())
    }
}

/// Chỉ car được bật mặc định. Các profile khác phải trỏ tới deployment OSRM phù hợp.
public final class OSRMRoutingService: RoutingServiceProtocol {
    private let endpoints: [RouteProfile: OSRMEndpoint]
    private let session: URLSession
    private let cache: RouteCache

    public init(endpoints: [RouteProfile: OSRMEndpoint] = [.car: .publicCarDemo],
                session: URLSession? = nil, cacheTTL: TimeInterval = 300) {
        self.endpoints = endpoints; self.session = session ?? UITestNetwork.session()
        self.cache = RouteCache(ttl: cacheTTL.isFinite ? max(0, cacheTTL) : 0)
    }

    public func calculateRoute(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D,
                               waypoints: [CLLocationCoordinate2D] = [], profile: RouteProfile = .car) async throws -> Route {
        guard let first = try await calculateRoutes(from: from, to: to, waypoints: waypoints, profile: profile, alternatives: true).first else {
            throw RoutingError.noRoute
        }
        return first
    }

    public func calculateRoutes(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D,
                                waypoints: [CLLocationCoordinate2D] = [], profile: RouteProfile = .car,
                                alternatives: Bool = true) async throws -> [Route] {
        guard let endpoint = endpoints[profile] else { throw RoutingError.unsupportedProfile(profile) }
        let coordinates = [from] + waypoints + [to]
        guard coordinates.count <= 25 else { throw RoutingError.tooManyWaypoints }
        guard coordinates.allSatisfy({ CLLocationCoordinate2DIsValid($0) && $0.latitude.isFinite && $0.longitude.isFinite }) else {
            throw RoutingError.invalidCoordinates
        }
        guard ["http", "https"].contains(endpoint.baseURL.scheme?.lowercased() ?? ""),
              endpoint.baseURL.host != nil, endpoint.baseURL.query == nil, endpoint.baseURL.fragment == nil,
              !endpoint.pathProfile.isEmpty, endpoint.pathProfile.range(of: "^[a-zA-Z0-9_-]+$", options: .regularExpression) != nil else {
            throw RoutingError.invalidURL
        }
        let points = coordinates.map {
            String(format: "%.7f,%.7f", locale: Locale(identifier: "en_US_POSIX"), $0.longitude, $0.latitude)
        }.joined(separator: ";")
        let url = endpoint.baseURL.appendingPathComponent("route/v1/\(endpoint.pathProfile)/\(points)")
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { throw RoutingError.invalidURL }
        components.queryItems = [
            URLQueryItem(name: "overview", value: "full"), URLQueryItem(name: "geometries", value: "geojson"),
            URLQueryItem(name: "steps", value: "true"), URLQueryItem(name: "annotations", value: "true"),
            URLQueryItem(name: "alternatives", value: alternatives ? "true" : "false")
        ]
        guard let requestURL = components.url else { throw RoutingError.invalidURL }
        let key = profile.rawValue + "|" + requestURL.absoluteString
        try Task.checkCancellation()
        if let cached = await cache.get(key) { return cached }
        var request = URLRequest(url: requestURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.setValue("VietNav/1.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw RoutingError.invalidResponse }
        if !(200..<300).contains(http.statusCode) {
            if let result = try? JSONDecoder().decode(OSRMErrorResponse.self, from: data), result.code == "NoRoute" {
                throw RoutingError.noRoute
            }
            throw RoutingError.httpStatus(http.statusCode)
        }
        let payload: OSRMResponse
        do { payload = try JSONDecoder().decode(OSRMResponse.self, from: data) }
        catch { throw RoutingError.invalidResponse }
        if payload.code == "NoRoute" { throw RoutingError.noRoute }
        guard payload.code == "Ok" else { throw RoutingError.server(code: payload.code, message: payload.message) }
        guard let rawRoutes = payload.routes, !rawRoutes.isEmpty else { throw RoutingError.noRoute }
        let routes = try rawRoutes.map { try Self.makeRoute($0, profile: profile, waypoints: waypoints, destination: to) }
        await cache.put(routes, key: key)
        return routes
    }

    private static func coordinate(_ point: [Double]) throws -> CLLocationCoordinate2D {
        guard point.count >= 2, point[0].isFinite, point[1].isFinite else { throw RoutingError.invalidResponse }
        let c = CLLocationCoordinate2D(latitude: point[1], longitude: point[0])
        guard CLLocationCoordinate2DIsValid(c) else { throw RoutingError.invalidResponse }
        return c
    }
    private static func makeRoute(_ raw: OSRMRoute, profile: RouteProfile, waypoints: [CLLocationCoordinate2D], destination: CLLocationCoordinate2D) throws -> Route {
        guard raw.geometry.type == "LineString", raw.geometry.coordinates.count >= 2,
              raw.distance.isFinite, raw.distance >= 0, raw.duration.isFinite, raw.duration >= 0 else { throw RoutingError.invalidResponse }
        let geometry = try raw.geometry.coordinates.map(coordinate)
        let lats = geometry.map(\.latitude), lons = geometry.map(\.longitude)
        let bbox = BoundingBox(south: lats.min()!, west: lons.min()!, north: lats.max()!, east: lons.max()!)
        let steps: [RouteStep] = try raw.legs.flatMap(\.steps).map { step in
            guard step.distance.isFinite, step.distance >= 0, step.duration.isFinite, step.duration >= 0 else { throw RoutingError.invalidResponse }
            let maneuver = Self.maneuver(type: step.maneuver.type, modifier: step.maneuver.modifier)
            let name = step.name.trimmingCharacters(in: .whitespacesAndNewlines)
            return RouteStep(instruction: vietnameseInstruction(for: maneuver, streetName: name), distance: step.distance,
                             duration: step.duration, maneuver: maneuver, streetName: name, coordinate: try coordinate(step.maneuver.location),
                             lanes: step.intersections?.first(where: { !($0.lanes ?? []).isEmpty })?.lanes?.map { LaneGuidance(indications: $0.indications, valid: $0.valid) } ?? [])
        }
        return Route(geometry: geometry, distance: raw.distance, duration: raw.duration, steps: steps, bbox: bbox,
                     profile: profile, waypoints: waypoints, destination: destination)
    }
    private static func maneuver(type: String, modifier: String?) -> Maneuver {
        switch type {
        case "depart": return .depart
        case "arrive": return .arrive
        case "roundabout", "rotary", "roundabout turn": return .roundabout
        case "exit roundabout", "exit rotary": return .exitRoundabout
        default: break
        }
        switch modifier {
        case "left", "sharp left": return .turnLeft
        case "right", "sharp right": return .turnRight
        case "slight left": return .slightLeft
        case "slight right": return .slightRight
        case "uturn": return .uTurn
        case "straight": return .straight
        default: return .unknown
        }
    }
}

public func vietnameseInstruction(for step: RouteStep) -> String {
    vietnameseInstruction(for: step.maneuver, streetName: step.streetName)
}
private func vietnameseInstruction(for maneuver: Maneuver, streetName: String) -> String {
    let name = streetName.trimmingCharacters(in: .whitespacesAndNewlines)
    func withRoad(_ phrase: String, _ connector: String) -> String { name.isEmpty ? phrase : "\(phrase) \(connector) \(name)" }
    switch maneuver {
    case .turnLeft: return withRoad("Rẽ trái", "vào")
    case .turnRight: return withRoad("Rẽ phải", "vào")
    case .slightLeft: return withRoad("Chếch trái", "vào")
    case .slightRight: return withRoad("Chếch phải", "vào")
    case .straight: return withRoad("Đi thẳng", "trên")
    case .uTurn: return "Quay đầu xe"
    case .roundabout: return withRoad("Đi theo vòng xuyến", "vào")
    case .exitRoundabout: return withRoad("Ra khỏi vòng xuyến", "vào")
    case .arrive: return "Đã đến nơi"
    case .depart: return withRoad("Bắt đầu đi", "trên")
    case .unknown: return withRoad("Tiếp tục", "trên")
    }
}

private struct OSRMErrorResponse: Decodable { let code: String }
private struct OSRMResponse: Decodable { let code: String; let message: String?; let routes: [OSRMRoute]? }
private struct OSRMRoute: Decodable { let distance: Double; let duration: Double; let geometry: OSRMGeometry; let legs: [OSRMLeg] }
private struct OSRMGeometry: Decodable { let type: String; let coordinates: [[Double]] }
private struct OSRMLeg: Decodable { let steps: [OSRMStep] }
private struct OSRMStep: Decodable { let distance: Double; let duration: Double; let name: String; let maneuver: OSRMManeuver; let intersections: [OSRMIntersection]? }
private struct OSRMIntersection: Decodable { let lanes: [OSRMLane]? }
private struct OSRMLane: Decodable { let indications: [String]; let valid: Bool? }
private struct OSRMManeuver: Decodable { let type: String; let modifier: String?; let location: [Double] }
