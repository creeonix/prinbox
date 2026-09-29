// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Prinbox",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "PrinboxCore"),
        .testTarget(name: "PrinboxCoreTests", dependencies: ["PrinboxCore"]),
    ]
)
