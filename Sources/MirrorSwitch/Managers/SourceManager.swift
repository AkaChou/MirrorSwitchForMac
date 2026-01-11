//
//  SourceManager.swift
//  MirrorSwitch
//
//  核心管理器，协调镜像源切换、配置管理和网络测速
//

import Foundation

/// 核心管理器（单例）
@MainActor
class SourceManager {
    /// 单例实例
    static let shared = SourceManager()

    /// 配置管理器
    private let configManager = ConfigManager.shared

    /// 网络测速器
    private let networkTester = NetworkTester()

    /// 应用配置
    private var config: AppConfiguration

    /// 各工具的处理器
    private var handlers: [ToolType: ToolHandlerProtocol]

    /// 是否已初始化
    private var isInitialized = false

    /// 私有初始化方法
    private init() {
        self.config = AppConfiguration.defaultConfig
        self.handlers = [
            .npm: NPMHandler(),
            .maven: MavenHandler(),
            .homebrew: HomebrewHandler(),
            .orbstack: OrbStackHandler()
        ]
    }

    // MARK: - Public Methods

    /// 初始化管理器
    func initialize() async {
        guard !isInitialized else { return }

        // 加载配置
        config = configManager.loadConfig()

        // 先尝试加载保存的选中状态
        loadCurrentSelection()

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
        guard let handler = handlers[tool] else {
            throw SourceManagerError.handlerNotFound
        }

        print("🔄 开始切换 \(tool.displayName) 镜像源...")

        // 执行切换
        try await handler.switchTo(source)

        // 保存选择
        configManager.saveCurrentSelection(tool: tool, sourceId: source.id)

        // 更新内存中的选中状态
        updateSelectionState(tool: tool, sourceId: source.id)

        print("✓ \(tool.displayName) 镜像源切换完成")
    }

    /// 测试指定工具的所有镜像源延迟
    func testSpeed(sources: [MirrorSource]) async {
        print("⚡️ 开始测速，共 \(sources.count) 个镜像源...")

        let tester = networkTester
        await withTaskGroup(of: (String, Int?).self) { group in
            for source in sources {
                group.addTask {
                    await tester.testSource(source)
                }
            }

            for await (sourceId, pingTime) in group {
                // 更新延迟时间到配置中
                updatePingTime(sourceId: sourceId, pingTime: pingTime)
            }
        }

        print("✓ 测速完成")
    }

    /// 获取指定工具的当前配置
    func getCurrentConfig(for tool: ToolType) async throws -> String {
        guard let handler = handlers[tool] else {
            throw SourceManagerError.handlerNotFound
        }

        return try await handler.getCurrentConfig()
    }

    /// 恢复指定工具的备份配置
    func restoreBackup(for tool: ToolType) async throws {
        guard let handler = handlers[tool] else {
            throw SourceManagerError.handlerNotFound
        }

        try await handler.restoreBackup()
    }

    // MARK: - Private Methods

    /// 加载当前选中状态
    private func loadCurrentSelection() {
        for tool in ToolType.allCases {
            if let sourceId = configManager.getCurrentSelection(for: tool) {
                updateSelectionState(tool: tool, sourceId: sourceId)
            }
        }
    }

    /// 检测当前实际使用的镜像源
    private func detectCurrentSources() async {
        for tool in ToolType.allCases {
            do {
                let currentConfig = try await getCurrentConfig(for: tool)

                // 查找匹配的镜像源
                if let matchingSource = findMatchingSource(for: tool, currentConfig: currentConfig) {
                    // 更新选中状态
                    updateSelectionState(tool: tool, sourceId: matchingSource.id)

                    // 保存选中状态到文件
                    configManager.saveCurrentSelection(tool: tool, sourceId: matchingSource.id)

                    print("✓ 检测到 \(tool.displayName) 当前使用: \(matchingSource.name)")
                }
            } catch {
                print("⚠️ 无法检测 \(tool.displayName) 当前配置: \(error.localizedDescription)")
            }
        }
    }

    /// 根据当前配置查找匹配的镜像源
    private func findMatchingSource(for tool: ToolType, currentConfig: String) -> MirrorSource? {
        let sources = getSources(for: tool)

        // 优先精确 URL 匹配
        for source in sources {
            if currentConfig.contains(source.url) {
                return source
            }
        }

        // 如果没有精确匹配，尝试域名匹配
        for source in sources {
            if let sourceDomain = extractDomain(from: source.url),
               let currentDomain = extractDomain(from: currentConfig),
               sourceDomain == currentDomain {
                return source
            }
        }

        return nil
    }

    /// 从 URL 中提取域名
    private func extractDomain(from url: String) -> String? {
        guard let url = URL(string: url) else { return nil }
        return url.host
    }

    /// 更新选中状态
    private func updateSelectionState(tool: ToolType, sourceId: String) {
        if var sources = config.tools[tool] {
            for index in sources.indices {
                sources[index].isSelected = (sources[index].id == sourceId)
            }
            config.tools[tool] = sources
        }
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

    var localizedDescription: String {
        switch self {
        case .handlerNotFound:
            return "找不到对应的工具处理器"
        case .notInitialized:
            return "管理器未初始化"
        case .switchFailed(let message):
            return "切换失败: \(message)"
        }
    }
}
