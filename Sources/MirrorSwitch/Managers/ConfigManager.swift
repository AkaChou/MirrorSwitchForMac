//
//  ConfigManager.swift
//  MirrorSwitch
//
//  配置文件管理器
//

import Foundation

/// 配置文件管理器（单例）
class ConfigManager {
    /// 单例实例
    nonisolated(unsafe) static let shared = ConfigManager()

    /// 应用目录
    private let appDirectory: URL

    /// 配置文件路径
    private let configFile: URL

    /// 选中状态文件路径
    private let selectionFile: URL

    /// 自定义工具路径文件路径
    private let customPathFile: URL

    /// 私有初始化方法
    private init() {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        appDirectory = homeDir.appendingPathComponent(".mirror-switch")
        configFile = appDirectory.appendingPathComponent("config.json")
        selectionFile = appDirectory.appendingPathComponent("selection.json")
        customPathFile = appDirectory.appendingPathComponent("custom_paths.json")

        // 创建目录（如果不存在）
        createDirectoryIfNeeded()
    }

    // MARK: - Public Methods

    /// 加载配置
    func loadConfig() -> MirrorSourceConfiguration {
        // 检查配置文件是否存在
        guard FileManager.default.fileExists(atPath: configFile.path) else {
            // 首次运行，保存默认配置
            saveConfig(MirrorSourceConfiguration.defaultConfig)
            return MirrorSourceConfiguration.defaultConfig
        }

        // 读取并解析配置文件
        guard let data = try? Data(contentsOf: configFile),
            let config = try? JSONDecoder().decode(MirrorSourceConfiguration.self, from: data)
        else {
            // 解析失败，返回默认配置
            return MirrorSourceConfiguration.defaultConfig
        }

        // 加载选中状态
        var configWithSelection = config
        for tool in ToolType.allCases {
            if let sourceId = getCurrentSelection(for: tool) {
                configWithSelection.currentSelection[tool.rawValue] = sourceId
            }
        }

        return configWithSelection
    }

    /// 保存配置
    func saveConfig(_ config: MirrorSourceConfiguration) {
        guard let data = try? JSONEncoder().encode(config) else {
            print("⚠️ 配置编码失败")
            return
        }

        do {
            try data.write(to: configFile)
            print("✓ 配置已保存")
        } catch {
            print("⚠️ 配置保存失败: \(error.localizedDescription)")
        }
    }

    /// 获取指定工具的当前选中镜像源 ID
    func getCurrentSelection(for tool: ToolType) -> String? {
        guard FileManager.default.fileExists(atPath: selectionFile.path) else {
            return nil
        }

        guard let data = try? Data(contentsOf: selectionFile),
            let selections = try? JSONDecoder().decode([String: String].self, from: data)
        else {
            return nil
        }

        return selections[tool.rawValue]
    }

    /// 保存指定工具的选中镜像源 ID
    func saveCurrentSelection(tool: ToolType, sourceId: String) {
        // 读取现有选中状态
        var selections: [String: String]
        if let data = try? Data(contentsOf: selectionFile),
            let existing = try? JSONDecoder().decode([String: String].self, from: data)
        {
            selections = existing
        } else {
            selections = [:]
        }

        // 更新选中状态
        selections[tool.rawValue] = sourceId

        // 保存到文件
        guard let data = try? JSONEncoder().encode(selections) else {
            print("⚠️ 选中状态编码失败")
            return
        }

        do {
            try data.write(to: selectionFile)
            print("✓ 选中状态已保存: \(tool.displayName) -> \(sourceId)")
        } catch {
            print("⚠️ 选中状态保存失败: \(error.localizedDescription)")
        }
    }

    /// 清除指定工具的选中镜像源 ID
    func clearCurrentSelection(tool: ToolType) {
        // 检查文件是否存在
        guard FileManager.default.fileExists(atPath: selectionFile.path) else {
            return
        }

        // 读取现有选中状态
        guard let data = try? Data(contentsOf: selectionFile),
            var selections = try? JSONDecoder().decode([String: String].self, from: data)
        else {
            return
        }

        // 移除该工具的选中状态
        selections.removeValue(forKey: tool.rawValue)

        // 如果 selections 为空，删除文件；否则保存更新后的 selections
        if selections.isEmpty {
            try? FileManager.default.removeItem(at: selectionFile)
            print("✓ 选中状态已清除（文件已删除）: \(tool.displayName)")
        } else {
            guard let newData = try? JSONEncoder().encode(selections) else {
                print("⚠️ 选中状态编码失败")
                return
            }

            do {
                try newData.write(to: selectionFile)
                print("✓ 选中状态已清除: \(tool.displayName)")
            } catch {
                print("⚠️ 选中状态保存失败: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - 工具 ID 支持（动态工具）

    /// 获取指定工具的当前选中镜像源 ID（通过工具 ID）
    /// - Parameter toolId: 工具 ID（如 "npm", "maven", "brew"）
    /// - Returns: 选中的镜像源 ID
    func getCurrentSelection(for toolId: String) -> String? {
        guard FileManager.default.fileExists(atPath: selectionFile.path) else {
            return nil
        }

        guard let data = try? Data(contentsOf: selectionFile),
            let selections = try? JSONDecoder().decode([String: String].self, from: data)
        else {
            return nil
        }

        return selections[toolId]
    }

    /// 保存指定工具的选中镜像源 ID（通过工具 ID）
    /// - Parameters:
    ///   - toolId: 工具 ID（如 "npm", "maven", "brew"）
    ///   - sourceId: 要保存的镜像源 ID
    func saveCurrentSelection(toolId: String, sourceId: String) {
        // 读取现有选中状态
        var selections: [String: String]
        if let data = try? Data(contentsOf: selectionFile),
            let existing = try? JSONDecoder().decode([String: String].self, from: data)
        {
            selections = existing
        } else {
            selections = [:]
        }

        // 更新选中状态
        selections[toolId] = sourceId

        // 保存到文件
        guard let data = try? JSONEncoder().encode(selections) else {
            print("⚠️ 选中状态编码失败")
            return
        }

        do {
            try data.write(to: selectionFile)
            debugLog("✓ 选中状态已保存: \(toolId) -> \(sourceId)")
        } catch {
            print("⚠️ 选中状态保存失败: \(error.localizedDescription)")
        }
    }

    /// 获取所有选中状态
    func getAllSelections() -> [String: String] {
        guard FileManager.default.fileExists(atPath: selectionFile.path) else {
            return [:]
        }

        guard let data = try? Data(contentsOf: selectionFile),
            let selections = try? JSONDecoder().decode([String: String].self, from: data)
        else {
            return [:]
        }

        return selections
    }

    /// 清除指定工具的选中镜像源 ID（通过工具 ID）
    /// - Parameter toolId: 工具 ID
    func clearCurrentSelection(toolId: String) {
        // 检查文件是否存在
        guard FileManager.default.fileExists(atPath: selectionFile.path) else {
            return
        }

        // 读取现有选中状态
        guard let data = try? Data(contentsOf: selectionFile),
            var selections = try? JSONDecoder().decode([String: String].self, from: data)
        else {
            return
        }

        // 移除该工具的选中状态
        selections.removeValue(forKey: toolId)

        // 如果 selections 为空，删除文件；否则保存更新后的 selections
        if selections.isEmpty {
            try? FileManager.default.removeItem(at: selectionFile)
            debugLog("✓ 选中状态已清除（文件已删除）: \(toolId)")
        } else {
            guard let newData = try? JSONEncoder().encode(selections) else {
                print("⚠️ 选中状态编码失败")
                return
            }

            do {
                try newData.write(to: selectionFile)
                debugLog("✓ 选中状态已清除: \(toolId)")
            } catch {
                print("⚠️ 选中状态保存失败: \(error.localizedDescription)")
            }
        }
    }

    /// 获取指定工具的自定义路径
    func getCustomPath(for tool: ToolType) -> String? {
        return getCustomPath(for: tool.rawValue)
    }

    /// 保存指定工具的自定义路径
    func saveCustomPath(tool: ToolType, path: String) {
        saveCustomPath(toolId: tool.rawValue, path: path)
    }

    /// 获取指定工具的自定义路径（通过工具 ID）
    /// - Parameter toolId: 工具 ID（如 "npm", "maven", "brew"）
    /// - Returns: 自定义路径
    func getCustomPath(for toolId: String) -> String? {
        guard FileManager.default.fileExists(atPath: customPathFile.path) else {
            return nil
        }

        guard let data = try? Data(contentsOf: customPathFile),
            let customPaths = try? JSONDecoder().decode([String: String].self, from: data)
        else {
            return nil
        }

        return customPaths[toolId]
    }

    /// 保存指定工具的自定义路径（通过工具 ID）
    /// - Parameters:
    ///   - toolId: 工具 ID（如 "npm", "maven", "brew"）
    ///   - path: 要保存的自定义路径
    func saveCustomPath(toolId: String, path: String) {
        // 读取现有自定义路径
        var customPaths: [String: String]
        if let data = try? Data(contentsOf: customPathFile),
            let existing = try? JSONDecoder().decode([String: String].self, from: data)
        {
            customPaths = existing
        } else {
            customPaths = [:]
        }

        // 更新自定义路径
        customPaths[toolId] = path

        // 保存到文件
        guard let data = try? JSONEncoder().encode(customPaths) else {
            print("⚠️ 自定义路径编码失败")
            return
        }

        do {
            try data.write(to: customPathFile)
            debugLog("✓ 自定义路径已保存: \(toolId) -> \(path)")
        } catch {
            print("⚠️ 自定义路径保存失败: \(error.localizedDescription)")
        }
    }

    // MARK: - Private Methods

    /// 创建应用目录（如果不存在）
    private func createDirectoryIfNeeded() {
        if !FileManager.default.fileExists(atPath: appDirectory.path) {
            do {
                try FileManager.default.createDirectory(
                    at: appDirectory,
                    withIntermediateDirectories: true,
                    attributes: nil)
                print("✓ 应用目录已创建: \(appDirectory.path)")
            } catch {
                print("⚠️ 创建应用目录失败: \(error.localizedDescription)")
            }
        }
    }
}
