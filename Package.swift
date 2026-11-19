// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Seasons",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Seasons", targets: ["Seasons"]),
        .library(name: "SeasonsCore", targets: ["SeasonsCore"]),
    ],
    targets: [
        // Platform-independent simulation (no AppKit, no Metal). Portable to Windows/Linux.
        .target(name: "SeasonsCore"),
        // macOS app: menu bar, overlay windows, Metal renderer, window/Dock detection.
        // Localizations live in Resources/ and are copied into the .app by build.sh,
        // so the plain `swift build` binary falls back to the English keys.
        .executableTarget(
            name: "Seasons",
            dependencies: ["SeasonsCore"],
            exclude: ["Resources"]
        ),
        .testTarget(name: "SeasonsCoreTests", dependencies: ["SeasonsCore"]),
    ]
)
