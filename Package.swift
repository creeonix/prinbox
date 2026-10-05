// swift-tools-version:6.0
import PackageDescription

// The app target exists only on macOS, so a Linux build (CI, the roadmap's 1.0 port) sees the library, the
// command and the tests. The command's product is lowercase on purpose: it is the binary's name, and it must
// differ from the app's product in more than case, since the build volume is case-insensitive.
var products: [Product] = [.executable(name: "prinbox", targets: ["PrinboxCLI"])]
var targets: [Target] = [
    .target(name: "PrinboxCore"),
    .executableTarget(name: "PrinboxCLI", dependencies: ["PrinboxCore"]),
    .testTarget(name: "PrinboxCoreTests", dependencies: ["PrinboxCore"], exclude: ["Fixtures", "Golden"]),
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
