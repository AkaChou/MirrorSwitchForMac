//
//  HomebrewHandler.swift
//  MirrorSwitch
//
//  Homebrew 镜像源处理器（参考 chsrc 的 git remote 方式）
//

import Foundation

/// Homebrew 镜像源处理器
class HomebrewHandler: ToolHandlerProtocol {
    /// 路径解析器
    private let pathResolver = PathResolver()

    // MARK: - ToolHandlerProtocol

    /// 切换到指定镜像源
    func switchTo(_ source: MirrorSource) async throws {
        print("🔄 切换 Homebrew 镜像源: \(source.name)")

        // 查找 git 可执行文件
        guard let gitPath = pathResolver.findExecutable("git") else {
            throw ToolHandlerError.executableNotFound
        }

        // 查找 brew 路径
        guard let brewPath = findBrewPath() else {
            throw ToolHandlerError.executableNotFound
        }

        // 1. 修改 brew 本身的 remote
        let brewRepoResult = try await ShellExecutor.execute(gitPath, arguments: [
            "-C", brewPath, "remote", "set-url", "origin", source.url
        ])

        if brewRepoResult.exitCode != 0 {
            throw ToolHandlerError.switchFailed("修改 brew remote 失败: \(brewRepoResult.standardError)")
        }

        // 2. 修改 homebrew-core 的 remote
        let corePath = "\(brewPath)/Library/Taps/homebrew/homebrew-core"

        if FileManager.default.fileExists(atPath: corePath) {
            // 从 brew URL 推导 core URL
            let coreUrl = deriveCoreURL(from: source.url)

            let coreRepoResult = try await ShellExecutor.execute(gitPath, arguments: [
                "-C", corePath, "remote", "set-url", "origin", coreUrl
            ])

            if coreRepoResult.exitCode != 0 {
                print("⚠️ 修改 homebrew-core remote 失败: \(coreRepoResult.standardError)")
            }
        }

        print("✓ Homebrew 镜像源已切换到: \(source.url)")
        print("💡 提示：请运行 'brew update' 使更改生效")
    }

    /// 获取当前配置
    func getCurrentConfig() async throws -> String {
        guard let gitPath = pathResolver.findExecutable("git") else {
            throw ToolHandlerError.executableNotFound
        }

        guard let brewPath = findBrewPath() else {
            throw ToolHandlerError.executableNotFound
        }

        let result = try await ShellExecutor.execute(gitPath, arguments: [
            "-C", brewPath, "remote", "-v"
        ])

        if result.exitCode == 0 {
            return result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            throw ToolHandlerError.commandExecutionFailed(result.standardError)
        }
    }

    /// 备份当前配置
    func backupConfig() async throws {
        guard let brewPath = findBrewPath() else {
            print("⚠️ 找不到 Homebrew 安装路径，跳过备份")
            return
        }

        let backupDir = BackupManager.shared.backupDirectory(for: .homebrew)
        try FileManager.default.createDirectory(at: backupDir,
                                                withIntermediateDirectories: true)

        // 备份 .git/config 文件
        let gitConfigPath = "\(brewPath)/.git/config"
        if FileManager.default.fileExists(atPath: gitConfigPath) {
            let backupPath = backupDir.appendingPathComponent("git.config.backup")

            if FileManager.default.fileExists(atPath: backupPath.path) {
                try FileManager.default.removeItem(at: backupPath)
            }

            try FileManager.default.copyItem(atPath: gitConfigPath, toPath: backupPath.path)
            print("✓ Homebrew 配置已备份")
        }
    }

    /// 恢复备份配置
    func restoreBackup() async throws {
        guard let brewPath = findBrewPath() else {
            throw ToolHandlerError.executableNotFound
        }

        let backupPath = BackupManager.shared.backupDirectory(for: .homebrew)
            .appendingPathComponent("git.config.backup")

        guard FileManager.default.fileExists(atPath: backupPath.path) else {
            throw ToolHandlerError.backupNotFound
        }

        let gitConfigPath = "\(brewPath)/.git/config"

        if FileManager.default.fileExists(atPath: gitConfigPath) {
            try FileManager.default.removeItem(atPath: gitConfigPath)
        }

        try FileManager.default.copyItem(atPath: backupPath.path, toPath: gitConfigPath)
        print("✓ Homebrew 配置已恢复")
    }

    // MARK: - Private Methods

    /// 查找 Homebrew 安装路径
    private func findBrewPath() -> String? {
        // 方法1: 使用 brew --prefix
        if let brewPath = pathResolver.findExecutable("brew") {
            do {
                let result = try ShellExecutor.executeSync(brewPath, arguments: ["--prefix"])
                if result.exitCode == 0 {
                    return result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            } catch {
                // 继续尝试其他方法
            }
        }

        // 方法2: 检查常见路径
        let commonPaths = [
            "/opt/homebrew",
            "/usr/local",
            "/home/linuxbrew/.linuxbrew"
        ]

        for path in commonPaths {
            if FileManager.default.fileExists(atPath: "\(path)/bin/brew") {
                return path
            }
        }

        return nil
    }

    /// 从 brew URL 推导 homebrew-core URL
    ///
    /// 实现方式：
    /// 1. 优先使用预定义的镜像站映射（更准确）
    /// 2. 如果没有映射，使用字符串替换规则
    /// 3. 无法推导则返回官方源
    ///
    /// 映射规则：
    /// - GitHub 官方：brew.git → homebrew-core.git
    /// - 清华镜像：/brew.git → /homebrew-core.git
    /// - 中科大镜像：brew.git → homebrew-core.git
    ///
    /// - Parameter brewURL: brew 仓库 URL
    /// - Returns: homebrew-core 仓库 URL
    private func deriveCoreURL(from brewURL: String) -> String {
        // 常见镜像站的 URL 映射规则
        let mappings: [String: String] = [
            "https://github.com/Homebrew/brew": "https://github.com/Homebrew/homebrew-core",
            "https://mirrors.tuna.tsinghua.edu.cn/git/homebrew/brew.git": "https://mirrors.tuna.tsinghua.edu.cn/git/homebrew/homebrew-core.git",
            "https://mirrors.ustc.edu.cn/brew.git": "https://mirrors.ustc.edu.cn/homebrew-core.git",
        ]

        // 检查是否有直接映射
        for (base, core) in mappings where brewURL.contains(base) {
            return core
        }

        // 默认推导规则
        if brewURL.contains("brew.git") || brewURL.contains("/brew") {
            return brewURL.replacingOccurrences(of: "brew", with: "homebrew-core")
        }

        // 如果无法推导，返回默认值
        return "https://github.com/Homebrew/homebrew-core"
    }
}
