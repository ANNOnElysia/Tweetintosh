// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Tweetintosh",
    platforms: [
        .macOS(.v15)
    ],
    targets: [
        .executableTarget(
            name: "Tweetintosh",
            path: "src",
            exclude: ["custom.css", "inject.js", "Info.plist", "AppIcon.icns"],
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
