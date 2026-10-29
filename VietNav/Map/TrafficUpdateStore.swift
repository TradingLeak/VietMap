import Foundation
import CryptoKit

/// Updates raw OSM extracts only; this does not activate safety warnings.
@MainActor
final class TrafficUpdateStore: ObservableObject {
    @Published private(set) var status = "Chưa kiểm tra cập nhật."
    @Published private(set) var busy = false
    private struct Release: Decodable {
        struct Asset: Decodable { let name: String; let browser_download_url: URL }
        let tag_name: String
        let draft: Bool
        let prerelease: Bool
        let assets: [Asset]
    }
    private struct Manifest: Decodable {
        let schema: Int
        let version: String
        let generated_at_utc: String
        let size: Int64
        let sha256: String
    }
    private let maxBytes: Int64 = 256 * 1024 * 1024
    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 45
        config.timeoutIntervalForResource = 600
        return URLSession(configuration: config)
    }()
    private func checkedAssetURL(_ url: URL, tag: String, name: String) -> Bool {
        url.scheme == "https" && url.host == "github.com" && url.path == "/TradingLeak/VietMap/releases/download/\(tag)/\(name)"
    }
    private func checkedResponse(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
              http.url?.scheme == "https" else { throw UpdateError.invalidResponse }
    }
    func update() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            status = "Đang kiểm tra GitHub…"
            var request = URLRequest(url: URL(string: "https://api.github.com/repos/TradingLeak/VietMap/releases?per_page=100")!)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            let (responseData, response) = try await session.data(for: request)
            try checkedResponse(response)
            guard responseData.count < 2_000_000 else { throw UpdateError.invalidResponse }
            let releases = try JSONDecoder().decode([Release].self, from: responseData)
            guard let release = releases.first(where: { !$0.draft && !$0.prerelease && $0.tag_name.hasPrefix("traffic-") && $0.assets.contains(where: { $0.name == "traffic-manifest.json" }) && $0.assets.contains(where: { $0.name == "vietnam-traffic.sqlite" }) }),
                  let manifestAsset = release.assets.first(where: { $0.name == "traffic-manifest.json" }),
                  let databaseAsset = release.assets.first(where: { $0.name == "vietnam-traffic.sqlite" }),
                  checkedAssetURL(manifestAsset.browser_download_url, tag: release.tag_name, name: manifestAsset.name),
                  checkedAssetURL(databaseAsset.browser_download_url, tag: release.tag_name, name: databaseAsset.name) else { throw UpdateError.noRelease }
            let (manifestData, manifestResponse) = try await session.data(from: manifestAsset.browser_download_url)
            try checkedResponse(manifestResponse)
            guard manifestData.count < 64_000 else { throw UpdateError.invalidManifest }
            let manifest = try JSONDecoder().decode(Manifest.self, from: manifestData)
            guard manifest.schema == 2, manifest.version == release.tag_name,
                  manifest.size > 100, manifest.size <= maxBytes,
                  manifest.sha256.count == 64, manifest.sha256.allSatisfy({ $0.isHexDigit }) else { throw UpdateError.invalidManifest }
            status = "Đang tải dữ liệu OSM…"
            let (tempURL, fileResponse) = try await session.download(from: databaseAsset.browser_download_url)
            try checkedResponse(fileResponse)
            let attrs = try FileManager.default.attributesOfItem(atPath: tempURL.path)
            guard (attrs[.size] as? NSNumber)?.int64Value == manifest.size else { throw UpdateError.invalidFile }
            let handle = try FileHandle(forReadingFrom: tempURL)
            defer { try? handle.close() }
            guard try handle.read(upToCount: 16) == Data("SQLite format 3\0".utf8) else { throw UpdateError.invalidFile }
            try handle.seek(toOffset: 0)
            var sha = SHA256()
            while let chunk = try handle.read(upToCount: 1024 * 1024), !chunk.isEmpty { sha.update(data: chunk) }
            let actual = sha.finalize().map { String(format: "%02x", $0) }.joined()
            guard actual == manifest.sha256.lowercased() else { throw UpdateError.invalidFile }
            let fm = FileManager.default
            let base = try fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            try fm.createDirectory(at: base, withIntermediateDirectories: true)
            let target = base.appendingPathComponent("vietnam-traffic.sqlite")
            let stage = base.appendingPathComponent("traffic-\(UUID().uuidString).tmp")
            defer { try? fm.removeItem(at: stage) }
            try fm.copyItem(at: tempURL, to: stage)
            if fm.fileExists(atPath: target.path) { _ = try fm.replaceItemAt(target, withItemAt: stage) }
            else { try fm.moveItem(at: stage, to: target) }
            UserDefaults.standard.set(manifest.version, forKey: "trafficDataVersion")
            status = "Đã tải \(manifest.version) (nguồn: \(manifest.generated_at_utc)). Chưa hỗ trợ cảnh báo."
        } catch {
            status = "Không cập nhật được: \(error.localizedDescription). Dữ liệu cũ được giữ lại."
        }
    }
    private enum UpdateError: LocalizedError {
        case invalidResponse, noRelease, invalidManifest, invalidFile
        var errorDescription: String? {
            switch self {
            case .invalidResponse: return "phản hồi mạng không hợp lệ"
            case .noRelease: return "chưa có bản dữ liệu công khai"
            case .invalidManifest: return "thông tin gói không hợp lệ"
            case .invalidFile: return "kích thước hoặc mã kiểm tra không khớp"
            }
        }
    }
}
