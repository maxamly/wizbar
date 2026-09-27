// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "WizBar",
    platforms: [.macOS(.v15)],
    targets: [.executableTarget(name: "WizBar", path: "Sources")],
    swiftLanguageModes: [.v5]
)
