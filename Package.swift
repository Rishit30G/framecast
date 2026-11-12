// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Framecast",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Framecast",
            path: "Sources/Framecast",
            swiftSettings: [.unsafeFlags(["-swift-version", "5"])]
        )
    ]
)
