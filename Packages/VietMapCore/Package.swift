// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VietMapCore",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [.library(name: "VietMapCore", targets: ["VietMapCore"])],
    targets: [
        .target(name: "VietMapCore"),
        .testTarget(name: "VietMapCoreTests", dependencies: ["VietMapCore"])
    ]
)
