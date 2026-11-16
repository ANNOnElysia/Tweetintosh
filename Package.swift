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
            ],
            linkerSettings: [
                // AppKit chooses a control's design from the SDK recorded in the binary, and SwiftPM writes the
                // deployment target (15.0) there instead, which leaves Xcode builds with Sequoia's switches and
                // sliders: no Liquid Glass even on macOS 26. Marking the link as macOS 26 keeps minos at 15.0, so
                // the app still runs on macOS 15, but lets the system draw its controls in the current style.
                .unsafeFlags([
                    "-Xlinker", "-platform_version",
                    "-Xlinker", "macos",
                    "-Xlinker", "15.0",
                    "-Xlinker", "26.0"
                ])
            ]
        )
    ]
)
