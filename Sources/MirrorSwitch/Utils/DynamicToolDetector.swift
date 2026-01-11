//
//  DynamicToolDetector.swift
//  MirrorSwitch
//
//  动态工具检测器
//  根据配置文件动态检测工具是否安装及版本信息
//

import Foundation
import AppKit

/// 动态工具检测器
/// 从配置文件读取工具定义并动态检测工具状态
@MainActor
class DynamicToolDetector {
    /// 单例
    static let shared = DynamicToolDetector()

    private init() {}

    // MARK: - 公共方法

    /// 检测所有配置的工具
    /// - Returns: 工具版本字典 [toolId: version]
    func detectAllTools() async -> [String: String] {
        let tools = ConfigurationDrivenSourceManager.shared.getAllTools()
        var versions: [String: String] = [:]

        for tool in tools {
            if let version = await detectTool(tool: tool) {
                versions[tool.id] = version
                debugLog("✅ 检测到 \(tool.name): \(version)")
            } else {
                debugLog("⚠️ 未检测到 \(tool.name)")
            }
        }

        return versions
    }

    /// 检测指定工具
    /// - Parameter toolId: 工具 ID
    /// - Returns: 版本字符串，如果检测失败返回 nil
    func detectTool(toolId: String) async -> String? {
        guard let tool = ConfigurationDrivenSourceManager.shared.getTool(by: toolId) else {
            return nil
        }
        return await detectTool(tool: tool)
    }

    /// 检查工具是否可用
    /// - Parameter toolId: 工具 ID
    /// - Returns: 是否可用
    func isToolAvailable(toolId: String) async -> Bool {
        return await detectTool(toolId: toolId) != nil
    }

    // MARK: - 私有方法

    /// 检测单个工具
    /// - Parameter tool: 工具配置
    /// - Returns: 版本字符串，如果检测失败返回 nil
    private func detectTool(tool: ToolConfiguration) async -> String? {
        // 0. 优先检查用户手动选择的路径（最高优先级）
        if let userCustomPath = ConfigManager.shared.getCustomPath(for: tool.id) {
            debugLog("🔍 发现用户自定义路径: \(userCustomPath)")
            if let version = await tryDetectAtPath(userCustomPath, tool: tool) {
                debugLog("✅ 使用自定义路径检测到版本: \(version)")
                return version
            }
        }

        // 1. 尝试主要检测方式（命令）
        let result = await detectByCommand(tool)

        if let version = parseVersion(result, toolId: tool.id) {
            return version
        }

        // 2. 尝试备用检测方式
        if let fallback = tool.detection.fallbackDetection {
            if let version = await tryFallbackDetection(fallback, tool: tool) {
                return version
            }
        }

        // 3. 尝试配置文件中的自定义路径
        if let customPaths = tool.detection.customPaths {
            for path in customPaths {
                if let version = await tryDetectAtPath(path, tool: tool) {
                    return version
                }
            }
        }

        return nil
    }

    /// 通过命令检测工具
    /// - Parameter tool: 工具配置
    /// - Returns: 命令输出
    private func detectByCommand(_ tool: ToolConfiguration) async -> String? {
        do {
            let result = try await ShellExecutor.execute(
                tool.detection.command,
                arguments: tool.detection.arguments
            )
            return result.standardOutput
        } catch {
            debugLog("⚠️ 命令检测失败: \(error.localizedDescription)")
            return nil
        }
    }

    /// 尝试备用检测方式
    /// - Parameters:
    ///   - fallback: 备用检测配置
    ///   - tool: 工具配置
    /// - Returns: 版本字符串
    private func tryFallbackDetection(_ fallback: FallbackDetection, tool: ToolConfiguration) async -> String? {
        let rawResult: String?

        switch fallback {
        case .file(let path):
            rawResult = await detectByFile(path)

        case .app(let bundleId, let path):
            rawResult = await detectByApp(bundleId: bundleId, path: path)

        case .environmentVariable(let name):
            rawResult = detectByEnvironmentVariable(name)

        case .script(let command, let arguments):
            rawResult = await detectByScript(command: command, arguments: arguments)
        }

        // 所有 fallback 检测结果都需要通过 parseVersion 过滤
        // 这样可以过滤掉 "detected" 等无意义的占位符
        return parseVersion(rawResult, toolId: tool.id)
    }

    /// 通过文件存在检测
    /// - Parameter path: 文件路径
    /// - Returns: 工具名称（表示检测到）
    private func detectByFile(_ path: String) async -> String? {
        let expandedPath = NSString(string: path).expandingTildeInPath
        let fileManager = FileManager.default

        // 支持通配符
        if path.contains("*") {
            do {
                let url = URL(fileURLWithPath: expandedPath)
                let files = try fileManager.contentsOfDirectory(
                    atPath: url.deletingLastPathComponent().path
                )
                let pattern = url.lastPathComponent
                let matchingFiles = files.filter {
                    $0.matchesPattern(pattern)
                }
                return matchingFiles.isEmpty ? nil : "detected"
            } catch {
                return nil
            }
        }

        return fileManager.fileExists(atPath: expandedPath) ? "detected" : nil
    }

    /// 通过应用包检测
    /// - Parameters:
    ///   - bundleId: Bundle ID
    ///   - path: 应用路径（可选）
    /// - Returns: 版本字符串
    private func detectByApp(bundleId: String, path: String?) async -> String? {
        let workspace = NSWorkspace.shared

        // 尝试通过 Bundle ID 检测
        if let appURL = workspace.urlForApplication(withBundleIdentifier: bundleId) {
            return extractAppVersion(from: appURL.path)
        }

        // 尝试通过路径检测
        if let path = path {
            let expandedPath = NSString(string: path).expandingTildeInPath
            if FileManager.default.fileExists(atPath: expandedPath) {
                return extractAppVersion(from: expandedPath)
            }
        }

        return nil
    }

    /// 通过环境变量检测
    /// - Parameter name: 环境变量名
    /// - Returns: 环境变量值
    private func detectByEnvironmentVariable(_ name: String) -> String? {
        return ProcessInfo.processInfo.environment[name]
    }

    /// 通过脚本检测
    /// - Parameters:
    ///   - command: 命令
    ///   - arguments: 参数
    /// - Returns: 脚本输出
    private func detectByScript(command: String, arguments: [String]) async -> String? {
        do {
            let result = try await ShellExecutor.execute(command, arguments: arguments)
            return result.standardOutput.isEmpty ? nil : result.standardOutput
        } catch {
            return nil
        }
    }

    /// 尝试在自定义路径检测工具
    /// - Parameters:
    ///   - path: 自定义路径（可能是目录或可执行文件）
    ///   - tool: 工具配置
    /// - Returns: 版本字符串
    private func tryDetectAtPath(_ path: String, tool: ToolConfiguration) async -> String? {
        let expandedPath = NSString(string: path).expandingTildeInPath

        // 首先尝试直接执行路径（如果是可执行文件）
        if FileManager.default.fileExists(atPath: expandedPath) {
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: expandedPath, isDirectory: &isDir)

            // 如果是文件（不是目录），直接尝试执行
            if !isDir.boolValue {
                do {
                    let result = try await ShellExecutor.execute(
                        expandedPath,
                        arguments: tool.detection.arguments
                    )
                    return parseVersion(result.standardOutput, toolId: tool.id)
                } catch {
                    // 执行失败，继续尝试其他方式
                }
            }
        }

        // 如果路径是目录或者直接执行失败，尝试在目录下查找可执行文件
        // 构建可能的可执行文件路径
        let command = tool.detection.command
        let executableNames = [
            command,
            "\(command).sh",
            "bin/\(command)",
            "bin/\(command).sh"
        ]

        for name in executableNames {
            let fullPath = "\(expandedPath)/\(name)"

            // 检查文件是否存在且可执行
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: fullPath, isDirectory: &isDir),
                  !isDir.boolValue else {
                continue
            }

            guard FileManager.default.isExecutableFile(atPath: fullPath) else {
                continue
            }

            debugLog("✅ 找到可执行文件: \(fullPath)")

            // 尝试获取版本信息
            do {
                let result = try await ShellExecutor.execute(
                    fullPath,
                    arguments: tool.detection.arguments
                )
                if let version = parseVersion(result.standardOutput, toolId: tool.id) {
                    debugLog("✅ 检测到版本: \(version)")
                    return version
                }
            } catch {
                debugLog("⚠️ 执行失败: \(error.localizedDescription)")
            }
        }

        return nil
    }

    // MARK: - 版本解析

    /// 解析版本字符串
    /// - Parameters:
    ///   - output: 命令输出
    ///   - toolId: 工具 ID
    /// - Returns: 解析后的版本字符串
    private func parseVersion(_ output: String?, toolId: String) -> String? {
        guard let output = output, !output.isEmpty else {
            return nil
        }

        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)

        // 过滤掉无意义的占位符
        if trimmed.lowercased() == "detected" || trimmed.isEmpty {
            return nil
        }

        // 针对不同工具的特殊解析
        switch toolId {
        case "npm":
            // npm: "npm@10.5.0" -> "10.5.0"
            if let range = trimmed.range(of: "\\d+\\.\\d+\\.\\d+", options: .regularExpression) {
                return String(trimmed[range])
            }
        case "pip", "pip2", "pip3":
            // pip: "pip 23.2.1 from ..." -> "23.2.1"
            if let range = trimmed.range(of: "\\d+\\.\\d+\\.\\d+", options: .regularExpression) {
                return String(trimmed[range])
            }
        case "brew":
            // brew: "Homebrew 4.1.0" -> "4.1.0"
            if let range = trimmed.range(of: "\\d+\\.\\d+\\.\\d+", options: .regularExpression) {
                return String(trimmed[range])
            }
        case "maven":
            // Maven: "Apache Maven 3.9.5" -> "3.9.5"
            if let range = trimmed.range(of: "\\d+\\.\\d+\\.\\d+", options: .regularExpression) {
                return String(trimmed[range])
            }
        default:
            // 通用版本号提取
            if let range = trimmed.range(of: "\\d+\\.\\d+(\\.\\d+)?", options: .regularExpression) {
                return String(trimmed[range])
            }
        }

        // 如果无法解析版本号，返回原始输出
        return trimmed.isEmpty ? nil : trimmed
    }

    /// 从应用路径提取版本
    /// - Parameter path: 应用路径
    /// - Returns: 版本字符串
    private func extractAppVersion(from path: String) -> String? {
        let plistPath = (path as NSString).appendingPathComponent("Contents/Info.plist")

        guard let plist = NSDictionary(contentsOfFile: plistPath),
              let version = plist["CFBundleShortVersionString"] as? String ??
                          plist["CFBundleVersion"] as? String else {
            return nil
        }

        return version
    }
}

// MARK: - 辅助扩展

extension String {
    /// 检查字符串是否匹配通配符模式
    func matchesPattern(_ pattern: String) -> Bool {
        do {
            let regex = try NSRegularExpression(
                pattern: pattern
                    .replacingOccurrences(of: ".", with: "\\.")
                    .replacingOccurrences(of: "*", with: ".*")
                    .replacingOccurrences(of: "?", with: ".")
            )
            return regex.firstMatch(in: self, range: NSRange(location: 0, length: utf16.count)) != nil
        } catch {
            return false
        }
    }
}
