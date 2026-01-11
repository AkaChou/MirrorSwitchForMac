//
//  NPMHandler.swift
//  MirrorSwitch
//
//  NPM 镜像源处理器
//

import Foundation

/// NPM 镜像源处理器
class NPMHandler: ToolHandlerProtocol {
    /// 路径解析器
    private let pathResolver = PathResolver()

    // MARK: - ToolHandlerProtocol

    /// 切换到指定镜像源
    func switchTo(_ source: MirrorSource) async throws {
        // 查找 npm 可执行文件
        guard let npmPath = pathResolver.findExecutable("npm") else {
            throw ToolHandlerError.executableNotFound
        }

        print("🔄 切换 NPM 镜像源: \(source.name)")

        // 执行 npm config set registry 命令
        let result = try await ShellExecutor.execute(npmPath, arguments: [
            "config", "set", "registry", source.url
        ])

        if result.exitCode == 0 {
            print("✓ NPM 镜像源已切换到: \(source.url)")
        } else {
            throw ToolHandlerError.switchFailed(result.standardError)
        }
    }

    /// 获取当前配置
    func getCurrentConfig() async throws -> String {
        guard let npmPath = pathResolver.findExecutable("npm") else {
            throw ToolHandlerError.executableNotFound
        }

        let result = try await ShellExecutor.execute(npmPath, arguments: [
            "config", "get", "registry"
        ])

        if result.exitCode == 0 {
            return result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            throw ToolHandlerError.commandExecutionFailed(result.standardError)
        }
    }

    /// 备份当前配置
    func backupConfig() async throws {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        let npmrcPath = homeDir.appendingPathComponent(".npmrc")

        // 检查文件是否存在
        guard FileManager.default.fileExists(atPath: npmrcPath.path) else {
            print("⚠️ .npmrc 文件不存在，跳过备份")
            return
        }

        // 创建备份目录
        let backupDir = BackupManager.shared.backupDirectory(for: .npm)
        try FileManager.default.createDirectory(at: backupDir,
                                                withIntermediateDirectories: true)

        // 复制备份文件
        let backupPath = backupDir.appendingPathComponent(".npmrc.backup")

        // 如果备份文件已存在，先删除
        if FileManager.default.fileExists(atPath: backupPath.path) {
            try FileManager.default.removeItem(at: backupPath)
        }

        try FileManager.default.copyItem(at: npmrcPath, to: backupPath)
        print("✓ NPM 配置已备份")
    }

    /// 恢复备份配置
    func restoreBackup() async throws {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        let npmrcPath = homeDir.appendingPathComponent(".npmrc")
        let backupPath = BackupManager.shared.backupDirectory(for: .npm)
            .appendingPathComponent(".npmrc.backup")

        // 检查备份文件是否存在
        guard FileManager.default.fileExists(atPath: backupPath.path) else {
            throw ToolHandlerError.backupNotFound
        }

        // 如果目标文件存在，先删除
        if FileManager.default.fileExists(atPath: npmrcPath.path) {
            try FileManager.default.removeItem(at: npmrcPath)
        }

        // 复制备份文件
        try FileManager.default.copyItem(at: backupPath, to: npmrcPath)
        print("✓ NPM 配置已恢复")
    }

    /// 获取配置文件目录
    func getConfigDirectory() -> URL? {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        // .npmrc 在用户主目录下，返回主目录
        return FileManager.default.fileExists(atPath: homeDir.path) ? homeDir : nil
    }
}
