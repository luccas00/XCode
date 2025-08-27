// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "MyExecutable",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "MyExecutable", targets: ["MyExecutable"])],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.60.0"),
        .package(url: "https://github.com/vapor/postgres-nio.git", from: "1.21.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.5.0") // <-- add
    ],
    targets: [
        .executableTarget(
            name: "MyExecutable",
            dependencies: [
                .product(name: "NIO", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
                .product(name: "PostgresNIO", package: "postgres-nio"),
                .product(name: "Logging", package: "swift-log") // <-- add
            ]
        )
    ]
)
