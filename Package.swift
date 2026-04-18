// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Logleaf",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.24.0"),
    ],
    targets: [
        .target(
            name: "LogleafLib",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            path: "Sources/LogleafLib"
        ),
        .executableTarget(
            name: "Logleaf",
            dependencies: [
                "LogleafLib",
            ],
            path: "Sources/Logleaf",
            resources: [
                .copy("Resources/AppIcon.icns"),
                .copy("Resources/AppIcon.png"),
            ]
        ),
        .testTarget(
            name: "LogleafTests",
            dependencies: [
                "LogleafLib",
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            path: "Tests/LogleafTests"
        ),
    ]
)
