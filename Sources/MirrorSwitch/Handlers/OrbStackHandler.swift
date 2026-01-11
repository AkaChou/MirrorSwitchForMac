//
//  OrbStackHandler.swift
//  MirrorSwitch
//
//  OrbStack 镜像源处理器（JSON 配置修改）
//

import Foundation

/// OrbStack 镜像源处理器
class OrbStackHandler: ToolHandlerProtocol {
    /// OrbStack 配置文件路径
    private let orbstackConfigPath: URL

    /// 初始化
    init() {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        orbstackConfigPath = homeDir
            .appendingPathComponent(".orbstack")
            .appendingPathComponent("config.json")
    }

    // MARK: - ToolHandlerProtocol

    /// 切换到指定镜像源
    func switchTo(_ source: MirrorSource) async throws {
        print("🔄 切换 OrbStack 镜像源: \(source.name)")

        // 检查配置文件是否存在
        guard FileManager.default.fileExists(atPath: orbstackConfigPath.path) else {
            // 配置文件不存在，尝试创建默认配置
            try createDefaultConfig(with: source.url)
            return
        }

        // 读取现有配置
        let data = try Data(contentsOf: orbstackConfigPath)
        var config = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]

        // 修改镜像配置
        // 注意：OrbStack 的实际配置结构可能需要根据实际情况调整
        if var dockerConfig = config["docker"] as? [String: Any] {
            dockerConfig["registry"] = source.url
            config["docker"] = dockerConfig
        } else {
            // 如果没有 docker 配置，创建一个
            config["docker"] = ["registry": source.url]
        }

        // 写回文件
        let newData = try JSONSerialization.data(withJSONObject: config, options: .prettyPrinted)
        try newData.write(to: orbstackConfigPath)

        print("✓ OrbStack 镜像源已切换到: \(source.url)")
        print("💡 提示：请重启 OrbStack 使更改生效")
    }

    /// 获取当前配置
    func getCurrentConfig() async throws -> String {
        guard FileManager.default.fileExists(atPath: orbstackConfigPath.path) else {
            return "未配置（配置文件不存在）"
        }

        let data = try Data(contentsOf: orbstackConfigPath)
        let config = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        if let dockerConfig = config?["docker"] as? [String: Any],
           let registry = dockerConfig["registry"] as? String {
            return registry
        }

        return "未配置"
    }

    /// 备份当前配置
    func backupConfig() async throws {
        guard FileManager.default.fileExists(atPath: orbstackConfigPath.path) else {
            print("⚠️ OrbStack 配置文件不存在，跳过备份")
            return
        }

        let backupDir = BackupManager.shared.backupDirectory(for: .orbstack)
        try FileManager.default.createDirectory(at: backupDir,
                                                withIntermediateDirectories: true)

        let backupPath = backupDir.appendingPathComponent("config.json.backup")

        if FileManager.default.fileExists(atPath: backupPath.path) {
            try FileManager.default.removeItem(at: backupPath)
        }

        try FileManager.default.copyItem(at: orbstackConfigPath, to: backupPath)
        print("✓ OrbStack 配置已备份")
    }

    /// 恢复备份配置
    func restoreBackup() async throws {
        let backupPath = BackupManager.shared.backupDirectory(for: .orbstack)
            .appendingPathComponent("config.json.backup")

        guard FileManager.default.fileExists(atPath: backupPath.path) else {
            throw ToolHandlerError.backupNotFound
        }

        // 确保目标目录存在
        let configDir = orbstackConfigPath.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: configDir,
                                                withIntermediateDirectories: true)

        if FileManager.default.fileExists(atPath: orbstackConfigPath.path) {
            try FileManager.default.removeItem(at: orbstackConfigPath)
        }

        try FileManager.default.copyItem(at: backupPath, to: orbstackConfigPath)
        print("✓ OrbStack 配置已恢复")
    }

    // MARK: - Private Methods

    /// 创建默认配置文件
    private func createDefaultConfig(with registryURL: String) throws {
        let config: [String: Any] = [
            "docker": [
                "registry": registryURL
            ]
        ]

        let data = try JSONSerialization.data(withJSONObject: config, options: .prettyPrinted)

        // 确保目录存在
        let configDir = orbstackConfigPath.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: configDir,
                                                withIntermediateDirectories: true)

        // 写入配置文件
        try data.write(to: orbstackConfigPath)

        print("✓ 已创建 OrbStack 默认配置")
    }
}
