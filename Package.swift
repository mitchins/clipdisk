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
        .target(
            name: "ClipboardFolderUI",
            dependencies: ["ClipboardFolderCore"],
            path: "Sources/ClipboardFolderUI"
        ),
        .executableTarget(
            name: "ClipboardFolder",
            dependencies: ["ClipboardFolderUI"],
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
        .testTarget(
            name: "ClipboardFolderUITests",
            dependencies: ["ClipboardFolderUI"],
            path: "Tests/ClipboardFolderUITests"
        ),
    ]
)
