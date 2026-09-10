// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "AlwaysListen",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "AlwaysListen", targets: ["AlwaysListen"]),
    ],
    targets: [
        .executableTarget(name: "AlwaysListen"),
        .testTarget(name: "AlwaysListenTests", dependencies: ["AlwaysListen"]),
    ]
)
