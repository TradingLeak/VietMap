import Foundation
import OSMData

@main
struct OSMDataFetcher {
    static func main() async {
        do { try await run() }
        catch {
            FileHandle.standardError.write(Data("Lỗi: \(error)\n".utf8))
            exit(1)
        }
    }

    static func run() async throws {
        let args = Array(CommandLine.arguments.dropFirst())
        if args.contains("--help") || args.isEmpty {
            print("""
            OSMDataFetcher --dataset <cameras|signals|speed|residential|tolls|railway|all> [--region <tên>] [--regions <file>] [--output <thư mục>] [--endpoint <URL>]
            Chạy từ thư mục gốc. Không có --region nghĩa là toàn bộ 63 vùng lịch sử; sẽ mất nhiều thời gian và tạo tải lớn.
            """)
            return
        }
        var options: [String: String] = [:]
        var i = 0
        let allowed = Set(["--dataset", "--region", "--regions", "--output", "--endpoint"])
        while i < args.count {
            guard allowed.contains(args[i]), i + 1 < args.count, options[args[i]] == nil else { throw CLIError.arguments }
            options[args[i]] = args[i + 1]; i += 2
        }
        guard let selected = options["--dataset"], ["cameras", "signals", "speed", "residential", "tolls", "railway", "all"].contains(selected) else { throw CLIError.arguments }
        let file = options["--regions"] ?? "VietNav/Resources/vietnam_regions.json"
        let catalog = try JSONDecoder().decode(VietnamRegions.self, from: Data(contentsOf: URL(fileURLWithPath: file)))
        let regions = catalog.regions.filter { options["--region"] == nil || $0.name.caseInsensitiveCompare(options["--region"]!) == .orderedSame }
        guard !regions.isEmpty else { throw CLIError.noRegions }
        let endpoint: URL
        if let string = options["--endpoint"] {
            guard let url = URL(string: string), ["http", "https"].contains(url.scheme ?? ""), url.host != nil else { throw CLIError.arguments }
            endpoint = url
        } else { endpoint = OverpassAPIClient.defaultEndpoint }
        let client = OverpassAPIClient(regions: regions, endpoint: endpoint)
        let output = URL(fileURLWithPath: options["--output"] ?? "osm-export", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        func save<T: Encodable>(_ value: T, _ filename: String) throws {
            try encoder.encode(value).write(to: output.appendingPathComponent(filename), options: .atomic)
            print("Đã lưu \(filename)")
        }
        // Chỉ ghi từng file sau khi toàn bộ request của dataset đó thành công.
        if selected == "all" || selected == "cameras" { try await save(client.fetchSpeedCameras(), "camera_data_vn.json") }
        if selected == "all" || selected == "signals" { try await save(client.fetchTrafficSignals(), "traffic_signals_vn.json") }
        if selected == "all" || selected == "speed" {
            var unique: [Int64: OSMWay] = [:]
            for region in regions {
                print("Tải maxspeed: \(region.name)")
                for way in try await client.fetchSpeedLimits(bbox: region.bbox) { unique[way.id] = way }
            }
            try save(unique.keys.sorted().compactMap { unique[$0] }, "speed_limits_vn.json")
        }
        if selected == "all" || selected == "residential" { try await save(client.fetchResidentialZones(), "residential_zones_vn.json") }
        if selected == "all" || selected == "tolls" { try await save(client.fetchTollBooths(), "toll_booths_vn.json") }
        if selected == "all" || selected == "railway" { try await save(client.fetchRailwayCrossings(), "railway_crossings_vn.json") }
    }
    enum CLIError: Error { case arguments, noRegions }
}
