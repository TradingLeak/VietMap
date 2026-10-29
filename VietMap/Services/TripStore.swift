import Foundation
import VietMapCore

actor TripStore {
    private let directory: URL
    private var finalized = Set<UUID>()
    private var activeURL: URL { directory.appendingPathComponent("active.json") }

    init(directory: URL = AppDirectories.support.appendingPathComponent("Trips", isDirectory: true)) {
        self.directory = directory
    }

    func list() throws -> [TripSummary] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        let folders = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { UUID(uuidString: $0.lastPathComponent) != nil }
        var result: [TripSummary] = []
        for folder in folders {
            let summaryURL = folder.appendingPathComponent("summary.json")
            if let data = try? Data(contentsOf: summaryURL), let summary = try? decoder.decode(TripSummary.self, from: data) {
                result.append(summary)
            } else if let id = UUID(uuidString: folder.lastPathComponent), let trip = try? load(id) {
                // Recover a completed trip even if the app was terminated before summary writing.
                let summary = TripSummary(trip)
                try write(summary, to: summaryURL)
                result.append(summary)
            }
        }
        return result.sorted { $0.startedAt > $1.startedAt }
    }

    func checkpoint(_ trip: Trip) throws {
        guard !finalized.contains(trip.id) else { return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try write(trip, to: activeURL)
    }

    func finish(_ trip: Trip) throws {
        let folder = directory.appendingPathComponent(trip.id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try write(trip, to: folder.appendingPathComponent("trip.json"))
        try write(TripSummary(trip), to: folder.appendingPathComponent("summary.json"))
        finalized.insert(trip.id)
        if let data = try? Data(contentsOf: activeURL), let active = try? decoder.decode(Trip.self, from: data), active.id == trip.id {
            try FileManager.default.removeItem(at: activeURL)
        }
    }

    func recoverInterruptedTrip() throws -> Bool {
        guard FileManager.default.fileExists(atPath: activeURL.path) else { return false }
        var trip = try decoder.decode(Trip.self, from: Data(contentsOf: activeURL))
        guard !FileManager.default.fileExists(atPath: directory.appendingPathComponent(trip.id.uuidString).appendingPathComponent("trip.json").path) else {
            try FileManager.default.removeItem(at: activeURL)
            return false
        }
        trip.finish(at: trip.points.last?.timestamp ?? trip.startedAt, interrupted: true)
        try finish(trip)
        return true
    }

    func load(_ id: UUID) throws -> Trip {
        let url = directory.appendingPathComponent(id.uuidString).appendingPathComponent("trip.json")
        return try decoder.decode(Trip.self, from: Data(contentsOf: url))
    }

    func remove(_ id: UUID) throws {
        let url = directory.appendingPathComponent(id.uuidString)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }

    func deleteAll() throws {
        if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
    }

    func export(_ id: UUID, gpx: Bool) throws -> URL {
        let trip = try load(id)
        let content = gpx ? TripExport.gpx(trip) : TripExport.csv(trip)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("VietMap-\(id.uuidString).\(gpx ? "gpx" : "csv")")
        try Data(content.utf8).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        return url
    }

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601; return decoder
    }

    private func write<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(value).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}
