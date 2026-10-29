import Foundation
import XCTest
@testable import VietNavCore

final class TrafficDataUpdateTests: XCTestCase {
    func testRejectsInsecureURLWithoutNetwork() async throws {
        let service = TrafficDataUpdateService(manifestURL: URL(string: "http://example.test/manifest.json")!, database: TrafficDatabase(databasePath: ":memory:", findBundledSeed: false))
        do { _ = try await service.checkForDataUpdates(); XCTFail("HTTP must be rejected") }
        catch TrafficUpdateError.invalidManifest {} catch { XCTFail("Unexpected \(error)") }
    }
    func testRejectsMalformedManifestWithoutTouchingDatabase() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [InvalidManifestProtocol.self]
        let db = TrafficDatabase(databasePath: ":memory:", findBundledSeed: false)
        try db.saveUserReport(UserReport(type: .incident, description: "safe"))
        let service = TrafficDataUpdateService(manifestURL: URL(string: "https://example.test/manifest.json")!, session: URLSession(configuration: config), database: db)
        do { _ = try await service.checkForDataUpdates(); XCTFail("Invalid schema must be rejected") }
        catch TrafficUpdateError.invalidManifest {} catch { XCTFail("Unexpected \(error)") }
        XCTAssertEqual(try db.getPendingReports().first?.description, "safe")
    }
}
private final class InvalidManifestProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(#"{"version":"20261029T000000Z","schema":999,"file":"vietnam_traffic.sqlite","sha256":"0000000000000000000000000000000000000000000000000000000000000000","size":1}"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
