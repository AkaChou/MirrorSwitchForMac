//
//  ToolDetector.swift
//  MirrorSwitch
//
//  工具检测器，用于检测系统中已安装的开发工具
//

import Foundation

/// 工具检测器（Actor 保证线程安全）
actor ToolDetector {
    /// 单例实例
    static let shared = ToolDetector()

    /// 已安装的工具集合
    private var availableTools: Set<ToolType> = []

    private init() {}

    /// 检测指定工具是否已安装
    /// - Parameter tool: 要检测的工具类型
    /// - Returns: 工具是否已安装
    func isToolAvailable(_ tool: ToolType) -> Bool {
        // 如果已缓存检测结果，直接返回
        if availableTools.contains(tool) {
            return true
        }

        // 策略 0: 优先使用用户自定义路径
        if let customPath = ConfigManager.shared.getCustomPath(for: tool) {
            if checkToolAtPath(tool: tool, path: customPath) {
                debugLog("✅ 使用自定义路径检测到 \(tool.displayName): \(customPath)")
                availableTools.insert(tool)
                return true
            }
        }

        // 策略 1: 使用 which 命令检测
        let result = try? ShellExecutor.executeSync(
            "/bin/sh",
            arguments: ["-c", "which \(tool.detectionCommand)"]
        )

        let isAvailable = result?.exitCode == 0 && !(result?.standardOutput.isEmpty ?? true)

        // 策略 2: 如果 PATH 检测失败，尝试文件系统搜索
        if !isAvailable {
            if let _ = searchToolInFileSystem(tool) {
                return true
            }
        }

        // 缓存检测结果
        if isAvailable {
            availableTools.insert(tool)
        }

        return isAvailable
    }

    /// 检查指定路径中是否存在工具
    /// - Parameters:
    ///   - tool: 工具类型
    ///   - path: 自定义路径
    /// - Returns: 工具是否存在于该路径
    nonisolated private func checkToolAtPath(tool: ToolType, path: String) -> Bool {
        // 构建可能的可执行文件路径
        let executableNames = [
            tool.detectionCommand,
            "\(tool.detectionCommand).sh",
            "bin/\(tool.detectionCommand)",
            "bin/\(tool.detectionCommand).sh"
        ]

        for name in executableNames {
            let fullPath = "\(path)/\(name)"

            // 检查文件是否存在且可执行
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: fullPath, isDirectory: &isDir),
                  !isDir.boolValue else {
                continue
            }

            guard FileManager.default.isExecutableFile(atPath: fullPath) else {
                continue
            }

            return true
        }

        return false
    }

    /// 检测所有工具的可用性
    /// - Returns: 已安装的工具数组
    nonisolated func detectAllTools() -> [ToolType] {
        var detected: [ToolType] = []

        for tool in ToolType.allCases {
            // 策略 1: 使用 which 命令检测
            let result = try? ShellExecutor.executeSync(
                "/bin/sh",
                arguments: ["-c", "which \(tool.detectionCommand)"]
            )
            let isAvailable = result?.exitCode == 0 && !(result?.standardOutput.isEmpty ?? true)

            if isAvailable {
                detected.append(tool)
            } else {
                // 策略 2: PATH 检测失败，尝试文件系统搜索
                if let _ = searchToolInFileSystem(tool) {
                    detected.append(tool)
                }
            }
        }

        return detected
    }

    /// 获取工具版本信息
    /// - Parameter tool: 工具类型
    /// - Returns: 版本字符串，检测失败返回 nil
    nonisolated func getToolVersion(_ tool: ToolType) async -> String? {
        // 策略 0: 优先使用用户自定义路径
        if let customPath = ConfigManager.shared.getCustomPath(for: tool) {
            if let version = await getVersionFromCustomPath(tool: tool, path: customPath) {
                debugLog("✅ 使用自定义路径获取 \(tool.displayName) 版本: \(version)")
                return version
            }
        }

        // ⚠️ 注意：OrbStack 等其他工具已移至配置文件中动态加载
        // 这里只保留 npm 的特殊处理逻辑（如果有的话）
        // 其他工具的检测逻辑应该从配置文件中获取

        // 其他工具使用常规检测方式
        let command = "\(tool.detectionCommand) \(tool.versionArguments.joined(separator: " "))"

        let result = try? await ShellExecutor.execute(
            "/bin/sh",
            arguments: ["-lc", command]
        )

        // 提取版本号（通常在输出的第一行）
        if let output = result?.standardOutput, !output.isEmpty {
            let lines = output.components(separatedBy: .newlines)
            let versionLine = lines.first?.trimmingCharacters(in: .whitespaces)

            // 过滤掉错误信息
            if let version = versionLine, !version.lowercased().contains("not found") &&
               !version.lowercased().contains("command not found") &&
               !version.lowercased().contains("error") {
                return version
            }
        }

        // 检查错误输出，可能是工具不存在
        if let error = result?.standardError, !error.isEmpty {
            debugLog("❌ \(tool.displayName) 版本检测失败: \(error)")
        }

        return nil
    }

    /// 清除缓存，重新检测
    func resetCache() {
        availableTools.removeAll()
    }

    // MARK: - 文件系统搜索（针对绿色安装且无 PATH 的工具）

    /// 在文件系统中搜索工具
    /// - Parameter tool: 要搜索的工具类型
    /// - Returns: 找到的工具可执行文件路径，未找到返回 nil
    nonisolated func searchToolInFileSystem(_ tool: ToolType) -> String? {
        // 策略 A: 使用 Spotlight 搜索 (mdfind)
        if let path = searchWithSpotlight(tool) {
            debugLog("🔍 Spotlight 找到 \(tool.displayName): \(path)")
            return path
        }

        // 策略 B: 检查常见目录
        if let path = searchInCommonDirectories(tool) {
            debugLog("🔍 常见目录找到 \(tool.displayName): \(path)")
            return path
        }

        debugLog("⚠️ 文件系统搜索未找到 \(tool.displayName)")
        return nil
    }

    /// 使用 Spotlight (mdfind) 搜索工具
    /// - Parameter tool: 要搜索的工具类型
    /// - Returns: 找到的工具路径，未找到返回 nil
    nonisolated private func searchWithSpotlight(_ tool: ToolType) -> String? {
        let searchCriteria = getSpotlightSearchCriteria(for: tool)

        let result = try? ShellExecutor.executeSync(
            "/usr/bin/mdfind",
            arguments: [searchCriteria]
        )

        guard let output = result?.standardOutput,
              result?.exitCode == 0,
              !output.isEmpty else {
            return nil
        }

        // mdfind 返回多行，取第一个有效的路径
        let lines = output.components(separatedBy: .newlines)
        for line in lines {
            let path = line.trimmingCharacters(in: .whitespaces)
            if !path.isEmpty {
                // 验证路径是否存在且可执行
                if isExecutableFile(at: path) {
                    return path
                }
            }
        }

        return nil
    }

    /// 在常见目录中搜索工具
    /// - Parameter tool: 要搜索的工具类型
    /// - Returns: 找到的工具路径，未找到返回 nil
    nonisolated private func searchInCommonDirectories(_ tool: ToolType) -> String? {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path

        // 常见安装目录
        let commonDirectories = [
            "\(homeDir)/Downloads",
            "\(homeDir)/Documents",
            "\(homeDir)/Tools",
            "\(homeDir)/Applications",
            "/opt",
            "/usr/local",
            "/usr/local/bin",
            "\(homeDir)/.local/bin"
        ]

        let possibleNames = getPossibleExecutableNames(for: tool)

        for directory in commonDirectories {
            // 检查目录是否存在
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: directory, isDirectory: &isDir), isDir.boolValue else {
                continue
            }

            // 在目录中搜索可执行文件
            if let path = searchInDirectory(directory, possibleNames: possibleNames) {
                return path
            }

            // 如果是工具特定的根目录，递归搜索子目录
            if shouldRecursivelySearch(directory, for: tool) {
                if let path = recursivelySearchInDirectory(directory, possibleNames: possibleNames, maxDepth: 3) {
                    return path
                }
            }
        }

        return nil
    }

    /// 递归搜索目录
    nonisolated private func recursivelySearchInDirectory(_ directory: String, possibleNames: [String], maxDepth: Int) -> String? {
        guard maxDepth > 0 else { return nil }

        guard let enumerator = FileManager.default.enumerator(at: URL(fileURLWithPath: directory), includingPropertiesForKeys: [.isDirectoryKey]) else {
            return nil
        }

        let rootComponents = (directory as NSString).pathComponents.count

        for case let fileURL as URL in enumerator {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDir) else {
                continue
            }

            // 计算当前深度
            let components = (fileURL.path as NSString).pathComponents.count
            let depth = components - rootComponents

            guard depth <= maxDepth else {
                enumerator.skipDescendants()
                continue
            }

            // 如果是文件，检查是否匹配
            if !isDir.boolValue {
                let fileName = (fileURL.path as NSString).lastPathComponent
                if possibleNames.contains(fileName) && isExecutableFile(at: fileURL.path) {
                    return fileURL.path
                }
            }
        }

        return nil
    }

    /// 在指定目录中搜索可执行文件
    nonisolated private func searchInDirectory(_ directory: String, possibleNames: [String]) -> String? {
        for name in possibleNames {
            let path = "\(directory)/\(name)"
            if isExecutableFile(at: path) {
                return path
            }
        }
        return nil
    }

    /// 检查文件是否可执行
    nonisolated private func isExecutableFile(at path: String) -> Bool {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), !isDir.boolValue else {
            return false
        }

        // 检查文件权限
        guard FileManager.default.isExecutableFile(atPath: path) else {
            return false
        }

        return true
    }

    /// 判断是否应该递归搜索该目录
    nonisolated private func shouldRecursivelySearch(_ directory: String, for tool: ToolType) -> Bool {
        switch tool {
        case .npm:
            return false
        }
    }

    /// 获取 Spotlight 搜索条件
    nonisolated private func getSpotlightSearchCriteria(for tool: ToolType) -> String {
        switch tool {
        case .npm:
            // 搜索 npm 可执行文件
            return "kMDItemDisplayName == \"npm\"wc"
        }
    }

    /// 获取可能的可执行文件名称
    nonisolated private func getPossibleExecutableNames(for tool: ToolType) -> [String] {
        switch tool {
        case .npm:
            return ["npm"]
        }
    }

    /// 从自定义路径获取工具版本信息
    /// - Parameters:
    ///   - tool: 工具类型
    ///   - path: 自定义路径
    /// - Returns: 版本字符串，检测失败返回 nil
    nonisolated private func getVersionFromCustomPath(tool: ToolType, path: String) async -> String? {
        // 构建可能的可执行文件路径
        let executableNames = [
            tool.detectionCommand,
            "\(tool.detectionCommand).sh",
            "bin/\(tool.detectionCommand)",
            "bin/\(tool.detectionCommand).sh"
        ]

        for name in executableNames {
            let fullPath = "\(path)/\(name)"

            // 检查文件是否存在且可执行
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: fullPath, isDirectory: &isDir),
                  !isDir.boolValue else {
                continue
            }

            guard FileManager.default.isExecutableFile(atPath: fullPath) else {
                continue
            }

            debugLog("🔍 找到可执行文件: \(fullPath)")

            // 尝试获取版本信息
            let command = "\"\(fullPath)\" \(tool.versionArguments.joined(separator: " "))"
            let result = try? await ShellExecutor.execute(
                "/bin/sh",
                arguments: ["-lc", command]
            )

            if let output = result?.standardOutput, !output.isEmpty {
                let lines = output.components(separatedBy: .newlines)
                let versionLine = lines.first?.trimmingCharacters(in: .whitespaces)

                if let version = versionLine,
                   !version.lowercased().contains("not found") &&
                   !version.lowercased().contains("command not found") &&
                   !version.lowercased().contains("error") {
                    debugLog("✅ 版本信息: \(version)")
                    return version
                }
            }
        }

        return nil
    }
}
