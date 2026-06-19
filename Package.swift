// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "WebPageCLI",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .executable(name: "wb", targets: ["WebPageCLI"])
    ],
    targets: [
        .executableTarget(name: "WebPageCLI")
    ]
)
