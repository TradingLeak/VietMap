import XCTest
import Foundation
@testable import OSMData

final class OverpassTests: XCTestCase {
    func testBoundingBoxValidation() throws {
        try BoundingBox(south: 8, west: 102, north: 24, east: 110).validate()
        XCTAssertThrowsError(try BoundingBox(south: 24, west: 102, north: 8, east: 110).validate())
    }

    func testElementRoundTrip() throws {
        let input = Data(#"[{"type":"node","id":1,"lat":21,"lon":105},{"type":"way","id":2,"nodes":[1],"geometry":[{"lat":21,"lon":105}],"tags":{"maxspeed":"50"}}]"#.utf8)
        let elements = try JSONDecoder().decode([OSMElement].self, from: input)
        XCTAssertEqual(try JSONDecoder().decode([OSMElement].self, from: JSONEncoder().encode(elements)), elements)
    }

    func testSpeedLimitRequestAndCache() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockProtocol.self]
        let session = URLSession(configuration: config)
        let cache = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: cache) }
        MockProtocol.count = 0
        let client = OverpassAPIClient(regions: [], endpoint: URL(string: "https://example.com/interpreter")!, session: session, cacheDirectory: cache)
        let box = BoundingBox(south: 20, west: 105, north: 21, east: 106)
        let first = try await client.fetchSpeedLimits(bbox: box)
        let second = try await client.fetchSpeedLimits(bbox: box)
        XCTAssertEqual(first, second)
        XCTAssertEqual(first.first?.geometry?.count, 1)
        XCTAssertEqual(MockProtocol.count, 1)
    }
}

private final class MockProtocol: URLProtocol {
    static var count = 0
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.count += 1
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(#"{"elements":[{"type":"way","id":12,"nodes":[1],"geometry":[{"lat":21,"lon":105}],"tags":{"maxspeed":"50"}}]}"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
