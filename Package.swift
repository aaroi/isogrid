// swift-tools-version: 6.2
import PackageDescription

let approachable: [SwiftSetting] = [
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
]

let package = Package(
    name: "Isogrid",
    platforms: [.macOS(.v15)],
    targets: [
        .target(name: "IsogridCore", swiftSettings: approachable),
        .executableTarget(
            name: "Isogrid",
            dependencies: ["IsogridCore"],
            swiftSettings: approachable + [.defaultIsolation(MainActor.self)]
        ),
        .executableTarget(name: "IsogridFixture", swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(name: "isogrid-e2e", dependencies: ["IsogridCore"], swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "IsogridCoreTests", dependencies: ["IsogridCore"], swiftSettings: approachable),
    ]
)
