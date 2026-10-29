import Foundation
import CryptoKit
import VietMapCore

actor TrafficRepository {
    private let directory: URL
    private var datasetURL: URL { directory.appendingPathComponent("traffic.json") }

    init(directory: URL = AppDirectories.support.appendingPathComponent("Traffic", isDirectory: true)) {
        self.directory = directory
    }

    func load() throws -> TrafficDataset? {
        guard FileManager.default.fileExists(atPath: datasetURL.path) else { return nil }
        return try TrafficDataset.decode(Self.readBounded(datasetURL))
    }

    func demo() throws -> TrafficDataset {
        guard let url = Bundle.main.url(forResource: "demo-traffic", withExtension: "json") else {
            throw DatasetError.invalid("Không tìm thấy dữ liệu mô phỏng đi kèm ứng dụng.")
        }
        let value = try TrafficDataset.decode(Self.readBounded(url))
        guard value.isDemo else { throw DatasetError.invalid("Tệp mô phỏng chưa được đánh dấu an toàn.") }
        return value
    }

    func importFile(_ url: URL) throws -> TrafficDataset {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        return try install(Self.readBounded(url))
    }

    func importRemote(urlText: String, expectedSHA256: String) async throws -> TrafficDataset {
        let checksum = expectedSHA256.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard checksum.count == 64, checksum.allSatisfy({ "0123456789abcdef".contains($0) }) else {
            throw DatasetError.invalid("Cần mã SHA-256 gồm đúng 64 ký tự hệ 16 từ một nguồn bạn tin cậy.")
        }
        guard let url = URL(string: urlText.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme?.lowercased() == "https", url.host != nil, url.user == nil, url.password == nil else { throw DatasetError.insecureURL }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 120
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        let session = URLSession(configuration: configuration, delegate: HTTPSOnlyRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(from: url)
        guard let http = response as? HTTPURLResponse else { throw DatasetError.invalid("Phản hồi máy chủ không hợp lệ.") }
        guard http.statusCode == 200 else { throw DatasetError.server(http.statusCode) }
        guard http.url?.scheme?.lowercased() == "https" else { throw DatasetError.insecureURL }
        guard response.expectedContentLength <= Int64(TrafficDataset.maximumBytes) else { throw DatasetError.tooLarge }
        var data = Data()
        data.reserveCapacity(Int(max(0, response.expectedContentLength)))
        for try await byte in bytes {
            guard data.count < TrafficDataset.maximumBytes else { throw DatasetError.tooLarge }
            data.append(byte)
            if data.count % 16_384 == 0 { try Task.checkCancellation() }
        }
        try Task.checkCancellation()
        let actual = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard actual == checksum else { throw DatasetError.checksumMismatch }
        return try install(data)
    }

    func remove() throws {
        if FileManager.default.fileExists(atPath: datasetURL.path) { try FileManager.default.removeItem(at: datasetURL) }
    }

    func prepareEngine(dataset: TrafficDataset?, configuration: EngineConfiguration) throws -> TrafficEngine {
        if let dataset { return try TrafficEngine(dataset: dataset, configuration: configuration) }
        return TrafficEngine(configuration: configuration)
    }

    private func install(_ data: Data) throws -> TrafficDataset {
        let value = try TrafficDataset.decode(data)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Set directory policy before commit: even a metadata failure must preserve old data.
        var resource = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try resource.setResourceValues(values)
        // Decode and validate BEFORE atomically replacing the last working dataset.
        try data.write(to: datasetURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        return value
    }

    private static func readBounded(_ url: URL) throws -> Data {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= TrafficDataset.maximumBytes else { throw DatasetError.tooLarge }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard data.count <= TrafficDataset.maximumBytes else { throw DatasetError.tooLarge }
        return data
    }
}

private final class HTTPSOnlyRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        let url = request.url
        completionHandler(url?.scheme?.lowercased() == "https" && url?.user == nil && url?.password == nil ? request : nil)
    }
}

enum AppDirectories {
    static var support: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            .map { $0.appendingPathComponent("VietMap", isDirectory: true) }
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("VietMap", isDirectory: true)
    }
}
