import XCTest
import CryptoKit
@testable import VietMap
import VietMapCore

final class AppTests: XCTestCase {
    func testSettingsSanitizationAndPersistence() throws {
        let name = "VietMapTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        var settings = AppSettings()
        settings.maximumWarningDistance = 9_000
        settings.overspeedTolerance = -5
        settings.speechRate = 5
        settings.voiceEnabled = false
        settings.save(to: defaults)
        let loaded = AppSettings.load(from: defaults)
        XCTAssertEqual(loaded.maximumWarningDistance, 800)
        XCTAssertEqual(loaded.overspeedTolerance, 0)
        XCTAssertEqual(loaded.speechRate, 0.6)
        XCTAssertFalse(loaded.voiceEnabled)
    }

    func testCorruptSettingsReturnSafeDefaults() throws {
        let name = "VietMapTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(Data("broken".utf8), forKey: AppSettings.storageKey)
        XCTAssertEqual(AppSettings.load(from: defaults), AppSettings())
    }

    func testFailedImportPreservesPreviousDataset() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let repository = TrafficRepository(directory: folder.appendingPathComponent("installed"))
        let input = folder.appendingPathComponent("input.json")
        let value = makeDataset()
        try value.encoded().write(to: input)
        let imported = try await repository.importFile(input)
        XCTAssertEqual(imported.id, value.id)
        try Data("broken".utf8).write(to: input)
        do { _ = try await repository.importFile(input); XCTFail("Invalid import accepted") } catch { }
        let current = try await repository.load()
        XCTAssertEqual(current, value)
    }

    func testDemoBundledResourceIsExplicitlyMarked() async throws {
        let repository = TrafficRepository()
        let value = try await repository.demo()
        XCTAssertTrue(value.isDemo)
        XCTAssertGreaterThan(value.hazards.count, 5)
    }

    func testInterruptedTripRecoveryAndLateCheckpoint() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = TripStore(directory: folder)
        var trip = Trip(isDemo: true)
        let date = trip.startedAt
        trip.append(LocationFix(coordinate: Coordinate(latitude: 20, longitude: 106), speedMPS: 5, heading: 0, horizontalAccuracy: 5, timestamp: date), speedLimit: nil, now: date)
        try await store.checkpoint(trip)
        let recovered = try await store.recoverInterruptedTrip()
        XCTAssertTrue(recovered)
        let records = try await store.list()
        XCTAssertEqual(records.count, 1)
        XCTAssertTrue(records[0].wasInterrupted)
        try await store.checkpoint(trip)
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("active.json").path))
        let again = try await store.recoverInterruptedTrip()
        XCTAssertFalse(again)
    }

    func testRemoteURLAndChecksumAreValidatedBeforeNetwork() async throws {
        let repository = TrafficRepository()
        do {
            _ = try await repository.importRemote(urlText: "http://example.com/data.json", expectedSHA256: String(repeating: "0", count: 64))
            XCTFail("HTTP accepted")
        } catch { XCTAssertEqual(error as? DatasetError, .insecureURL) }
        do {
            _ = try await repository.importRemote(urlText: "https://example.com/data.json", expectedSHA256: "123")
            XCTFail("Bad checksum accepted")
        } catch { XCTAssertNotNil(error as? DatasetError) }
    }

    func testSummaryRecoveryIfSummaryIsMissing() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = TripStore(directory: folder)
        var trip = Trip(isDemo: true)
        trip.finish(at: trip.startedAt)
        try await store.finish(trip)
        try FileManager.default.removeItem(at: folder.appendingPathComponent(trip.id.uuidString).appendingPathComponent("summary.json"))
        let values = try await store.list()
        XCTAssertEqual(values.map(\.id), [trip.id])
    }

    func testDeletingTripAlsoRemovesLocalExportCopies() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = TripStore(directory: folder.appendingPathComponent("records"), exportDirectory: folder.appendingPathComponent("exports"))
        var trip = Trip(isDemo: true)
        trip.finish(at: trip.startedAt)
        try await store.finish(trip)
        let gpx = try await store.export(trip.id, gpx: true)
        let csv = try await store.export(trip.id, gpx: false)
        XCTAssertTrue(FileManager.default.fileExists(atPath: gpx.path))
        try await store.remove(trip.id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: gpx.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: csv.path))
        let remaining = try await store.list()
        XCTAssertTrue(remaining.isEmpty)
    }

    private func makeDataset() -> TrafficDataset {
        TrafficDataset(id: "app-tests", version: "1", name: "Synthetic", updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
                       source: DatasetSource(name: "Tests", url: "https://example.com", license: "CC0", attribution: "Synthetic"), isDemo: true,
                       roads: [RoadSegment(id: "a", name: "Test", start: Coordinate(latitude: 20, longitude: 106), end: Coordinate(latitude: 20.01, longitude: 106), speedLimit: 60)], hazards: [])
    }
}
