// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "RoboYard",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "RoboYard", targets: ["RoboYard"]),
    ],
    targets: [
        .executableTarget(name: "RoboYard"),
        .testTarget(name: "RoboYardTests", dependencies: ["RoboYard"]),
    ]
)
