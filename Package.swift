// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Blindspot",
    // Keep in step with min_macos in build.sh.
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "Blindspot"),
        .testTarget(name: "BlindspotTests", dependencies: ["Blindspot"]),
    ]
)
