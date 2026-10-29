import SwiftUI
import MapKit
import VietMapCore

struct MapPreview: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var navigation: NavigationService
    @State private var camera: MapCameraPosition = .region(MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 20.25, longitude: 105.975), latitudinalMeters: 4_000, longitudinalMeters: 4_000))
    var showRoutePreview = false

    var body: some View {
        Group {
            if model.settings.mapDisplay == .offline {
                OfflineMapView()
            } else {
                Map(position: $camera, interactionModes: showRoutePreview ? .all : []) {
                    if model.mode == .live { UserAnnotation() }
                    if model.mode == .demo, let coordinate = model.lastCoordinate {
                        Annotation("Mô phỏng", coordinate: coordinate.clCoordinate) {
                            Image(systemName: "location.north.circle.fill").font(.largeTitle).foregroundStyle(Palette.accent).background(.white, in: Circle())
                        }
                    }
                    if let route = navigation.activeRoute ?? (showRoutePreview ? navigation.routes.first : nil) {
                        MapPolyline(route.polyline).stroke(Palette.accent, style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
                    }
                    ForEach(model.nearbyHazards.prefix(20)) { hazard in
                        Annotation(hazard.title, coordinate: hazard.coordinate.clCoordinate) {
                            Image(systemName: hazard.kind.symbol).font(.caption.bold()).foregroundStyle(.black)
                                .padding(8).background(Palette.amber, in: RoundedRectangle(cornerRadius: 9))
                        }.annotationTitles(.hidden)
                    }
                }
                .mapStyle(model.settings.mapDisplay == .hybrid ? .hybrid(elevation: .flat) : .standard(elevation: .flat))
                .mapControls { MapCompass(); MapScaleView() }
                .overlay(alignment: .bottomTrailing) {
                    Button { recenter() } label: {
                        Image(systemName: "location.fill").font(.headline).frame(width: 44, height: 44).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                    }.accessibilityLabel("Đưa bản đồ về vị trí hiện tại").padding(12)
                }
                .onAppear { recenter() }
                .onChange(of: model.mode) { _, _ in recenter() }
                .onChange(of: model.lastCoordinate) { _, _ in if model.mode == .demo { recenter() } }
                .onChange(of: navigation.destination.map { Coordinate($0.placemark.coordinate) }) { _, _ in fitRoute() }
                .onChange(of: navigation.activeRoute.map { ObjectIdentifier($0) }) { _, _ in fitRoute() }
            }
        }
    }

    private func recenter() {
        if model.mode == .demo, let coordinate = model.lastCoordinate {
            camera = .region(MKCoordinateRegion(center: coordinate.clCoordinate, latitudinalMeters: 1_200, longitudinalMeters: 1_200))
        } else if model.mode == .live {
            camera = .userLocation(followsHeading: true, fallback: .automatic)
        } else { fitRoute() }
    }

    private func fitRoute() {
        if let route = navigation.activeRoute ?? (showRoutePreview ? navigation.routes.first : nil) { camera = .rect(route.polyline.boundingMapRect) }
    }
}

struct OfflineMapView: View {
    @EnvironmentObject private var model: AppModel
    var radius: Double = 600
    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(red: 0.045, green: 0.065, blue: 0.09)))
            for x in stride(from: 0.0, through: size.width, by: 34) {
                var line = Path(); line.move(to: CGPoint(x: x, y: 0)); line.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(line, with: .color(.white.opacity(0.035)), lineWidth: 1)
            }
            for y in stride(from: 0.0, through: size.height, by: 34) {
                var line = Path(); line.move(to: CGPoint(x: 0, y: y)); line.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(line, with: .color(.white.opacity(0.035)), lineWidth: 1)
            }
            guard let centre = model.lastCoordinate else { return }
            for road in model.nearbyRoads {
                var path = Path()
                path.move(to: pixel(road.start, centre: centre, size: size))
                path.addLine(to: pixel(road.end, centre: centre, size: size))
                context.stroke(path, with: .color(.white.opacity(0.10)), style: StrokeStyle(lineWidth: 10, lineCap: .round))
                context.stroke(path, with: .color(.white.opacity(0.45)), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            }
            for hazard in model.nearbyHazards {
                let point = pixel(hazard.coordinate, centre: centre, size: size)
                if CGRect(origin: .zero, size: size).contains(point) {
                    context.fill(Path(ellipseIn: CGRect(x: point.x - 5, y: point.y - 5, width: 10, height: 10)), with: .color(Palette.amber))
                }
            }
            let centrePoint = CGPoint(x: size.width / 2, y: size.height / 2)
            context.fill(Path(ellipseIn: CGRect(x: centrePoint.x - 22, y: centrePoint.y - 22, width: 44, height: 44)), with: .color(Palette.accent.opacity(0.15)))
            var arrow = Path()
            arrow.move(to: CGPoint(x: 0, y: -12)); arrow.addLine(to: CGPoint(x: 9, y: 10))
            arrow.addLine(to: CGPoint(x: 0, y: 5)); arrow.addLine(to: CGPoint(x: -9, y: 10)); arrow.closeSubpath()
            context.translateBy(x: centrePoint.x, y: centrePoint.y)
            context.rotate(by: .degrees(model.latestFix?.validHeading ?? 0))
            context.fill(arrow, with: .color(Palette.accent))
        }
        .overlay(alignment: .topTrailing) { Text("BẮC ↑").font(.system(size: 9, weight: .bold)).foregroundStyle(.white.opacity(0.5)).padding(16) }
        .overlay(alignment: .bottomLeading) {
            VStack(alignment: .leading, spacing: 4) {
                Text(model.lastCoordinate == nil ? "Chờ vị trí để vẽ sơ đồ" : (model.nearbyRoads.isEmpty ? "Không có dữ liệu đường tại đây" : "\(Int(radius)) m · dữ liệu lưu trên máy"))
                Text("Sơ đồ tham khảo, không phải bản đồ dẫn đường")
            }.font(.system(size: 9)).foregroundStyle(.white.opacity(0.65)).padding(14)
        }
        .accessibilityLabel("Sơ đồ đường ngoại tuyến tham khảo")
    }

    private func pixel(_ coordinate: Coordinate, centre: Coordinate, size: CGSize) -> CGPoint {
        let offset = Geo.offset(from: centre, to: coordinate)
        let scale = min(size.width, size.height) / (radius * 2)
        return CGPoint(x: size.width / 2 + offset.east * scale, y: size.height / 2 - offset.north * scale)
    }
}
