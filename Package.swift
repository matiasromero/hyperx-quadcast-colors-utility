// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "HyperXRGB",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "HyperXProtocol", targets: ["HyperXProtocol"]),
        .library(name: "HyperXCore", targets: ["HyperXCore"]),
        .executable(name: "HyperXRGB", targets: ["HyperXRGB"]),
    ],
    targets: [
        .target(name: "HyperXProtocol"),
        .target(
            name: "HyperXCore",
            dependencies: ["HyperXProtocol"]
        ),
        .executableTarget(
            name: "HyperXRGB",
            dependencies: ["HyperXCore", "HyperXProtocol"]
        ),
        .executableTarget(
            name: "ValidateProtocol",
            dependencies: ["HyperXProtocol"]
        ),
        .executableTarget(
            name: "HIDProbe",
            dependencies: ["HyperXCore", "HyperXProtocol"]
        ),
        .testTarget(
            name: "HyperXProtocolTests",
            dependencies: ["HyperXProtocol"]
        ),
    ]
)
