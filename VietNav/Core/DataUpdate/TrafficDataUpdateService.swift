import Foundation
import CryptoKit

public enum TrafficUpdateError: Error { case invalidManifest, invalidDownload, checksumMismatch }

/// Cần manifest HTTPS trên host đáng tin cậy. Không tự chạy; gọi chủ động khi không dẫn đường.
public actor TrafficDataUpdateService {
    private struct Manifest: Decodable {
        let version: String
        let schema: Int
        let file: String
        let sha256: String
        let size: Int64
    }
    private let manifestURL: URL
    private let session: URLSession
    private let database: TrafficDatabase
    private let maxBytes: Int64 = 200 * 1024 * 1024
    public init(manifestURL: URL, session: URLSession = .shared, database: TrafficDatabase = .shared) {
        self.manifestURL = manifestURL; self.session = session; self.database = database
    }
    /// true nếu có bản mới được cài; false nếu version không mới. Lỗi không sửa DB.
    public func checkForDataUpdates() async throws -> Bool {
        guard manifestURL.scheme?.lowercased() == "https", let host = manifestURL.host,
              manifestURL.user == nil, manifestURL.password == nil else { throw TrafficUpdateError.invalidManifest }
        let (data, response) = try await session.data(from: manifestURL)
        guard data.count <= 32_768, valid(response, host: host) else { throw TrafficUpdateError.invalidManifest }
        let manifest = try JSONDecoder().decode(Manifest.self, from: data)
        guard manifest.schema == 1, manifest.file == "vietnam_traffic.sqlite",
              manifest.version.range(of: "^[0-9]{8}T[0-9]{6}Z$", options: .regularExpression) != nil,
              manifest.sha256.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil,
              manifest.size > 0, manifest.size <= maxBytes else { throw TrafficUpdateError.invalidManifest }
        let installedVersion = try await Task.detached(priority: .utility) { [database] in try database.trafficDataVersion() }.value
        guard manifest.version > installedVersion else { return false }
        let fileURL = manifestURL.deletingLastPathComponent().appendingPathComponent(manifest.file)
        let (temporary, fileResponse) = try await session.download(from: fileURL)
        defer { try? FileManager.default.removeItem(at: temporary) }
        guard valid(fileResponse, host: host),
              let size = (try FileManager.default.attributesOfItem(atPath: temporary.path)[.size] as? NSNumber)?.int64Value,
              size == manifest.size else { throw TrafficUpdateError.invalidDownload }
        let handle = try FileHandle(forReadingFrom: temporary)
        defer { try? handle.close() }
        var hash = SHA256()
        while let chunk = try handle.read(upToCount: 1024 * 1024), !chunk.isEmpty {
            try Task.checkCancellation(); hash.update(data: chunk)
        }
        let actual = hash.finalize().map { String(format: "%02x", $0) }.joined()
        guard actual == manifest.sha256 else { throw TrafficUpdateError.checksumMismatch }
        try Task.checkCancellation()
        return try await Task.detached(priority: .utility) { [database] in
            try database.installTrafficUpdate(from: temporary.path, version: manifest.version)
        }.value
    }
    private func valid(_ response: URLResponse, host: String) -> Bool {
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let url = http.url else { return false }
        return url.scheme?.lowercased() == "https" && url.host?.lowercased() == host.lowercased()
    }
}
