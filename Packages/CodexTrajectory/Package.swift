// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CodexTrajectory",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
    ],
    products: [
        .library(
            name: "CodexTrajectory",
            targets: ["CodexTrajectory"]
        ),
    ],
    targets: [
        .target(
            name: "CodexTrajectory"
        ),
        .testTarget(
            name: "CodexTrajectoryTests",
            dependencies: ["CodexTrajectory"]
        ),
    ]
)
