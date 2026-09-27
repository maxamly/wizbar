// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "WizBar",
    platforms: [.macOS(.v26)],
    targets: [.executableTarget(name: "WizBar", path: "Sources")],
    swiftLanguageModes: [.v5]
)
