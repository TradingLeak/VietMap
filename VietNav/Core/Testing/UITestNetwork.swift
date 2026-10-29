import Foundation

/// Stub chỉ được biên dịch ở DEBUG và chỉ được bật bằng launch argument của UI test.
enum UITestNetwork {
    static func session() -> URLSession {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-vietnav-ui-testing") {
            let config = URLSessionConfiguration.ephemeral
            config.protocolClasses = [UITestURLProtocol.self]
            return URLSession(configuration: config)
        }
        #endif
        return .shared
    }
}
#if DEBUG
private final class UITestURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "nominatim.openstreetmap.org" || request.url?.host == "router.project-osrm.org"
    }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url else { return }
        let search = url.host == "nominatim.openstreetmap.org"
        let body = search ? #"[{"place_id":99,"osm_type":"node","osm_id":99,"display_name":"Điểm thử nghiệm, Hà Nội, Việt Nam","lat":"21.0400","lon":"105.8600","category":"place","type":"city","address":{"city":"Hà Nội"},"importance":0.5}]"# : #"{"code":"Ok","routes":[{"distance":1600,"duration":240,"geometry":{"type":"LineString","coordinates":[[105.8542,21.0285],[105.8570,21.0340],[105.8600,21.0400]]},"legs":[{"steps":[{"distance":600,"duration":100,"name":"","maneuver":{"type":"depart","location":[105.8542,21.0285]}},{"distance":1000,"duration":140,"name":"Đường thử nghiệm","maneuver":{"type":"turn","modifier":"right","location":[105.8570,21.0340]}},{"distance":0,"duration":0,"name":"","maneuver":{"type":"arrive","location":[105.8600,21.0400]}}]}]}]}"#
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
#endif
