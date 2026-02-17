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
    dependencies: [
        .package(url: "https://github.com/steipete/SweetCookieKit", from: "0.4.0")
    ],
    targets: [
        .target(
            name: "InfoBar",
            dependencies: [
                .product(name: "SweetCookieKit", package: "SweetCookieKit")
            ],
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
