// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Perry",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "PerryCore"),
        .executableTarget(name: "Perry", dependencies: ["PerryCore"]),
        .executableTarget(name: "PerryCheck", dependencies: ["PerryCore"]),
    ]
)
