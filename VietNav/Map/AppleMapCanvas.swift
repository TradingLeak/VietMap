import SwiftUI
import MapKit

/// MapKit is only a display provider, not a routing service.
struct AppleMapCanvas: UIViewRepresentable {
    @ObservedObject var model: MapModel
    func makeCoordinator() -> Coordinator { Coordinator(model: model) }
    func makeUIView(context: Context) -> MKMapView {
        let view = MKMapView(frame: .zero)
        view.delegate = context.coordinator
        view.showsCompass = true
        view.showsScale = true
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.userPan(_:)))
        pan.delegate = context.coordinator
        view.addGestureRecognizer(pan)
        let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.userPan(_:)))
        pinch.delegate = context.coordinator
        view.addGestureRecognizer(pinch)
        return view
    }
    func updateUIView(_ view: MKMapView, context: Context) {
        let c = context.coordinator
        c.model = model
        let center = model.followsLocation ? (model.location?.coordinate ?? model.mapCenter) : model.mapCenter
        // Approximate MapLibre's zoom using meters per screen width at the current latitude.
        let latitudeFactor = max(0.1, cos(center.latitude * .pi / 180))
        let span = max(100, 40_075_016.0 * latitudeFactor / pow(2, model.zoom) * 1.5)
        let changed = c.lastZoom != model.zoom || c.lastPitch != model.pitch || c.lastHeading != (model.followsLocation ? model.heading : 0) || c.lastLat != center.latitude || c.lastLon != center.longitude
        if changed && !c.gesturing {
            c.lastZoom = model.zoom; c.lastPitch = model.pitch
            c.lastHeading = model.followsLocation ? model.heading : 0
            c.lastLat = center.latitude; c.lastLon = center.longitude
            let camera = MKMapCamera(lookingAtCenter: center, fromDistance: span, pitch: model.pitch, heading: model.followsLocation ? model.heading : 0)
            view.setCamera(camera, animated: false)
        }
        if let location = model.location {
            if let marker = c.marker { marker.coordinate = location.coordinate }
            else { let marker = MKPointAnnotation(); marker.coordinate = location.coordinate; marker.title = "Vị trí của bạn"; c.marker = marker; view.addAnnotation(marker) }
        } else if let marker = c.marker { view.removeAnnotation(marker); c.marker = nil }
    }
    static func dismantleUIView(_ view: MKMapView, coordinator: Coordinator) { view.delegate = nil }

    @MainActor final class Coordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {
        var model: MapModel
        var marker: MKPointAnnotation?
        var lastZoom: Double?; var lastPitch: CGFloat?; var lastHeading: Double?
        var lastLat: Double?; var lastLon: Double?
        private var gestures = Set<ObjectIdentifier>()
        var gesturing: Bool { !gestures.isEmpty }
        init(model: MapModel) { self.model = model }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }
        @objc func userPan(_ gesture: UIGestureRecognizer) {
            guard let view = gesture.view as? MKMapView else { return }
            let id = ObjectIdentifier(gesture)
            if gesture.state == .began { gestures.insert(id); model.followsLocation = false }
            if gesture.state == .ended || gesture.state == .cancelled || gesture.state == .failed {
                gestures.remove(id)
                guard gestures.isEmpty else { return }
                let center = view.centerCoordinate
                let factor = max(0.1, cos(center.latitude * .pi / 180))
                let zoom = min(19, max(3, log2(40_075_016.0 * factor * 1.5 / max(100, view.camera.centerCoordinateDistance))))
                lastLat = center.latitude; lastLon = center.longitude; lastZoom = zoom
                model.mapCenter = center; model.zoom = zoom
            }
        }
    }
}
