// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TopShelf",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "TopShelf", targets: ["TopShelf"])
    ],
    targets: [
        .executableTarget(
            name: "TopShelf",
            path: "Sources/TopShelf",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
