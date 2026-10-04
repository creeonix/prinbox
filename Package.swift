// swift-tools-version:6.0
import PackageDescription

// The app target exists only on macOS, so a Linux build (CI, the roadmap's 1.0 port) sees the library, the
// command and the tests. The command target arrives in a later step of this release.
var products: [Product] = []
var targets: [Target] = [
    .target(name: "PrinboxCore"),
    .testTarget(name: "PrinboxCoreTests", dependencies: ["PrinboxCore"], exclude: ["Fixtures"]),
]
#if os(macOS)
    products.append(.executable(name: "PrinboxApp", targets: ["PrinboxApp"]))
    targets.append(.executableTarget(name: "PrinboxApp", dependencies: ["PrinboxCore"]))
#endif

let package = Package(
    name: "Prinbox",
    platforms: [.macOS(.v14)],
    products: products,
    targets: targets
)
