import SwiftUI
import MapLibre
import CoreLocation

/// Cầu nối SwiftUI và MapLibre; coordinator theo dõi thao tác thủ công.
struct MapViewRepresentable: UIViewRepresentable {
    @ObservedObject var viewModel: MapViewModel
    @ObservedObject private var battery = BatteryOptimizer.shared
    @ObservedObject private var offline = OfflineMapStore.shared
    var route: Route?
    var warnings: [WarningItem]
    var fitRoute: Bool = false
    @Environment(\.colorScheme) private var colorScheme

    init(viewModel: MapViewModel, route: Route? = nil, warnings: [WarningItem] = [], fitRoute: Bool = false) {
        self.viewModel = viewModel; self.route = route; self.warnings = warnings; self.fitRoute = fitRoute
    }

    func makeCoordinator() -> Coordinator { Coordinator(viewModel: viewModel) }

    private var styleURL: URL? {
        if offline.isEnabled, let style = offline.styleURL { return style }
        return Bundle.module.url(forResource: colorScheme == .dark ? "osm_dark_vn" : "osm_bright_vn", withExtension: "json")
    }

    func makeUIView(context: Context) -> MLNMapView {
        let map = MLNMapView(frame: .zero, styleURL: styleURL)
        context.coordinator.map = map
        context.coordinator.styleURL = styleURL
        context.coordinator.route = route
        map.delegate = context.coordinator
        map.setCenter(CLLocationCoordinate2D(latitude: 21.0285, longitude: 105.8542), zoomLevel: viewModel.zoomLevel, animated: false)
        let camera = map.camera
        camera.pitch = battery.reducedRendering ? min(viewModel.pitch, 45) : viewModel.pitch
        map.camera = camera
        // Chỉ ẩn logo MapLibre; nút attribution vẫn hiện và truy cập được.
        map.logoView.isHidden = true
        map.attributionButtonPosition = .bottomLeft
        map.attributionButtonMargins = CGPoint(x: 8, y: 155)
        for gesture in map.gestureRecognizers ?? [] where gesture is UIPanGestureRecognizer || gesture is UIPinchGestureRecognizer || gesture is UIRotationGestureRecognizer {
            gesture.addTarget(context.coordinator, action: #selector(Coordinator.handleGesture(_:)))
        }
        return map
    }

    func updateUIView(_ map: MLNMapView, context: Context) {
        context.coordinator.viewModel = viewModel
        context.coordinator.route = route
        context.coordinator.fitEnabled = fitRoute
        if context.coordinator.styleURL != styleURL, let styleURL {
            context.coordinator.styleURL = styleURL
            map.styleURL = styleURL
        }
        if let style = map.style { context.coordinator.renderer.render(route, style: style) }
        // Chỉ đánh dấu các điểm thực sự có trong database; không tạo biển báo giả.
        context.coordinator.updateWarnings(warnings, on: map)
        // Dùng một nguồn vị trí thống nhất, kể cả tuyến GPX trên simulator.
        if let location = viewModel.currentLocation, viewModel.isActive {
            if context.coordinator.userAnnotation == nil {
                let annotation = MLNPointAnnotation()
                annotation.title = "Vị trí của bạn"
                annotation.coordinate = location.coordinate
                context.coordinator.userAnnotation = annotation
                map.addAnnotation(annotation)
            } else {
                context.coordinator.userAnnotation?.coordinate = location.coordinate
            }
        } else if let annotation = context.coordinator.userAnnotation {
            map.removeAnnotation(annotation)
            context.coordinator.userAnnotation = nil
        }
        // Xem trước toàn tuyến; trong phiên navigation tiếp tục bám vị trí người dùng.
        guard !context.coordinator.isGesturing else { return }
        if !fitRoute { context.coordinator.lastFittedRoute = route?.id }
        if fitRoute, let route, context.coordinator.lastFittedRoute != route.id, map.bounds.height > 100 {
            context.coordinator.lastFittedRoute = route.id
            let b = route.bbox
            let southwest = CLLocationCoordinate2D(latitude: max(-90, b.south - 0.0001), longitude: max(-180, b.west - 0.0001))
            let northeast = CLLocationCoordinate2D(latitude: min(90, b.north + 0.0001), longitude: min(180, b.east + 0.0001))
            let bounds = MLNCoordinateBounds(sw: southwest, ne: northeast)
            let bottom = min(map.bounds.height * 0.35, 250)
            map.setVisibleCoordinateBounds(bounds, edgePadding: UIEdgeInsets(top: 100, left: 40, bottom: bottom, right: 60), animated: false, completionHandler: nil)
            let zoom = map.zoomLevel
            let coordinator = context.coordinator
            DispatchQueue.main.async { [weak coordinator] in
                guard let coordinator, coordinator.fitEnabled, coordinator.route?.id == route.id else { return }
                coordinator.viewModel.stopFollowing()
                coordinator.viewModel.setZoom(zoom)
            }
            return
        }
        let center = viewModel.isFollowingUser ? viewModel.currentLocation?.coordinate : nil
        if let center {
            map.setCenter(center, zoomLevel: viewModel.zoomLevel, animated: false)
        } else if abs(map.zoomLevel - viewModel.zoomLevel) > 0.01 {
            map.setZoomLevel(viewModel.zoomLevel, animated: false)
        }
        let camera = map.camera
        camera.pitch = battery.reducedRendering ? min(viewModel.pitch, 45) : viewModel.pitch
        camera.heading = viewModel.heading
        map.camera = camera
    }

    static func dismantleUIView(_ map: MLNMapView, coordinator: Coordinator) {
        for gesture in map.gestureRecognizers ?? [] {
            gesture.removeTarget(coordinator, action: #selector(Coordinator.handleGesture(_:)))
        }
        map.showsUserLocation = false
        map.delegate = nil
        coordinator.map = nil
    }

    @MainActor
    final class Coordinator: NSObject, MLNMapViewDelegate {
        var viewModel: MapViewModel
        weak var map: MLNMapView?
        var styleURL: URL?
        var userAnnotation: MLNPointAnnotation?
        private var warningAnnotations: [Int64: WarningMapAnnotation] = [:]
        var route: Route?
        var fitEnabled = false
        var lastFittedRoute: UUID?
        let renderer = RouteMapRenderer()

        func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
            renderer.styleDidChange()
            renderer.render(route, style: style)
        }
        func updateWarnings(_ warnings: [WarningItem], on map: MLNMapView) {
            let visible = Array(warnings.prefix(30))
            let ids = Set(visible.map(\.id))
            for id in Array(warningAnnotations.keys) where !ids.contains(id) {
                if let annotation = warningAnnotations.removeValue(forKey: id) { map.removeAnnotation(annotation) }
            }
            for warning in visible where warningAnnotations[warning.id] == nil {
                let annotation = WarningMapAnnotation()
                annotation.coordinate = CLLocationCoordinate2D(latitude: warning.node.latitude, longitude: warning.node.longitude)
                annotation.kind = warning.node.type
                annotation.title = "Điểm cảnh báo OSM (cần kiểm chứng)"
                warningAnnotations[warning.id] = annotation
                map.addAnnotation(annotation)
            }
        }
        func mapView(_ mapView: MLNMapView, imageFor annotation: MLNAnnotation) -> MLNAnnotationImage? {
            guard let warning = annotation as? WarningMapAnnotation else { return nil }
            let id = "vietnav-warning-\(warning.kind.rawValue)"
            if let cached = mapView.dequeueReusableAnnotationImage(withIdentifier: id) { return cached }
            let symbol: String
            switch warning.kind {
            case .speedCamera, .redLightCamera: symbol = "camera.fill"
            case .railwayCrossing: symbol = "tram.fill"
            case .tollBooth: symbol = "creditcard.fill"
            case .noLeftTurn: symbol = "arrow.turn.up.left"
            case .noRightTurn: symbol = "arrow.turn.up.right"
            default: symbol = "exclamationmark.triangle.fill"
            }
            let image = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 40)).image { context in
                UIColor.white.setFill(); context.cgContext.fillEllipse(in: CGRect(x: 2, y: 2, width: 36, height: 36))
                UIColor.systemRed.setStroke(); context.cgContext.setLineWidth(4)
                context.cgContext.strokeEllipse(in: CGRect(x: 3, y: 3, width: 34, height: 34))
                let icon = UIImage(systemName: symbol)?.withTintColor(.black, renderingMode: .alwaysOriginal)
                icon?.draw(in: CGRect(x: 10, y: 10, width: 20, height: 20))
                if warning.kind == .noLeftTurn || warning.kind == .noRightTurn {
                    UIColor.systemRed.setStroke(); context.cgContext.setLineWidth(3)
                    context.cgContext.move(to: CGPoint(x: 7, y: 7)); context.cgContext.addLine(to: CGPoint(x: 33, y: 33)); context.cgContext.strokePath()
                }
            }
            return MLNAnnotationImage(image: image, reuseIdentifier: id)
        }
        private var activeGestures = Set<ObjectIdentifier>()
        var isGesturing: Bool { !activeGestures.isEmpty }

        init(viewModel: MapViewModel) { self.viewModel = viewModel }

        @objc func handleGesture(_ gesture: UIGestureRecognizer) {
            let id = ObjectIdentifier(gesture)
            switch gesture.state {
            case .began:
                activeGestures.insert(id)
                viewModel.stopFollowing()
            case .ended, .cancelled, .failed:
                guard activeGestures.remove(id) != nil, activeGestures.isEmpty, let map else { return }
                // Đồng bộ trạng thái để lần cập nhật SwiftUI tiếp theo không hoàn tác thao tác.
                viewModel.setZoom(map.zoomLevel)
                viewModel.setPitch(map.camera.pitch)
                viewModel.setBearing(map.camera.heading)
            default: break
            }
        }
    }
}

private final class WarningMapAnnotation: MLNPointAnnotation {
    var kind: NodeType = .incident
}
