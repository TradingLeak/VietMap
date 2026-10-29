// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VietNav",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(name: "VietNavCore", targets: ["VietNavCore"]),
        .library(name: "NavigationActivityShared", targets: ["NavigationActivityShared"]),
        .library(name: "OSMData", targets: ["OSMData"]),
        .executable(name: "OSMDataFetcher", targets: ["OSMDataFetcher"])
    ],
    dependencies: [
        .package(url: "https://github.com/maplibre/maplibre-gl-native-distribution.git", from: "6.0.0"),
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.29.0")
    ],
    targets: [
        .target(name: "NavigationActivityShared", path: "VietNav/ActivityShared"),
        .target(
            name: "VietNavCore",
            dependencies: [
                .product(name: "MapLibre", package: "maplibre-gl-native-distribution"),
                .product(name: "GRDB", package: "GRDB.swift"),
                "OSMData", "NavigationActivityShared"
            ],
            path: "VietNav",
            exclude: ["App", "Tests", "ActivityShared", "ActivityWidget", "Info.plist", "Data/OSM/OverpassAPIClient.swift", "Resources/vietnam_regions.json"],
            sources: ["Core", "Features", "Data"],
            resources: [.process("Resources/MapStyles"), .process("Resources/Assets.xcassets"), .process("Resources/Audio"), .copy("Resources/simulated_route_hanoi.gpx"), .process("Resources/InitialData/schema_v1.sql")]
        ),
        .target(name: "OSMData", path: "VietNav/Data/OSM", sources: ["OverpassAPIClient.swift"]),
        .executableTarget(name: "OSMDataFetcher", dependencies: ["OSMData"], path: "Tools/OSMDataFetcher"),
        .testTarget(name: "OSMDataTests", dependencies: ["OSMData"], path: "OSMDataTests"),
        .testTarget(name: "VietNavCoreTests", dependencies: ["VietNavCore"], path: "VietNav/Tests")
    ]
)
