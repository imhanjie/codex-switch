// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CodexSwitchCore",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(
            name: "CodexSwitchCore",
            targets: ["CodexSwitchCore"]
        ),
        .library(
            name: "CodexSwitchMenuBar",
            targets: ["CodexSwitchMenuBar"]
        ),
    ],
    targets: [
        .target(
            name: "CodexSwitchCore",
            path: "codex-switch/Core"
        ),
        .target(
            name: "CodexSwitchMenuBar",
            dependencies: ["CodexSwitchCore"],
            path: "codex-switch/UI",
            exclude: ["MenuBarPanelView.swift"],
            sources: ["MenuBarViewModel.swift"]
        ),
        .testTarget(
            name: "CodexSwitchCoreTests",
            dependencies: ["CodexSwitchCore"],
            path: "Tests/CodexSwitchCoreTests"
        ),
        .testTarget(
            name: "CodexSwitchMenuBarTests",
            dependencies: ["CodexSwitchMenuBar", "CodexSwitchCore"],
            path: "Tests/CodexSwitchMenuBarTests"
        ),
    ]
)
