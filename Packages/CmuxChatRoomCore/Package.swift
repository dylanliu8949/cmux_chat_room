// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CmuxChatRoomCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CmuxChatRoomCore", targets: ["CmuxChatRoomCore"]),
    ],
    targets: [
        .target(
            name: "CmuxChatRoomCore",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("ExistentialAny"),
                .enableUpcomingFeature("InternalImportsByDefault"),
            ]
        ),
        .testTarget(
            name: "CmuxChatRoomCoreTests",
            dependencies: ["CmuxChatRoomCore"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("ExistentialAny"),
                .enableUpcomingFeature("InternalImportsByDefault"),
            ]
        ),
    ]
)
