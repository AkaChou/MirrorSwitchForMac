//
//  BackupManager.swift
//  MirrorSwitch
//
//  备份管理器，负责首次运行时备份配置
//

import Foundation

/// 备份管理器（单例）
class BackupManager {
    /// 单例实例
    nonisolated(unsafe) static let shared = BackupManager()

    /// 备份根目录
    private let backupRoot: URL

    /// 首次运行标志文件
    private let firstRunFlag: URL

    /// 私有初始化方法
    private init() {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        backupRoot = homeDir.appendingPathComponent(".mirror-switch/backup")
        firstRunFlag = backupRoot.appendingPathComponent(".first_run_completed")
    }

    // MARK: - Public Methods

    /// 获取指定工具的备份目录
    func backupDirectory(for tool: ToolType) -> URL {
        return backupRoot.appendingPathComponent(tool.rawValue.lowercased())
    }

    /// 检查是否首次运行，如果是则执行备份
    func backupIfNeeded() async {
        // 检查是否首次运行
        if !FileManager.default.fileExists(atPath: firstRunFlag.path) {
            print("🔄 首次运行，开始备份配置...")

            // 执行首次备份
            await performFirstRunBackup()

            // 创建标志文件
            FileManager.default.createFile(atPath: firstRunFlag.path, contents: nil)

            print("✓ 首次备份完成")
        } else {
            print("✓ 已完成首次运行备份")
        }
    }

    /// 备份指定工具的配置文件
    func backupConfig(for tool: ToolType) async throws {
        let sourcePath = expandPath(tool.configFilePath)

        // 检查源文件是否存在
        guard FileManager.default.fileExists(atPath: sourcePath) else {
            print("⚠️ 源文件不存在，跳过备份: \(sourcePath)")
            return
        }

        // 创建备份目录
        let backupDir = backupDirectory(for: tool)
        try FileManager.default.createDirectory(at: backupDir,
                                                withIntermediateDirectories: true,
                                                attributes: nil)

        // 备份文件
        let fileName = (tool.configFilePath as NSString).lastPathComponent
        let backupPath = backupDir.appendingPathComponent("\(fileName).backup")

        // 如果备份文件已存在，先删除
        if FileManager.default.fileExists(atPath: backupPath.path) {
            try FileManager.default.removeItem(at: backupPath)
        }

        // 复制文件到备份目录
        try FileManager.default.copyItem(atPath: sourcePath, toPath: backupPath.path)
        print("✓ 已备份 \(tool.displayName): \(backupPath.path)")
    }

    /// 恢复指定工具的备份配置
    func restoreBackup(for tool: ToolType) async throws {
        let backupDir = backupDirectory(for: tool)
        let fileName = (tool.configFilePath as NSString).lastPathComponent
        let backupPath = backupDir.appendingPathComponent("\(fileName).backup")

        // 检查备份文件是否存在
        guard FileManager.default.fileExists(atPath: backupPath.path) else {
            throw BackupError.backupNotFound
        }

        let targetPath = expandPath(tool.configFilePath)

        // 如果目标文件存在，先删除
        if FileManager.default.fileExists(atPath: targetPath) {
            try FileManager.default.removeItem(atPath: targetPath)
        }

        // 复制备份文件到目标位置
        try FileManager.default.copyItem(atPath: backupPath.path, toPath: targetPath)
        print("✓ 已恢复 \(tool.displayName) 备份")
    }

    // MARK: - Private Methods

    /// 执行首次运行备份
    private func performFirstRunBackup() async {
        // 创建备份根目录
        try? FileManager.default.createDirectory(at: backupRoot,
                                                  withIntermediateDirectories: true,
                                                  attributes: nil)

        // 依次备份各工具的配置
        for tool in ToolType.allCases {
            do {
                try await backupConfig(for: tool)
            } catch {
                print("⚠️ 备份 \(tool.displayName) 失败: \(error.localizedDescription)")
            }
        }
    }

    /// 展开 ~ 路径
    private func expandPath(_ path: String) -> String {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        return path.replacingOccurrences(of: "~", with: homeDir)
    }
}

/// 备份错误类型
enum BackupError: Error {
    case backupNotFound
    case backupFailed(String)
    case restoreFailed(String)

    var localizedDescription: String {
        switch self {
        case .backupNotFound:
            return "备份文件不存在"
        case .backupFailed(let message):
            return "备份失败: \(message)"
        case .restoreFailed(let message):
            return "恢复失败: \(message)"
        }
    }
}
