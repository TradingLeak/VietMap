import Foundation
import SwiftUI
import VietMapCore

enum AppAppearance: String, CaseIterable, Codable {
    case system, dark, light
    var title: String { switch self { case .system: return "Tự động"; case .dark: return "Ban đêm"; case .light: return "Ban ngày" } }
    var colorScheme: ColorScheme? { switch self { case .system: return nil; case .dark: return .dark; case .light: return .light } }
}

enum MapDisplay: String, CaseIterable, Codable {
    case standard, hybrid, offline
    var title: String { switch self { case .standard: return "Bản đồ"; case .hybrid: return "Vệ tinh"; case .offline: return "Ngoại tuyến" } }
}

struct AppSettings: Codable, Equatable {
    var appearance: AppAppearance = .dark
    var mapDisplay: MapDisplay = .standard
    var voiceEnabled = true
    var voiceIdentifier: String?
    var speechRate: Double = 0.48
    var hapticsEnabled = true
    var overspeedTolerance: Double = 3
    var maximumWarningDistance: Double = 500
    var enabledHazards: Set<HazardKind> = Set(HazardKind.allCases)
    var recordTrips = true
    var keepScreenAwake = true
    var backgroundLocation = false
    var mirrorHUD = false

    var engineConfiguration: EngineConfiguration {
        EngineConfiguration(overspeedTolerance: overspeedTolerance, maximumWarningDistance: maximumWarningDistance, enabledKinds: enabledHazards)
    }

    func sanitized() -> AppSettings {
        var copy = self
        copy.overspeedTolerance = overspeedTolerance.isFinite ? min(10, max(0, overspeedTolerance)) : 3
        copy.maximumWarningDistance = maximumWarningDistance.isFinite ? min(800, max(150, maximumWarningDistance)) : 500
        copy.speechRate = speechRate.isFinite ? min(0.6, max(0.35, speechRate)) : 0.48
        return copy
    }

    static let storageKey = "vietmap.settings.v1"

    static func load(from defaults: UserDefaults = .standard) -> AppSettings {
        guard let data = defaults.data(forKey: storageKey), let settings = try? JSONDecoder().decode(AppSettings.self, from: data) else { return AppSettings() }
        return settings.sanitized()
    }

    func save(to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(sanitized()) { defaults.set(data, forKey: Self.storageKey) }
    }
}

struct TripSummary: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let startedAt: Date
    let duration: TimeInterval
    let distanceMetres: Double
    let maximumSpeedKmh: Double
    let averageSpeedKmh: Double
    let isDemo: Bool
    let wasInterrupted: Bool
    let pointCount: Int

    init(_ trip: Trip) {
        id = trip.id; startedAt = trip.startedAt; duration = trip.duration
        distanceMetres = trip.distanceMetres; maximumSpeedKmh = trip.maximumSpeedKmh
        averageSpeedKmh = trip.averageSpeedKmh; isDemo = trip.isDemo
        wasInterrupted = trip.wasInterrupted; pointCount = trip.points.count
    }
}

extension Coordinate {
    var clCoordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
    init(_ value: CLLocationCoordinate2D) { self.init(latitude: value.latitude, longitude: value.longitude) }
}

import CoreLocation
