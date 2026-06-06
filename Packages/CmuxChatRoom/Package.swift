// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CmuxChatRoom",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CmuxChatRoom", targets: ["CmuxChatRoom"]),
    ],
    dependencies: [
        .package(path: "../CmuxChatRoomCore"),
    ],
    targets: [
        .target(
            name: "CmuxChatRoom",
            dependencies: [.product(name: "CmuxChatRoomCore", package: "CmuxChatRoomCore")],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("ExistentialAny"),
                .enableUpcomingFeature("InternalImportsByDefault"),
            ]
        ),
        .testTarget(
            name: "CmuxChatRoomTests",
            dependencies: [
                "CmuxChatRoom",
                .product(name: "CmuxChatRoomCore", package: "CmuxChatRoomCore"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("ExistentialAny"),
                .enableUpcomingFeature("InternalImportsByDefault"),
            ]
        ),
    ]
)
