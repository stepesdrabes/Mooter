// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Mooter",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(
            name: "Mooter",
            swiftSettings: [.defaultIsolation(MainActor.self)]
        )
    ]
)
