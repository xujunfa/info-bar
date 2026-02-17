// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "InfoBar",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "InfoBar", targets: ["InfoBar"]),
        .executable(name: "InfoBarApp", targets: ["InfoBarApp"])
    ],
    targets: [
        .target(
            name: "InfoBar",
            resources: [
                .copy("Modules/Quota/config.plist"),
                .copy("Resources")
            ]
        ),
        .executableTarget(
            name: "InfoBarApp",
            dependencies: ["InfoBar"]
        ),
        .testTarget(name: "InfoBarTests", dependencies: ["InfoBar"])
    ]
)
