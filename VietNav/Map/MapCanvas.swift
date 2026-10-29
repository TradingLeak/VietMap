import SwiftUI
import MapLibre
import CoreLocation

struct MapCanvas: UIViewRepresentable {
    @ObservedObject var model: MapModel
    func makeCoordinator() -> Coordinator { Coordinator(model: model) }
    func makeUIView(context: Context) -> MLNMapView {
        let map = MLNMapView(frame: .zero, styleURL: Bundle.main.url(forResource: "osm", withExtension: "json"))
        map.delegate = context.coordinator
        map.setCenter(CLLocationCoordinate2D(latitude: 21.0285, longitude: 105.8542), zoomLevel: model.zoom, animated: false)
        map.logoView.isHidden = true
        map.attributionButtonPosition = .bottomLeft
        map.attributionButtonMargins = CGPoint(x: 8, y: 160)
        for gesture in map.gestureRecognizers ?? [] where gesture is UIPanGestureRecognizer || gesture is UIPinchGestureRecognizer || gesture is UIRotationGestureRecognizer {
            gesture.addTarget(context.coordinator, action: #selector(Coordinator.gesture(_:)))
        }
        return map
    }
    func updateUIView(_ map: MLNMapView, context: Context) {
        let coordinator = context.coordinator
        coordinator.model = model
        if let location = model.location {
            if let annotation = coordinator.user { annotation.coordinate = location.coordinate }
            else {
                let annotation = UserMarker()
                annotation.coordinate = location.coordinate
                annotation.title = "Vị trí của bạn"
                coordinator.user = annotation
                map.addAnnotation(annotation)
            }
        } else if let annotation = coordinator.user {
            map.removeAnnotation(annotation); coordinator.user = nil
        }
        guard !coordinator.gesturing else { return }
        if model.followsLocation, let position = model.location?.coordinate {
            map.setCenter(position, zoomLevel: model.zoom, animated: false)
        } else if abs(map.zoomLevel - model.zoom) > 0.01 { map.setZoomLevel(model.zoom, animated: false) }
        let camera = map.camera
        camera.pitch = model.pitch
        if model.followsLocation { camera.heading = model.heading }
        map.camera = camera
    }
    static func dismantleUIView(_ view: MLNMapView, coordinator: Coordinator) {
        for gesture in view.gestureRecognizers ?? [] { gesture.removeTarget(coordinator, action: #selector(Coordinator.gesture(_:))) }
        view.delegate = nil
    }
    @MainActor final class Coordinator: NSObject, MLNMapViewDelegate {
        var model: MapModel
        var user: UserMarker?
        private var gestures = Set<ObjectIdentifier>()
        var gesturing: Bool { !gestures.isEmpty }
        init(model: MapModel) { self.model = model }
        @objc func gesture(_ gesture: UIGestureRecognizer) {
            let id = ObjectIdentifier(gesture)
            switch gesture.state {
            case .began: gestures.insert(id); model.followsLocation = false
            case .ended, .cancelled, .failed:
                gestures.remove(id)
                if gestures.isEmpty, let map = gesture.view as? MLNMapView { model.zoom = map.zoomLevel }
            default: break
            }
        }
        func mapView(_ mapView: MLNMapView, imageFor annotation: MLNAnnotation) -> MLNAnnotationImage? {
            guard annotation is UserMarker else { return nil }
            let id = "user-location"
            if let existing = mapView.dequeueReusableAnnotationImage(withIdentifier: id) { return existing }
            let image = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 40)).image { context in
                let path = UIBezierPath(); path.move(to: CGPoint(x: 20, y: 3)); path.addLine(to: CGPoint(x: 36, y: 34)); path.addLine(to: CGPoint(x: 20, y: 29)); path.addLine(to: CGPoint(x: 4, y: 34)); path.close()
                UIColor.systemBlue.setFill(); path.fill(); UIColor.white.setStroke(); path.lineWidth = 3; path.stroke()
            }
            return MLNAnnotationImage(image: image, reuseIdentifier: id)
        }
    }
}
private final class UserMarker: MLNPointAnnotation {}
