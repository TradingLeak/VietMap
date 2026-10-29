import Foundation
import UIKit
import MapLibre

/// Các layer thuộc style nên phải dựng lại sau khi đổi sáng/tối.
final class RouteMapRenderer {
    private let sourceID = "vietnav-route"
    private let casingID = "vietnav-route-casing"
    private let lineID = "vietnav-route-line"
    private let arrowID = "vietnav-route-arrows"
    private let imageID = "vietnav-route-arrow"
    private var displayedID: UUID?

    func styleDidChange() { displayedID = nil }

    func render(_ route: Route?, style: MLNStyle) {
        if let route, displayedID == route.id, style.source(withIdentifier: sourceID) != nil { return }
        if route == nil, displayedID == nil, style.source(withIdentifier: sourceID) == nil { return }
        for id in [arrowID, lineID, casingID] {
            if let layer = style.layer(withIdentifier: id) { style.removeLayer(layer) }
        }
        if let source = style.source(withIdentifier: sourceID) { style.removeSource(source) }
        displayedID = nil
        guard let route, route.geometry.count >= 2 else { return }
        let object: [String: Any] = ["type": "Feature", "properties": [:], "geometry": ["type": "LineString", "coordinates": route.geometry.map { [$0.longitude, $0.latitude] }]]
        guard let data = try? JSONSerialization.data(withJSONObject: object),
              let shape = try? MLNShape(data: data, encoding: String.Encoding.utf8.rawValue) else { return }
        let source = MLNShapeSource(identifier: sourceID, shape: shape, options: nil)
        style.addSource(source)
        let casing = MLNLineStyleLayer(identifier: casingID, source: source)
        casing.lineColor = NSExpression(forConstantValue: UIColor(red: 0.04, green: 0.23, blue: 0.42, alpha: 1))
        casing.lineWidth = NSExpression(forConstantValue: 10)
        style.addLayer(casing)
        let line = MLNLineStyleLayer(identifier: lineID, source: source)
        line.lineColor = NSExpression(forConstantValue: UIColor(red: 30 / 255.0, green: 136 / 255.0, blue: 229 / 255.0, alpha: 1))
        line.lineWidth = NSExpression(forConstantValue: 8)
        style.addLayer(line)
        style.setImage(arrowImage(), forName: imageID)
        let arrows = MLNSymbolStyleLayer(identifier: arrowID, source: source)
        arrows.iconImageName = NSExpression(forConstantValue: imageID)
        arrows.symbolPlacement = NSExpression(forConstantValue: "line")
        arrows.symbolSpacing = NSExpression(forConstantValue: 80)
        arrows.iconAllowsOverlap = NSExpression(forConstantValue: true)
        style.addLayer(arrows)
        displayedID = route.id
    }

    private func arrowImage() -> UIImage {
        // Mũi tên trỏ sang phải; symbol-placement=line xoay biểu tượng theo chiều geometry.
        UIGraphicsImageRenderer(size: CGSize(width: 16, height: 16)).image { context in
            let path = UIBezierPath()
            path.move(to: CGPoint(x: 4, y: 3)); path.addLine(to: CGPoint(x: 12, y: 8))
            path.addLine(to: CGPoint(x: 4, y: 13)); path.lineWidth = 2.5
            path.lineCapStyle = .round; path.lineJoinStyle = .round
            UIColor.white.setStroke(); path.stroke()
        }
    }
}
