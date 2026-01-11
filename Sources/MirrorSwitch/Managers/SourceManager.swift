//
//  SourceManager.swift
//  MirrorSwitch
//
//  核心管理器（已废弃，请使用 ConfigurationDrivenSourceManager）
//  此文件保留仅用于向后兼容，实际功能已迁移到 ConfigurationDrivenSourceManager
//

import Foundation

/// 核心管理器（单例）
/// 此类已被 ConfigurationDrivenSourceManager 替代
@MainActor
class SourceManager {
    /// 单例实例
    static let shared = SourceManager()

    /// 配置管理器
    private let configManager = ConfigManager.shared

    /// 网络测速器
    private let networkTester = NetworkTester()

    /// 镜像源配置
    private var config: MirrorSourceConfiguration

    /// 是否已初始化
    private var isInitialized = false

    /// 私有初始化方法
    private init() {
        self.config = MirrorSourceConfiguration.defaultConfig
    }

    // MARK: - Public Methods

    /// 初始化管理器
    func initialize() async {
        guard !isInitialized else { return }

        // 加载配置
        config = configManager.loadConfig()

        // 检测当前实际使用的镜像源并设置选中状态
        await detectCurrentSources()

        isInitialized = true
        print("✓ SourceManager 初始化完成")
    }

    /// 获取指定工具的镜像源列表
    func getSources(for tool: ToolType) -> [MirrorSource] {
        return config.getSources(for: tool)
    }

    /// 切换到指定镜像源
    func switchSource(tool: ToolType, source: MirrorSource) async throws {
        print("⚠️ 使用已废弃的 SourceManager，请使用 ConfigurationDrivenSourceManager")
        throw SourceManagerError.switchFailed("请使用 ConfigurationDrivenSourceManager")
    }

    /// 测试指定工具的所有镜像源延迟
    func testSpeed(sources: [MirrorSource]) async {
        print("⚡️ 开始测速，共 \(sources.count) 个镜像源...")

        await withTaskGroup(of: (String, Int?).self) { group in
            for source in sources {
                group.addTask {
                    await self.networkTester.testSource(source)
                }
            }

            for await (sourceId, pingTime) in group {
                updatePingTime(sourceId: sourceId, pingTime: pingTime)
            }
        }

        print("✓ 测速完成")
    }

    /// 获取指定工具的当前配置
    func getCurrentConfig(for tool: ToolType) async throws -> String {
        print("⚠️ 使用已废弃的 SourceManager，请使用 ConfigurationDrivenSourceManager")
        throw SourceManagerError.switchFailed("请使用 ConfigurationDrivenSourceManager")
    }

    /// 恢复指定工具的备份配置
    func restoreConfig(for tool: ToolType) async throws {
        print("⚠️ 使用已废弃的 SourceManager，请使用 ConfigurationDrivenSourceManager")
        throw SourceManagerError.switchFailed("请使用 ConfigurationDrivenSourceManager")
    }

    // MARK: - Private Methods

    /// 检测当前实际使用的镜像源
    private func detectCurrentSources() async {
        // 简化实现：仅用于兼容
    }

    /// 更新延迟时间
    private func updatePingTime(sourceId: String, pingTime: Int?) {
        for tool in ToolType.allCases {
            if var sources = config.tools[tool] {
                if let index = sources.firstIndex(where: { $0.id == sourceId }) {
                    sources[index].pingTime = pingTime
                    config.tools[tool] = sources
                }
            }
        }
    }
}

/// 管理器错误类型
enum SourceManagerError: Error {
    case handlerNotFound
    case notInitialized
    case switchFailed(String)
    case toolNotFound(String)
    case sourceNotFound(String)
    case backupNotFound
    case backupNotSupported
    case parseFailed(String)
    case commandExecutionFailed(String)
    case configNotFound

    var localizedDescription: String {
        switch self {
        case .handlerNotFound:
            return "找不到对应的工具处理器"
        case .notInitialized:
            return "管理器未初始化"
        case .switchFailed(let message):
            return "切换失败: \(message)"
        case .toolNotFound(let id):
            return "工具未找到: \(id)"
        case .sourceNotFound(let id):
            return "镜像源未找到: \(id)"
        case .backupNotFound:
            return "备份文件不存在"
        case .backupNotSupported:
            return "该工具不支持备份"
        case .parseFailed(let message):
            return "解析失败: \(message)"
        case .commandExecutionFailed(let message):
            return "命令执行失败: \(message)"
        case .configNotFound:
            return "配置文件不存在"
        }
    }
}
