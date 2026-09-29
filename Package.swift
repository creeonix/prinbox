// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Prinbox",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Prinbox", targets: ["Prinbox"])
    ],
    targets: [
        .target(name: "PrinboxCore"),
        .executableTarget(name: "Prinbox", dependencies: ["PrinboxCore"]),
        .testTarget(name: "PrinboxCoreTests", dependencies: ["PrinboxCore"], exclude: ["Fixtures"]),
    ]
)
