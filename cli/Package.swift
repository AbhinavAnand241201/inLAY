// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "inlay",
    platforms: [.macOS(.v12)],
    products: [
        .executable(name: "inlay", targets: ["inlay"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/apple/swift-argument-parser.git",
            from: "1.3.0"),
    ],
    targets: [
        .executableTarget(
            name: "inlay",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            resources: [
                // The generated registry, bundled into the binary so `inlay`
                // works offline. Refreshed by `scripts/sync-registry.sh`.
                .copy("Resources/registry.json"),
            ]),
    ]
)
