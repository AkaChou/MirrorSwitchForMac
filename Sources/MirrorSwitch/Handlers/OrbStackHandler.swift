//
//  OrbStackHandler.swift
//  MirrorSwitch
//
//  OrbStack 镜像源处理器（JSON 配置修改）
//

import Foundation

/// OrbStack 镜像源处理器
class OrbStackHandler: ToolHandlerProtocol {
    /// OrbStack Docker 配置文件路径
    private let dockerConfigPath: URL

    /// 原始配置文件备份标记
    private static let originalBackupFlag = "original_docker_backed"

    /// 初始化
    init() {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        dockerConfigPath = homeDir
            .appendingPathComponent(".orbstack")
            .appendingPathComponent("config")
            .appendingPathComponent("docker.json")
    }

    // MARK: - ToolHandlerProtocol

    /// 切换到指定镜像源
    func switchTo(_ source: MirrorSource) async throws {
        print("🔄 切换 OrbStack 镜像源: \(source.name)")

        // 检查配置文件是否存在
        guard FileManager.default.fileExists(atPath: dockerConfigPath.path) else {
            // 配置文件不存在，尝试创建默认配置
            try createDefaultConfig(with: source.url)
            return
        }

        // 读取现有配置
        let data = try Data(contentsOf: dockerConfigPath)
        var config = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]

        // 修改镜像配置 - OrbStack 使用 registry-mirrors 配置
        config["registry-mirrors"] = [source.url]

        // 写回文件，使用自定义 JSON 格式化避免转义
        let jsonString = formatConfigJSON(config)
        try jsonString.write(to: dockerConfigPath, atomically: true, encoding: .utf8)

        print("✓ OrbStack 镜像源已切换到: \(source.url)")
    }

    /// 获取当前配置
    func getCurrentConfig() async throws -> String {
        guard FileManager.default.fileExists(atPath: dockerConfigPath.path) else {
            return "未配置（配置文件不存在）"
        }

        let data = try Data(contentsOf: dockerConfigPath)
        let config = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        if let registryMirrors = config?["registry-mirrors"] as? [String],
           let firstMirror = registryMirrors.first {
            return firstMirror
        }

        return "未配置"
    }

    /// 备份当前配置
    func backupConfig() async throws {
        guard FileManager.default.fileExists(atPath: dockerConfigPath.path) else {
            print("⚠️ OrbStack Docker 配置文件不存在，跳过备份")
            return
        }

        let backupDir = BackupManager.shared.backupDirectory(for: .orbstack)
        try FileManager.default.createDirectory(at: backupDir,
                                                withIntermediateDirectories: true)

        let backupPath = backupDir.appendingPathComponent("docker.json.backup")

        if FileManager.default.fileExists(atPath: backupPath.path) {
            try FileManager.default.removeItem(at: backupPath)
        }

        try FileManager.default.copyItem(at: dockerConfigPath, to: backupPath)
        print("✓ OrbStack Docker 配置已备份")
    }

    /// 恢复备份配置
    /// 优先恢复原始配置备份（docker.json.original）
    /// 如果没有原始备份，则使用普通备份（docker.json.backup）
    func restoreBackup() async throws {
        let originalBackupPath = getOriginalBackupPath()
        let normalBackupPath = BackupManager.shared.backupDirectory(for: .orbstack)
            .appendingPathComponent("docker.json.backup")

        // 优先尝试恢复原始配置
        if FileManager.default.fileExists(atPath: originalBackupPath.path) {
            if FileManager.default.fileExists(atPath: dockerConfigPath.path) {
                try FileManager.default.removeItem(at: dockerConfigPath)
            }
            try FileManager.default.copyItem(at: originalBackupPath, to: dockerConfigPath)
            print("✓ OrbStack 配置已恢复（原始备份）")
            return
        }

        // 如果没有原始备份，尝试普通备份
        guard FileManager.default.fileExists(atPath: normalBackupPath.path) else {
            throw ToolHandlerError.backupNotFound
        }

        // 确保目标目录存在
        let configDir = dockerConfigPath.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: configDir,
                                                withIntermediateDirectories: true)

        if FileManager.default.fileExists(atPath: dockerConfigPath.path) {
            try FileManager.default.removeItem(at: dockerConfigPath)
        }

        try FileManager.default.copyItem(at: normalBackupPath, to: dockerConfigPath)
        print("✓ OrbStack 配置已恢复（普通备份）")
    }

    /// 获取配置文件目录
    func getConfigDirectory() -> URL? {
        let configDir = dockerConfigPath.deletingLastPathComponent()
        return FileManager.default.fileExists(atPath: configDir.path) ? configDir : nil
    }

    // MARK: - Public Methods

    /// 备份原始配置文件（首次检测到 OrbStack 时调用）
    func backupOriginalConfig() async throws {
        // 如果已经备份过，跳过
        if hasOriginalBackup() {
            debugLog("ℹ️ OrbStack 原始配置已备份，跳过")
            return
        }

        // 检查配置文件是否存在
        guard FileManager.default.fileExists(atPath: dockerConfigPath.path) else {
            debugLog("⚠️ 配置文件不存在，无需备份: \(dockerConfigPath.path)")
            return
        }

        // 确保备份目录存在
        let backupPath = getOriginalBackupPath()
        let backupDir = backupPath.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: backupDir,
                                                withIntermediateDirectories: true)

        // 删除旧备份（如果存在）
        if FileManager.default.fileExists(atPath: backupPath.path) {
            try FileManager.default.removeItem(at: backupPath)
        }

        // 备份原始配置
        try FileManager.default.copyItem(at: dockerConfigPath, to: backupPath)
        markOriginalBackup()

        debugLog("✅ 已备份 OrbStack 原始配置: \(backupPath.path)")
    }

    // MARK: - Private Methods

    /// 获取原始配置备份路径
    private func getOriginalBackupPath() -> URL {
        let backupDir = BackupManager.shared.backupDirectory(for: .orbstack)
        return backupDir.appendingPathComponent("docker.json.original")
    }

    /// 检查是否已备份原始配置
    private func hasOriginalBackup() -> Bool {
        let flagPath = getOriginalBackupPath().deletingLastPathComponent()
            .appendingPathComponent(Self.originalBackupFlag)
        return FileManager.default.fileExists(atPath: flagPath.path)
    }

    /// 标记原始配置已备份
    private func markOriginalBackup() {
        let flagPath = getOriginalBackupPath().deletingLastPathComponent()
            .appendingPathComponent(Self.originalBackupFlag)
        FileManager.default.createFile(atPath: flagPath.path, contents: Data())
    }

    /// 创建默认配置文件
    private func createDefaultConfig(with registryURL: String) throws {
        let config: [String: Any] = [
            "registry-mirrors": [registryURL]
        ]

        // 使用自定义 JSON 格式化避免转义
        let jsonString = formatConfigJSON(config)

        // 确保目录存在
        let configDir = dockerConfigPath.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: configDir,
                                                withIntermediateDirectories: true)

        // 写入配置文件
        try jsonString.write(to: dockerConfigPath, atomically: true, encoding: .utf8)

        print("✓ 已创建 OrbStack Docker 默认配置")
    }

    /// 格式化配置为 JSON 字符串（不转义斜杠）
    private func formatConfigJSON(_ config: [String: Any]) -> String {
        var json = "{\n"

        var isFirst = true
        for (key, value) in config {
            if !isFirst {
                json += ",\n"
            }
            isFirst = false

            json += "  \"\(key)\": "

            if let array = value as? [String] {
                json += "[\n"
                for (index, item) in array.enumerated() {
                    json += "    \"\(item)\""
                    if index < array.count - 1 {
                        json += ","
                    }
                    json += "\n"
                }
                json += "  ]"
            }
        }

        json += "\n}\n"
        return json
    }
}
