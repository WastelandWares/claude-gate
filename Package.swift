// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "claude-gate",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/LebJe/TOMLKit.git", from: "0.6.0"),
    ],
    targets: [
        .target(
            name: "ClaudeGateCore",
            dependencies: ["TOMLKit"]
        ),
        .executableTarget(
            name: "claude-gate",
            dependencies: ["ClaudeGateCore", "TOMLKit"],
            linkerSettings: [
                .linkedFramework("LocalAuthentication"),
                .linkedFramework("AppKit"),
                .linkedFramework("UserNotifications"),
            ]
        ),
        .testTarget(
            name: "ClaudeGateCoreTests",
            dependencies: ["ClaudeGateCore"],
            resources: [
                .copy("Fixtures"),
            ]
        ),
    ]
)
