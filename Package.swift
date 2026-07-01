// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "AgentBar",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "AgentBar", targets: ["AgentBar"])
    ],
    targets: [
        .executableTarget(
            name: "AgentBar",
            path: "Sources/AgentBar",
            resources: [
                .copy("Resources/AgentBarLogo.png"),
                .copy("Resources/AgentBarMenuIcon.png"),
                .copy("Resources/AgentBarIcon.icns"),
                .copy("Resources/Fonts")
            ]
        ),
        .testTarget(
            name: "AgentBarTests",
            dependencies: ["AgentBar"],
            path: "Tests/AgentBarTests"
        )
    ]
)
