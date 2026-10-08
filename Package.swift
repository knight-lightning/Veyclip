// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ShareXMac",
    platforms: [.macOS("26.0")],
    products: [.executable(name: "ShareXMac", targets: ["ShareXMac"])],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", exact: "3.1.0")
    ],
    targets: [
        .target(name: "CaptureCore"),
        .executableTarget(name: "ShareXMac", dependencies: [
            "CaptureCore", .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts")
        ]),
        .testTarget(name: "CaptureCoreTests", dependencies: ["CaptureCore"]),
        .testTarget(name: "ShareXMacTests", dependencies: ["ShareXMac", "CaptureCore"])
    ],
    swiftLanguageModes: [.v5]
)
