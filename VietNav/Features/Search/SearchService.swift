import Foundation
import CoreLocation

public enum PlaceCategory: String, Codable, CaseIterable {
    case restaurant, cafe, hotel, hospital, school, bank, gasStation, shopping, atm, pharmacy, parking, busStation, airport, tourism, government, religious, other
}
public struct PlaceAddress: Codable, Equatable {
    public var houseNumber: String?
    public var street: String?
    public var ward: String?
    public var district: String?
    public var city: String?
    public var country: String?
    public init(houseNumber: String? = nil, street: String? = nil, ward: String? = nil, district: String? = nil, city: String? = nil, country: String? = nil) {
        self.houseNumber = houseNumber; self.street = street; self.ward = ward; self.district = district; self.city = city; self.country = country
    }
    public var formatted: String {
        [houseNumber, street, ward, district, city].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.joined(separator: ", ")
    }
}
public struct SearchResult: Identifiable, Codable {
    public let id: String
    public let displayName: String
    public let shortName: String
    private let latitude: Double
    private let longitude: Double
    public var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
    public let category: PlaceCategory
    public let address: PlaceAddress
    public let importance: Double
    public init(id: String, displayName: String, shortName: String, coordinate: CLLocationCoordinate2D, category: PlaceCategory, address: PlaceAddress, importance: Double) {
        self.id = id; self.displayName = displayName; self.shortName = shortName
        latitude = coordinate.latitude; longitude = coordinate.longitude; self.category = category; self.address = address; self.importance = importance
    }
}
public struct SearchSuggestion: Identifiable {
    public var id: String { result.id }
    public let result: SearchResult
    public init(result: SearchResult) { self.result = result }
}
public protocol SearchServiceProtocol {
    func search(query: String) async throws -> [SearchResult]
    func reverseGeocode(coordinate: CLLocationCoordinate2D) async throws -> SearchResult?
    /// Chỉ gợi ý cục bộ; public Nominatim không cho phép autocomplete.
    func autocomplete(query: String) async throws -> [SearchSuggestion]
}
public enum SearchServiceError: Error, LocalizedError {
    case invalidQuery, invalidCoordinate, invalidURL, http(Int), invalidResponse
    public var errorDescription: String? {
        switch self {
        case .invalidQuery: return "Nhập từ 3 đến 200 ký tự."
        case .invalidCoordinate: return "Tọa độ không hợp lệ."
        case .invalidURL: return "Địa chỉ dịch vụ tìm kiếm không hợp lệ."
        case .http(let status): return "Dịch vụ tìm kiếm trả về HTTP \(status)."
        case .invalidResponse: return "Dữ liệu tìm kiếm không hợp lệ."
        }
    }
}

/// Một request chạy tại một thời điểm và cách nhau >=1,1 giây trong tiến trình.
actor NominatimRateLimiter {
    static let shared = NominatimRateLimiter()
    private var active = false
    private var nextStart: TimeInterval = 0
    func acquire() async throws {
        while true {
            try Task.checkCancellation()
            let now = ProcessInfo.processInfo.systemUptime
            if !active && now >= nextStart { active = true; nextStart = now + 1.1; return }
            let seconds = max(0.05, min(0.25, nextStart - now))
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        }
    }
    func release() { active = false }
}

public actor NominatimSearchService: SearchServiceProtocol {
    public static let shared = NominatimSearchService()
    private let session: URLSession
    private let endpoint: URL
    private let storage: SearchPersistence
    private let userAgent: String
    public init(endpoint: URL = URL(string: "https://nominatim.openstreetmap.org/search")!,
                session: URLSession? = nil, storage: SearchPersistence = .shared,
                userAgent: String = "VietNav/1.0 (https://github.com/TradingLeak/VietMap)") {
        self.endpoint = endpoint; self.session = session ?? UITestNetwork.session(); self.storage = storage; self.userAgent = userAgent
    }
    public func search(query: String) async throws -> [SearchResult] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 3, text.count <= 200 else { throw SearchServiceError.invalidQuery }
        let key = "search|\(endpoint.absoluteString)|\(text.lowercased())"
        if let cached = try await storage.cached(key: key) { return cached }
        let data = try await request(url: endpoint, items: [
            .init(name: "q", value: text), .init(name: "format", value: "jsonv2"),
            .init(name: "countrycodes", value: "vn"), .init(name: "limit", value: "10"),
            .init(name: "addressdetails", value: "1"), .init(name: "accept-language", value: "vi")
        ])
        let raw: [NominatimPlace]
        do { raw = try JSONDecoder().decode([NominatimPlace].self, from: data) } catch { throw SearchServiceError.invalidResponse }
        let results = raw.compactMap { $0.result() }
        try await storage.cache(results, key: key)
        return results
    }
    public func reverseGeocode(coordinate: CLLocationCoordinate2D) async throws -> SearchResult? {
        guard coordinate.latitude.isFinite, coordinate.longitude.isFinite, CLLocationCoordinate2DIsValid(coordinate) else { throw SearchServiceError.invalidCoordinate }
        let lat = String(format: "%.7f", locale: Locale(identifier: "en_US_POSIX"), coordinate.latitude)
        let lon = String(format: "%.7f", locale: Locale(identifier: "en_US_POSIX"), coordinate.longitude)
        let url = endpoint.deletingLastPathComponent().appendingPathComponent("reverse")
        let key = "reverse|\(url.absoluteString)|\(lat),\(lon)"
        if let cached = try await storage.cached(key: key) { return cached.first }
        let data: Data
        do {
            data = try await request(url: url, items: [.init(name: "lat", value: lat), .init(name: "lon", value: lon), .init(name: "format", value: "jsonv2"), .init(name: "addressdetails", value: "1"), .init(name: "accept-language", value: "vi")])
        } catch SearchServiceError.http(404) { try await storage.cache([], key: key); return nil }
        if let error = try? JSONDecoder().decode(NominatimError.self, from: data), !error.error.isEmpty {
            if error.error.lowercased().contains("unable to geocode") {
                try await storage.cache([], key: key); return nil
            }
            throw SearchServiceError.invalidResponse
        }
        guard let place = try? JSONDecoder().decode(NominatimPlace.self, from: data), let result = place.result() else { throw SearchServiceError.invalidResponse }
        try await storage.cache([result], key: key)
        return result
    }
    public func autocomplete(query: String) async throws -> [SearchSuggestion] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return [] }
        // Chỉ dùng lịch sử/yêu thích trên thiết bị, không gửi autocomplete lên mạng.
        var seen = Set<String>()
        let favorites = try await storage.favorites().map(\.place)
        let recent = try await storage.recent()
        return (favorites + recent).filter { item in
            item.displayName.range(of: term, options: [.caseInsensitive, .diacriticInsensitive]) != nil && seen.insert(item.id).inserted
        }.prefix(10).map(SearchSuggestion.init(result:))
    }
    private func request(url: URL, items: [URLQueryItem]) async throws -> Data {
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil,
              !userAgent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw SearchServiceError.invalidURL }
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.queryItems = items
        guard let requestURL = components?.url else { throw SearchServiceError.invalidURL }
        var request = URLRequest(url: requestURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("vi", forHTTPHeaderField: "Accept-Language")
        try await NominatimRateLimiter.shared.acquire()
        let result: (Data, URLResponse)
        do { result = try await session.data(for: request) }
        catch { await NominatimRateLimiter.shared.release(); throw error }
        await NominatimRateLimiter.shared.release()
        guard let http = result.1 as? HTTPURLResponse else { throw SearchServiceError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw SearchServiceError.http(http.statusCode) }
        return result.0
    }
}

/// Chỉ dịch toàn bộ thành phần địa chỉ, không thay thế chuỗi con của tên riêng.
public func localizePlaceName(_ name: String) -> String {
    let translations = ["Vietnam": "Việt Nam", "Hanoi": "Hà Nội", "Ho Chi Minh City": "TP. Hồ Chí Minh", "Da Nang": "Đà Nẵng", "Hai Phong": "Hải Phòng", "Can Tho": "Cần Thơ"]
    return name.components(separatedBy: ",").map { part in
        let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
        return translations[trimmed] ?? trimmed
    }.joined(separator: ", ")
}
private struct NominatimError: Decodable { let error: String }
private struct NominatimPlace: Decodable {
    let place_id: Int64
    let osm_type: String?
    let osm_id: Int64?
    let display_name: String
    let name: String?
    let lat: String
    let lon: String
    let category: String?
    let type: String?
    let importance: Double?
    let address: [String: String]?
    func result() -> SearchResult? {
        guard let latitude = Double(lat), let longitude = Double(lon), latitude.isFinite, longitude.isFinite else { return nil }
        let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        guard CLLocationCoordinate2DIsValid(coordinate) else { return nil }
        let a = address ?? [:]
        let address = PlaceAddress(houseNumber: a["house_number"], street: a["road"] ?? a["pedestrian"],
            ward: a["suburb"] ?? a["quarter"] ?? a["neighbourhood"] ?? a["village"],
            district: a["city_district"] ?? a["municipality"] ?? a["county"], city: (a["city"] ?? a["town"] ?? a["state"]).map(localizePlaceName), country: a["country"].map(localizePlaceName))
        let display = localizePlaceName(display_name)
        let short = (name?.isEmpty == false ? name : nil) ?? display.components(separatedBy: ",").first ?? display
        let id = osm_type.flatMap { type in osm_id.map { "\(type)/\($0)" } } ?? "place/\(place_id)"
        return SearchResult(id: id, displayName: display, shortName: localizePlaceName(short), coordinate: coordinate,
                            category: Self.category(category, type), address: address, importance: importance ?? 0)
    }
    static func category(_ category: String?, _ type: String?) -> PlaceCategory {
        switch type {
        case "restaurant", "fast_food": return .restaurant
        case "cafe": return .cafe
        case "hotel", "guest_house", "motel": return .hotel
        case "hospital", "clinic": return .hospital
        case "school", "university", "college": return .school
        case "bank": return .bank
        case "fuel": return .gasStation
        case "atm": return .atm
        case "pharmacy": return .pharmacy
        case "parking": return .parking
        case "bus_station", "bus_stop": return .busStation
        case "aerodrome": return .airport
        case "government", "townhall", "public_building": return .government
        case "place_of_worship": return .religious
        default: break
        }
        if category == "shop" { return .shopping }
        if category == "tourism" { return .tourism }
        return .other
    }
}
