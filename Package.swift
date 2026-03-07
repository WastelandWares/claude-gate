// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "claude-gate",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/LebJe/TOMLKit.git", from: "0.6.0"),
    ],
    targets: [
        .executableTarget(
            name: "claude-gate",
            dependencies: ["TOMLKit"],
            linkerSettings: [
                .linkedFramework("LocalAuthentication"),
                .linkedFramework("AppKit"),
            ]
        ),
    ]
)
