// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SwitcherKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "SwitcherKit", targets: ["SwitcherKit"])],
    targets: [
        .target(name: "SwitcherKit"),
        .testTarget(name: "SwitcherKitTests", dependencies: ["SwitcherKit"]),
    ]
)
