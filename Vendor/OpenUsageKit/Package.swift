// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "OpenUsageKit",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "OpenUsageKit", targets: ["OpenUsageKit"])
    ],
    targets: [
        .target(
            name: "OpenUsageKit",
            path: "Sources/OpenUsage",
            exclude: [
                "App",
                "Views",
                "Services/Telemetry.swift",
                "Stores/TelemetryRecorder.swift",
                "Support/AppNotifications.swift",
                "Support/AppShortcuts.swift",
                "Support/PopoverDismissReader.swift",
                "Support/ShareCardRenderer.swift",
                "Support/TooMuchTransparencyKeyReader.swift"
            ],
            resources: [
                .copy("Resources/ProviderIcons"),
                .process("Resources/zh-Hans.lproj"),
                .copy("Resources/pricing_supplement.json"),
                .copy("Resources/pricing_litellm_snapshot.json"),
                .copy("Resources/pricing_models_dev_snapshot.json")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "OpenUsageKitTests",
            dependencies: ["OpenUsageKit"],
            path: "Tests/OpenUsageKitTests"
        )
    ]
)
