import SwiftUI
import Combine
import UIKit
import VietMapCore

@MainActor
final class AppModel: ObservableObject {
    enum DriveMode { case idle, live, demo }

    @Published var settings: AppSettings {
        didSet {
            settings.save()
            engine.configuration = settings.engineConfiguration
            speech.configure(settings)
            location.configureBackground(mode == .live && settings.backgroundLocation)
            updateIdleTimer()
        }
    }
    @Published private(set) var mode: DriveMode = .idle
    @Published private(set) var snapshot: DrivingSnapshot = .unavailable
    @Published private(set) var latestFix: LocationFix?
    @Published private(set) var lastCoordinate: Coordinate?
    @Published private(set) var importedDataset: TrafficDataset?
    @Published private(set) var demoDataset: TrafficDataset?
    @Published private(set) var nearbyRoads: [RoadSegment] = []
    @Published private(set) var nearbyHazards: [TrafficHazard] = []
    private var lastMapCoordinate: Coordinate?
    @Published private(set) var currentTrip: Trip?
    @Published private(set) var trips: [TripSummary] = []
    @Published private(set) var isBusy = false
    @Published private(set) var isReady = false
    @Published var showOnboarding: Bool
    @Published var showHUD = false
    @Published var errorMessage: String?
    @Published var notice: String?
    @Published var storageWarning: String?

    let location = LocationService()
    let speech = SpeechService()
    let navigation = NavigationService()
    private let traffic: TrafficRepository
    private let tripStore: TripStore
    private var engine = TrafficEngine()
    private var demoDriver: DemoDriver?
    private var timer: Timer?
    private var lastTick = Date()
    private var lastCheckpoint = Date.distantPast
    private var isForeground = true

    init(traffic: TrafficRepository = TrafficRepository(), tripStore: TripStore = TripStore()) {
        self.traffic = traffic
        self.tripStore = tripStore
        let testing = ProcessInfo.processInfo.arguments.contains("-ui-testing")
        var initial = testing ? AppSettings() : AppSettings.load()
        if testing { initial.voiceEnabled = false }
        settings = initial
        showOnboarding = !testing && !UserDefaults.standard.bool(forKey: "vietmap.onboarding.v1")
        speech.configure(settings)
        location.onFix = { [weak self] fix in self?.receive(fix) }
        location.onDenied = { [weak self] in
            guard let self else { return }
            self.errorMessage = self.location.errorMessage ?? "Cần quyền vị trí để sử dụng GPS thật."
            self.stopDriving()
        }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
    }

    var displayDataset: TrafficDataset? {
        if mode == .demo { return demoDataset }
        return importedDataset?.isDemo == false ? importedDataset : nil
    }
    var isDriving: Bool { mode != .idle }
    var canEdit: Bool { mode != .live || (snapshot.isReliable && (snapshot.speedKmh ?? .infinity) < 5) }
    var canManageData: Bool { mode == .idle && !isBusy && isReady }
    var hasRealData: Bool { importedDataset?.isDemo == false }
    var statusTitle: String {
        if mode == .demo { return "MÔ PHỎNG" }
        if mode == .idle { return "SẴN SÀNG" }
        return snapshot.isReliable ? "GPS TỐT" : "CHỜ GPS"
    }

    func bootstrap() async {
        guard !isReady else { return }
        isBusy = true
        do { importedDataset = try await traffic.load() }
        catch { errorMessage = "Không đọc được dữ liệu đã nhập: \(error.localizedDescription)" }
        do {
            if try await tripStore.recoverInterruptedTrip() { notice = "Đã khôi phục hành trình bị gián đoạn từ bản lưu tự động gần nhất." }
            trips = try await tripStore.list()
        } catch { storageWarning = "Không đọc được lịch sử: \(error.localizedDescription)" }
        isBusy = false
        isReady = true
    }

    func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: "vietmap.onboarding.v1")
        showOnboarding = false
    }

    func startDriving() async {
        guard mode == .idle, !isBusy, isReady, !showOnboarding else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            // The demo bundle is never passed to the live traffic engine.
            engine = try await traffic.prepareEngine(dataset: hasRealData ? importedDataset : nil, configuration: settings.engineConfiguration)
            mode = .live
            snapshot = .unavailable
            latestFix = nil
            lastCoordinate = nil
            lastMapCoordinate = nil
            nearbyRoads = []; nearbyHazards = []
            currentTrip = settings.recordTrips ? Trip() : nil
            lastCheckpoint = Date()
            updateIdleTimer()
            location.start(background: settings.backgroundLocation)
            if !hasRealData { notice = "GPS vẫn hoạt động. Chưa có dữ liệu giao thông thực: không hiển thị giới hạn tốc độ hoặc camera giả." }
        } catch { errorMessage = error.localizedDescription }
    }

    func startDemo() async {
        guard mode == .idle, !isBusy, isReady, !showOnboarding else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            let data = try await traffic.demo()
            let prepared = try await traffic.prepareEngine(dataset: data, configuration: settings.engineConfiguration)
            location.stop()
            navigation.stop()
            navigation.clearPreview()
            demoDataset = data
            engine = prepared
            demoDriver = DemoDriver(dataset: data)
            mode = .demo
            snapshot = .unavailable
            latestFix = nil
            lastMapCoordinate = nil
            nearbyRoads = []; nearbyHazards = []
            currentTrip = settings.recordTrips ? Trip(isDemo: true) : nil
            lastTick = Date(); lastCheckpoint = Date()
            updateIdleTimer()
            tick()
        } catch { errorMessage = error.localizedDescription }
    }

    func stopDriving() {
        guard isDriving else { return }
        location.stop()
        speech.stop()
        navigation.stop()
        if mode == .demo { lastCoordinate = nil; nearbyRoads = []; nearbyHazards = [] }
        mode = .idle
        demoDriver = nil
        latestFix = nil
        snapshot = engine.invalidate().snapshot
        showHUD = false
        updateIdleTimer()
        if var trip = currentTrip, !trip.points.isEmpty {
            trip.finish(at: Date())
            Task {
                do { try await tripStore.finish(trip); trips = try await tripStore.list() }
                catch { storageWarning = "Không lưu được hành trình. Bản lưu tự động được giữ lại: \(error.localizedDescription)" }
            }
        }
        currentTrip = nil
    }

    func importFile(_ url: URL) async {
        guard canManageData else { return }
        isBusy = true
        defer { isBusy = false }
        do { importedDataset = try await traffic.importFile(url); importNotice() }
        catch { errorMessage = error.localizedDescription }
    }

    func importRemote(url: String, checksum: String) async {
        guard canManageData else { return }
        isBusy = true
        defer { isBusy = false }
        do { importedDataset = try await traffic.importRemote(urlText: url, expectedSHA256: checksum); importNotice() }
        catch is CancellationError { notice = "Đã hủy tải dữ liệu. Bộ dữ liệu trước đó không thay đổi." }
        catch { errorMessage = error.localizedDescription }
    }

    private func importNotice() {
        notice = importedDataset?.isDemo == true
            ? "Đã nhập tệp mô phỏng. Tệp này KHÔNG được sử dụng khi lái xe thật."
            : "Đã kiểm tra và nhập dữ liệu. Hãy kiểm tra giấy phép, nguồn và độ cập nhật trước khi sử dụng."
    }

    func removeDataset() async {
        guard canManageData else { return }
        isBusy = true
        defer { isBusy = false }
        do { try await traffic.remove(); importedDataset = nil; notice = "Đã xóa dữ liệu giao thông đã nhập." }
        catch { errorMessage = error.localizedDescription }
    }

    func deleteTrip(_ id: UUID) async {
        guard canManageData else { return }
        do { try await tripStore.remove(id); trips = try await tripStore.list() }
        catch { errorMessage = error.localizedDescription }
    }

    func deleteAllTrips() async {
        guard canManageData else { return }
        isBusy = true
        defer { isBusy = false }
        do { try await tripStore.deleteAll(); trips = []; notice = "Đã xóa nhật ký hành trình trên thiết bị." }
        catch { errorMessage = error.localizedDescription }
    }

    func loadTrip(_ id: UUID) async throws -> Trip { try await tripStore.load(id) }
    func exportTrip(_ id: UUID, gpx: Bool) async throws -> URL { try await tripStore.export(id, gpx: gpx) }

    func sceneChanged(isActive: Bool) {
        isForeground = isActive
        updateIdleTimer()
        guard isDriving else { return }
        if !isActive {
            checkpoint()
            if mode == .demo || !settings.backgroundLocation {
                speech.stop()
                if mode == .live { location.stop() }
                latestFix = nil
                snapshot = engine.invalidate().snapshot
                navigation.invalidateProgress()
            }
        } else if mode == .live {
            location.start(background: settings.backgroundLocation)
        }
    }

    func openSystemSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
    }

    private func receive(_ fix: LocationFix) {
        guard isDriving else { return }
        let now = Date()
        if let latestFix, fix.timestamp <= latestFix.timestamp { return }
        let wasOverspeed = snapshot.isOverspeed
        let update = engine.process(fix, now: now)
        snapshot = update.snapshot
        guard fix.isUsable(at: now) else {
            latestFix = nil
            navigation.invalidateProgress()
            speech.stop()
            return
        }
        latestFix = fix
        lastCoordinate = fix.coordinate
        if lastMapCoordinate.map({ $0.distance(to: fix.coordinate) >= 30 }) ?? true {
            let features = engine.mapFeatures(near: fix.coordinate)
            nearbyRoads = features.roads; nearbyHazards = features.hazards
            lastMapCoordinate = fix.coordinate
        }
        if currentTrip != nil { currentTrip?.append(fix, speedLimit: snapshot.speedLimit, now: now) }
        var messages = update.announcements
        if mode == .live, let message = navigation.update(fix, now: now) { messages.append(message) }
        speech.enqueue(messages)
        if settings.hapticsEnabled, snapshot.isOverspeed, !wasOverspeed, isForeground {
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        }
    }

    private func tick() {
        let now = Date()
        defer { lastTick = now }
        if mode == .demo, isForeground, let fix = demoDriver?.next(at: now, delta: now.timeIntervalSince(lastTick)) { receive(fix) }
        if mode == .live, let fix = latestFix, !fix.isUsable(at: now) {
            latestFix = nil
            snapshot = engine.invalidate().snapshot
            navigation.invalidateProgress()
            speech.stop()
        }
        if isDriving, now.timeIntervalSince(lastCheckpoint) >= 15 { checkpoint() }
    }

    private func checkpoint() {
        lastCheckpoint = Date()
        guard let trip = currentTrip, !trip.points.isEmpty else { return }
        Task {
            do { try await tripStore.checkpoint(trip) }
            catch { storageWarning = "Không lưu tự động được. Hãy kiểm tra dung lượng thiết bị: \(error.localizedDescription)" }
        }
    }

    private func updateIdleTimer() {
        UIApplication.shared.isIdleTimerDisabled = isForeground && isDriving && settings.keepScreenAwake
    }
}
