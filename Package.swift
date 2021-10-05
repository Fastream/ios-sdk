// swift-tools-version:5.3

import PackageDescription

let package = Package(
    name: "ios-sdk",
    platforms: [
        .iOS(.v9)
    ],
    products: [
        .library(
            name: "ios-sdk",
            targets: ["ios-sdk"]),
    ],
    dependencies: [        
    ],
    targets: [
        .target(
            name: "ios-sdk",
            dependencies: [])        
    ]
)
