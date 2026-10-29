import XCTest
import CoreLocation
@testable import VietNavCore

final class RouteTests: XCTestCase {
    private let start = CLLocationCoordinate2D(latitude: 21.0285, longitude: 105.8542)
    private let via = CLLocationCoordinate2D(latitude: 21.03, longitude: 105.86)
    private let end = CLLocationCoordinate2D(latitude: 21.04, longitude: 105.87)
    private let fixture = #"""
    {"code":"Ok","routes":[
      {"distance":1200,"duration":180,"geometry":{"type":"LineString","coordinates":[[105.8542,21.0285],[105.86,21.03],[105.87,21.04]]},
       "legs":[{"steps":[
         {"distance":50,"duration":10,"name":"","maneuver":{"type":"depart","location":[105.8542,21.0285]}},
         {"distance":100,"duration":15,"name":"Phạm Văn Đồng","maneuver":{"type":"turn","modifier":"right","location":[105.86,21.03]},"intersections":[{"lanes":[{"indications":["left"],"valid":false},{"indications":["straight","right"],"valid":true}]}]}
       ]},{"steps":[{"distance":0,"duration":0,"name":"","maneuver":{"type":"arrive","location":[105.87,21.04]}}]}]},
      {"distance":1500,"duration":200,"geometry":{"type":"LineString","coordinates":[[105.8542,21.0285],[105.87,21.04]]},"legs":[{"steps":[]}]}
    ]}
    """#

    private func service(data: String, status: Int = 200) -> OSRMRoutingService {
        RouteMockProtocol.configure(data: Data(data.utf8), status: status)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [RouteMockProtocol.self]
        return OSRMRoutingService(endpoints: [.car: OSRMEndpoint(baseURL: URL(string: "https://example.test")!)], session: URLSession(configuration: config))
    }

    func testParsingAlternativesWaypointsAndCache() async throws {
        let subject = service(data: fixture)
        let routes = try await subject.calculateRoutes(from: start, to: end, waypoints: [via], profile: .car, alternatives: true)
        XCTAssertEqual(routes.count, 2)
        XCTAssertEqual(routes[0].geometry.count, 3)
        XCTAssertEqual(routes[0].geometry[0].latitude, 21.0285, accuracy: 0.000001)
        XCTAssertEqual(routes[0].geometry[0].longitude, 105.8542, accuracy: 0.000001)
        XCTAssertEqual(routes[0].distance, 1200)
        XCTAssertEqual(routes[0].duration, 180)
        XCTAssertEqual(routes[0].bbox.west, 105.8542, accuracy: 0.000001)
        XCTAssertEqual(routes[0].steps.count, 3)
        XCTAssertEqual(routes[0].steps[0].instruction, "Bắt đầu đi")
        XCTAssertEqual(routes[0].steps[1].instruction, "Rẽ phải vào Phạm Văn Đồng")
        XCTAssertEqual(routes[0].steps[1].lanes.count, 2)
        XCTAssertEqual(routes[0].steps[1].lanes[1].valid, true)
        XCTAssertEqual(routes[0].steps[2].maneuver, .arrive)
        let request = try XCTUnwrap(RouteMockProtocol.lastRequest)
        let url = try XCTUnwrap(request.url)
        XCTAssertTrue(url.path.removingPercentEncoding!.contains("105.8542000,21.0285000;105.8600000,21.0300000;105.8700000,21.0400000"))
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(query.first { $0.name == "alternatives" }?.value, "true")
        XCTAssertEqual(query.first { $0.name == "steps" }?.value, "true")
        let cached = try await subject.calculateRoute(from: start, to: end, waypoints: [via], profile: .car)
        XCTAssertEqual(cached.id, routes[0].id)
        XCTAssertEqual(RouteMockProtocol.count, 1)
        _ = try await subject.calculateRoutes(from: start, to: end, waypoints: [via], profile: .car, alternatives: false)
        XCTAssertEqual(RouteMockProtocol.count, 2)
    }

    func testFailureAndUnsupportedProfile() async throws {
        let subject = service(data: #"{"code":"NoRoute","message":"No route"}"#, status: 400)
        do {
            _ = try await subject.calculateRoute(from: start, to: end)
            XCTFail("Expected no route")
        } catch RoutingError.noRoute {} catch { XCTFail("Unexpected error \(error)") }
        do {
            _ = try await subject.calculateRoute(from: start, to: end, profile: .truck)
            XCTFail("Expected unsupported profile")
        } catch RoutingError.unsupportedProfile(.truck) {} catch { XCTFail("Unexpected error \(error)") }
        do {
            _ = try await subject.calculateRoute(from: .init(latitude: 100, longitude: 0), to: end)
            XCTFail("Expected invalid coordinate")
        } catch RoutingError.invalidCoordinates {} catch { XCTFail("Unexpected error \(error)") }
    }

    func testMalformedResponseIsNotCached() async throws {
        let subject = service(data: #"{"code":"Ok","routes":[{"distance":1,"duration":1,"geometry":{"type":"LineString","coordinates":[[105]]},"legs":[]}]}"#)
        for _ in 0..<2 {
            do { _ = try await subject.calculateRoute(from: start, to: end); XCTFail("Expected invalid response") }
            catch RoutingError.invalidResponse {} catch { XCTFail("Unexpected error \(error)") }
        }
        XCTAssertEqual(RouteMockProtocol.count, 2)
    }

    func testLocalizerWithoutStreetName() {
        let step = RouteStep(instruction: "", distance: 0, duration: 0, maneuver: .turnLeft, streetName: " ", coordinate: start)
        XCTAssertEqual(vietnameseInstruction(for: step), "Rẽ trái")
    }
}

private final class RouteMockProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var storedData = Data()
    private static var storedStatus = 200
    private static var storedCount = 0
    private static var storedRequest: URLRequest?
    static var count: Int { lock.lock(); defer { lock.unlock() }; return storedCount }
    static var lastRequest: URLRequest? { lock.lock(); defer { lock.unlock() }; return storedRequest }
    static func configure(data: Data, status: Int) {
        lock.lock(); defer { lock.unlock() }
        storedData = data; storedStatus = status; storedCount = 0; storedRequest = nil
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock()
        Self.storedCount += 1; Self.storedRequest = request
        let data = Self.storedData, status = Self.storedStatus
        Self.lock.unlock()
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
