// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PortalDemo",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "PortalDemo",
            path: "Sources/PortalDemo"
        )
    ]
)
