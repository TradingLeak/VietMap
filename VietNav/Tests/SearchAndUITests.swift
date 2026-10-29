import XCTest
import Foundation
@testable import VietNavCore

final class SearchAndUITests: XCTestCase {
    func testSearchUsesExplicitCountryAndCache() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SearchMockProtocol.self]
        let service = NominatimSearchService(endpoint: URL(string: "https://example.test/search")!, session: URLSession(configuration: config), storage: SearchPersistence(path: ":memory:"))
        SearchMockProtocol.reset()
        let places = try await service.search(query: "Hà Nội")
        XCTAssertEqual(places.count, 1)
        XCTAssertEqual(places[0].coordinate.latitude, 21.0285, accuracy: 0.00001)
        let request = try XCTUnwrap(SearchMockProtocol.request)
        XCTAssertNotNil(request.value(forHTTPHeaderField: "User-Agent"))
        let items = URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(items.first { $0.name == "countrycodes" }?.value, "vn")
        XCTAssertEqual(items.first { $0.name == "q" }?.value, "Hà Nội")
        _ = try await service.search(query: "Hà Nội")
        XCTAssertEqual(SearchMockProtocol.count, 1)
    }
    func testReverseAndLocalSuggestions() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SearchMockProtocol.self]
        let storage = SearchPersistence(path: ":memory:")
        let service = NominatimSearchService(endpoint: URL(string: "https://example.test/search")!, session: URLSession(configuration: config), storage: storage)
        SearchMockProtocol.reset()
        let result = try await service.reverseGeocode(coordinate: .init(latitude: 21.0285, longitude: 105.8542))
        let place = try XCTUnwrap(result)
        XCTAssertEqual(place.id, "node/9")
        XCTAssertEqual(place.displayName, "Hà Nội, Việt Nam")
        XCTAssertEqual(place.address.street, "Phạm Văn Đồng")
        XCTAssertEqual(place.category, .cafe)
        try await storage.addRecent(place)
        let suggestions = try await service.autocomplete(query: "ha noi")
        XCTAssertEqual(suggestions.count, 1)
        XCTAssertEqual(SearchMockProtocol.count, 1) // autocomplete không dùng mạng
        let again = try await service.reverseGeocode(coordinate: .init(latitude: 21.0285, longitude: 105.8542))
        XCTAssertEqual(again?.id, place.id)
        XCTAssertEqual(SearchMockProtocol.count, 1)
    }

    func testPersistenceExpiryAndFavorites() async throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite")
        defer { try? FileManager.default.removeItem(at: path) }
        var now = Date(timeIntervalSince1970: 1_000_000)
        let storage = SearchPersistence(path: path.path, clock: { now })
        let result = SearchResult(id: "node/1", displayName: "Hà Nội", shortName: "Hà Nội", coordinate: .init(latitude: 21, longitude: 105), category: .other, address: .init(city: "Hà Nội"), importance: 0.5)
        try await storage.cache([result], key: "q")
        try await storage.addRecent(result)
        try await storage.saveFavorite(.init(id: "home", label: "Nhà", place: result))
        let reopened = SearchPersistence(path: path.path, clock: { now })
        let favoriteList = try await reopened.favorites()
        let history = try await reopened.recent()
        XCTAssertEqual(favoriteList.first?.place.id, result.id)
        XCTAssertEqual(history.first?.id, result.id)
        now.addTimeInterval(7 * 86400 + 1)
        let expired = try await reopened.cached(key: "q")
        XCTAssertNil(expired)
        try await reopened.removeFavorite(id: "home")
        try await reopened.clearRecent()
        let remainingFavorites = try await reopened.favorites()
        let remainingRecent = try await reopened.recent()
        XCTAssertTrue(remainingFavorites.isEmpty)
        XCTAssertTrue(remainingRecent.isEmpty)
    }

    func testLocalizationOnlyChangesWholeComponents() {
        XCTAssertEqual(localizePlaceName("Hanoi, Vietnam"), "Hà Nội, Việt Nam")
        XCTAssertEqual(localizePlaceName("Hanoi Bank, Vietnam"), "Hanoi Bank, Việt Nam")
    }

    func testSearchRejectsShortQuery() async throws {
        let service = NominatimSearchService()
        do { _ = try await service.search(query: "ab"); XCTFail("Expected invalid query") }
        catch SearchServiceError.invalidQuery {} catch { XCTFail("Unexpected error \(error)") }
    }
    func testDistanceAndDurationFormatting() {
        XCTAssertEqual(NavigationFormat.distance(500), "500 m")
        XCTAssertEqual(NavigationFormat.distance(1500), "1.5 km")
        XCTAssertEqual(NavigationFormat.distance(1609.344, unit: "mi"), "1.0 mi")
        XCTAssertEqual(NavigationFormat.duration(3660), "1 giờ 1 phút")
    }
}
private final class SearchMockProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var storedCount = 0
    private static var storedRequest: URLRequest?
    static var count: Int { lock.lock(); defer { lock.unlock() }; return storedCount }
    static var request: URLRequest? { lock.lock(); defer { lock.unlock() }; return storedRequest }
    static func reset() { lock.lock(); defer { lock.unlock() }; storedCount = 0; storedRequest = nil }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock(); Self.storedRequest = request; Self.storedCount += 1; Self.lock.unlock()
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        let json = #"{"place_id":1,"osm_type":"node","osm_id":9,"display_name":"Hanoi, Vietnam","lat":"21.0285","lon":"105.8542","category":"amenity","type":"cafe","address":{"road":"Phạm Văn Đồng","city":"Hà Nội"},"importance":0.6}"#
        let text = request.url?.path.hasSuffix("/reverse") == true ? json : "[\(json)]"
        client?.urlProtocol(self, didLoad: Data(text.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
