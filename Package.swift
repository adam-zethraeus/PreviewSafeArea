// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "PreviewSafeArea",
    platforms: [.iOS(.v17), .macOS(.v14), .watchOS(.v10)],
    products: [
        .library(
            name: "PreviewSafeArea",
            targets: ["PreviewSafeArea"]
        ),
    ],
    targets: [
        .target(
            name: "PreviewSafeArea"
        ),
    ]
)
