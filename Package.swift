// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Tweetintosh",
    platforms: [
        .macOS(.v15)
    ],
    dependencies: [
        // Checks GitHub Releases for new versions and installs them (see RELEASING.md)
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.6")
    ],
    targets: [
        .executableTarget(
            name: "Tweetintosh",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "src",
            exclude: ["custom.css", "inject.js", "Info.plist", "AppIcon.icns"],
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
