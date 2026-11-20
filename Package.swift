// swift-tools-version:5.9
// SPDX-License-Identifier: GPL-3.0-or-later

import PackageDescription

let package = Package(
    name: "Slopdown",
    platforms: [.macOS(.v14)],
    targets: [
        // Markdown / Obsidian parsing and link resolution. Foundation only,
        // so it builds and tests on Linux as well as macOS.
        .target(
            name: "SlopdownCore",
            path: "Sources/SlopdownCore"
        ),
        // The AppKit application.
        .executableTarget(
            name: "Slopdown",
            dependencies: ["SlopdownCore"],
            path: "Sources/Slopdown"
        ),
        .testTarget(
            name: "SlopdownCoreTests",
            dependencies: ["SlopdownCore"],
            path: "Tests/SlopdownCoreTests"
        ),
    ]
)
