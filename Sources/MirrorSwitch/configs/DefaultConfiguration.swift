//
//  DefaultConfiguration.swift
//  MirrorSwitch
//
//  默认内置配置
//

import Foundation

struct DefaultConfiguration {
    /// 获取最小化工具配置（仅 npm）
    static func minimalTools() -> [ToolConfiguration] {
        // NPM
        let npm = ToolConfiguration(
            id: "npm",
            name: "NPM",
            description: "Node Package Manager",
            detection: DetectionConfiguration(
                command: "npm",
                arguments: ["--version"],
                customPaths: nil,
                fallbackDetection: nil
            ),
            sources: [
                SourceConfiguration(
                    id: "npm-official",
                    name: "官方源",
                    url: "https://registry.npmjs.org/",
                    description: "npm 官方源",
                    region: nil,
                    requiresAuth: nil,
                    auth: nil,
                    configSourceId: nil,
                    configSourceName: nil,
                    configSourceIsBuiltin: nil
                ),
                SourceConfiguration(
                    id: "npm-taobao",
                    name: "淘宝源",
                    url: "https://registry.npmmirror.com/",
                    description: "淘宝镜像",
                    region: "CN",
                    requiresAuth: nil,
                    auth: nil,
                    configSourceId: nil,
                    configSourceName: nil,
                    configSourceIsBuiltin: nil
                ),
                SourceConfiguration(
                    id: "npm-tencent",
                    name: "腾讯云",
                    url: "https://mirrors.cloud.tencent.com/npm/",
                    description: "腾讯云镜像",
                    region: "CN",
                    requiresAuth: nil,
                    auth: nil,
                    configSourceId: nil,
                    configSourceName: nil,
                    configSourceIsBuiltin: nil
                ),
                SourceConfiguration(
                    id: "npm-huawei",
                    name: "华为云",
                    url: "https://mirrors.huaweicloud.com/repository/npm/",
                    description: "华为云镜像",
                    region: "CN",
                    requiresAuth: nil,
                    auth: nil,
                    configSourceId: nil,
                    configSourceName: nil,
                    configSourceIsBuiltin: nil
                ),
            ],
            strategy: .command(
                CommandStrategy(
                    set: CommandSetConfiguration(
                        command: "npm",
                        arguments: ["config", "set", "registry", "{{url}}"],
                        environment: nil,
                        requiresAdmin: false,
                        workingDirectory: nil,
                        preCommands: nil,
                        timeout: 30
                    ),
                    get: CommandGetConfiguration(
                        command: "npm",
                        arguments: ["config", "get", "registry"],
                        outputParser: .trim,
                        timeout: 30
                    )
                )),
            backup: BackupConfiguration(
                filePath: "~/.npmrc",
                backupFileName: ".npmrc.backup",
                backupOriginal: true,
                originalBackupSuffix: nil
            ),
            metadata: ToolMetadata(
                supportedPlatforms: ["macOS", "linux", "windows"],
                supportsSpeedTest: true,
                dependencies: nil,
                documentationURL: "https://docs.npmjs.com/"
            ),
            postActions: nil
        )

        return [npm]
    }
}
