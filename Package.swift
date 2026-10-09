// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "FreeBudsManager",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "FreeBudsManager", targets: ["FreeBudsManager"]),
        .library(name: "FreeBudsKit", targets: ["FreeBudsKit"]),
    ],
    targets: [
        .target(name: "FreeBudsKit"),
        .target(name: "FreeBudsUI", dependencies: ["FreeBudsKit"]),
        .executableTarget(name: "FreeBudsManager", dependencies: ["FreeBudsKit", "FreeBudsUI"]),
        /// Developer tool: renders the screens to PNG with sample data (`scripts/preview.sh`).
        .executableTarget(name: "FreeBudsPreview", dependencies: ["FreeBudsKit", "FreeBudsUI"]),
        .testTarget(name: "FreeBudsKitTests", dependencies: ["FreeBudsKit"]),
    ]
)
