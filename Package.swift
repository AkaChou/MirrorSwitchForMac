// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "MirrorSwitch",
    platforms: [
        .macOS(.v13)  // MenuBarExtra 需要 macOS 13+
    ],
    products: [
        .executable(
            name: "MirrorSwitch",
            targets: ["MirrorSwitch"]
        ),
    ],
    dependencies: [
        // 不需要外部依赖，使用系统框架即可
    ],
    targets: [
        .executableTarget(
            name: "MirrorSwitch",
            dependencies: []
        ),
    ]
)
