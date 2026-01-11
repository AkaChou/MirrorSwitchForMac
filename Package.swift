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
        // XML 解析库，用于 Maven 等工具的配置文件处理
        .package(url: "https://github.com/tadija/AEXML.git", from: "4.6.1")
    ],
    targets: [
        .executableTarget(
            name: "MirrorSwitch",
            dependencies: [
                .product(name: "AEXML", package: "AEXML")
            ],
            exclude: [
                // 排除不需要打包的文件
                "configs/README.md",
                "configs/ui_strings.schema.json",
                "configs/app_config.schema.json",
            ],
            resources: [
                // 配置文件
                .process("configs/app_config.json"),
                .process("configs/mirror_config.schema.json"),
                .process("configs/npm_mirror.json"),
                .process("configs/orbstack_mirror.json"),
                .process("configs/ui_strings.json"),
                // Schema 验证文件
                .process("configs/ToolsConfiguration.schema.json"),
            ]
        ),
    ]
)
