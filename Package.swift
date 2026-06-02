// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Late",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "Late", targets: ["Late"])
    ],
    targets: [
        .executableTarget(name: "Late")
    ]
)
