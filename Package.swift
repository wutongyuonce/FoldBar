// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FoldBar",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "FoldBar", targets: ["FoldBar"])],
    targets: [
        .target(name: "FoldBarCore"),
        .executableTarget(name: "FoldBar", dependencies: ["FoldBarCore"]),
        .executableTarget(name: "CoreChecks", dependencies: ["FoldBarCore"], path: "Checks")
    ],
    swiftLanguageModes: [.v5]
)
