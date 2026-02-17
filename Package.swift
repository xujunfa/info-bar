// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "InfoBar",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "InfoBar", targets: ["InfoBar"])
    ],
    targets: [
        .target(
            name: "InfoBar",
            resources: [
                .copy("Modules/Quota/config.plist")
            ]
        ),
        .testTarget(name: "InfoBarTests", dependencies: ["InfoBar"])
    ]
)
