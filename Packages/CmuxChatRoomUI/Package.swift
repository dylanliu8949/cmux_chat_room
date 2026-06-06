// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CmuxChatRoomUI",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CmuxChatRoomUI", targets: ["CmuxChatRoomUI"]),
    ],
    dependencies: [
        .package(path: "../CmuxChatRoomCore"),
        .package(path: "../CmuxChatRoom"),
    ],
    targets: [
        .target(
            name: "CmuxChatRoomUI",
            dependencies: [
                .product(name: "CmuxChatRoomCore", package: "CmuxChatRoomCore"),
                .product(name: "CmuxChatRoom", package: "CmuxChatRoom"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("ExistentialAny"),
                .enableUpcomingFeature("InternalImportsByDefault"),
            ]
        ),
    ]
)
