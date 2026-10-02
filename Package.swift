// swift-tools-version:5.5
import PackageDescription

let package = Package(
    name: "ForceTouchKit",
    platforms: [.macOS(.v11)],
    products: [
        .library(name: "ForceTouchKit", targets: ["ForceTouchKit"]),
        .executable(name: "ForceTouchHarness", targets: ["ForceTouchHarness"]),
    ],
    targets: [
        .target(name: "ForceTouchKit"),
        .executableTarget(name: "ForceTouchHarness", dependencies: ["ForceTouchKit"]),
        .testTarget(name: "ForceTouchKitTests", dependencies: ["ForceTouchKit"]),
    ]
)
