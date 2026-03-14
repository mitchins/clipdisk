// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "ClipboardFolder",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "ClipboardFolderCore",
            path: "Sources/ClipboardFolderCore"
        ),
        .executableTarget(
            name: "ClipboardFolder",
            dependencies: ["ClipboardFolderCore"],
            path: "Sources/ClipboardFolder"
        ),
        .testTarget(
            name: "ClipboardFolderCoreTests",
            dependencies: ["ClipboardFolderCore"],
            path: "Tests/ClipboardFolderCoreTests"
        ),
        .testTarget(
            name: "ClipboardFolderIntegrationTests",
            dependencies: ["ClipboardFolderCore"],
            path: "Tests/ClipboardFolderIntegrationTests"
        ),
    ]
)
