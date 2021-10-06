// swift-tools-version:5.3

import PackageDescription

let package = Package(
    name: "Fastream",
    platforms: [
        .iOS(.v9)
    ],
    products: [
        .library(
            name: "Fastream",
            targets: ["Fastream"]),
    ],
    dependencies: [        
    ],
    targets: [
        .target(
            name: "Fastream",
            dependencies: [],
            path: "Sources/ios-sdk"),
        .testTarget(
            name: "FastreamTests",
            dependencies: ["Fastream"],
            path: "Tests/ios-sdk"),
    ]
)
