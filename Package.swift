// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "RtcKitSdkCall",
    platforms: [
        .iOS(.v12),
        .macOS(.v13)
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "RtcKitSdkCall",
            targets: ["RtcKitSdkCall"]),
    ],
    dependencies: [
        .package(url: "https://github.com/socketio/socket.io-client-swift", .upToNextMinor(from: "16.1.1")),
        .package(url: "https://github.com/stasel/WebRTC.git", branch: "latest"),
        .package(url: "https://github.com/daltoniam/Starscream.git", exact: "4.0.8"),
        .package(url: "https://github.com/krzyzanowskim/CryptoSwift.git", exact: "1.8.4")
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "RtcKitSdkCall",
            dependencies: [
                .product(name: "SocketIO", package: "socket.io-client-swift"),
                .product(name: "WebRTC", package: "WebRTC"),
                .product(name: "Starscream", package: "Starscream"),
                .product(name: "CryptoSwift", package: "CryptoSwift")
            ],
            resources: [
                .process("Media.xcassets")
            ]
        ),
        .testTarget(
            name: "RtcKitSdkCallTests",
            dependencies: [
                "RtcKitSdkCall",
                .product(name: "SocketIO", package: "socket.io-client-swift")
            ]
        ),
    ]
)
