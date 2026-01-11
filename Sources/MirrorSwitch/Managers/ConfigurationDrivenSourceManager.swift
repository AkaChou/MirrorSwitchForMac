//
//  ConfigurationDrivenSourceManager.swift
//  MirrorSwitch
//
//  配置驱动的核心管理器
//  替换原有的 SourceManager，使用配置驱动方式管理工具和镜像源
//

import Foundation

/// 配置驱动的源管理器
@MainActor
class ConfigurationDrivenSourceManager {
    /// 单例实例
    static let shared = ConfigurationDrivenSourceManager()

    // MARK: - 依赖

    /// 配置加载器
    private let configLoader = ConfigurationLoader.shared

    /// 策略执行器
    private let strategyExecutor = StrategyExecutor()

    /// 网络测速器
    private let networkTester = NetworkTester()

    // MARK: - 状态

    /// 工具配置
    private var toolsConfiguration: ToolsConfiguration?

    /// 缓存的工具列表
    private var cachedTools: [String: ToolConfiguration] = [:]

    /// 当前选中的镜像源
    private var currentSelection: [String: String] = [:]

    /// 是否已初始化
    private var isInitialized = false

    // MARK: - 配置管理器引用

    /// 配置管理器（用于保存选中状态）
    private let configManager = ConfigManager.shared

    // MARK: - 初始化

    private init() {}

    // MARK: - 公共方法

    /// 初始化管理器
    func initialize() async {
        guard !isInitialized else { return }

        print("🔄 正在初始化配置驱动管理器...")

        // 加载配置
        do {
            toolsConfiguration = try await configLoader.loadConfiguration()
            buildToolCache()
            print("✓ 配置加载成功，共 \(cachedTools.count) 个工具")
        } catch {
            print("⚠️ 配置加载失败: \(error.localizedDescription)")
            // 使用内置默认配置
            toolsConfiguration = configLoader.loadBuiltinConfiguration()
            buildToolCache()
            print("✓ 使用内置默认配置")
        }

        // 加载保存的选中状态
        loadCurrentSelection()

        // 检测当前实际使用的镜像源
        await detectCurrentSources()

        isInitialized = true
        print("✓ ConfigurationDrivenSourceManager 初始化完成")
    }

    /// 重新加载配置
    func reloadConfiguration() async throws {
        toolsConfiguration = try await configLoader.loadConfiguration()
        buildToolCache()

        // 重新检测当前配置
        await detectCurrentSources()

        print("✓ 配置已重新加载")
    }

    /// 获取所有工具配置
    func getAllTools() -> [ToolConfiguration] {
        return toolsConfiguration?.tools ?? []
    }

    /// 根据 ID 获取工具配置
    func getTool(by id: String) -> ToolConfiguration? {
        return cachedTools[id]
    }

    /// 获取工具的镜像源列表
    func getSources(for toolId: String) -> [MirrorSource] {
        guard let tool = cachedTools[toolId] else { return [] }

        // 将 SourceConfiguration 转换为 MirrorSource
        return tool.sources.map { source in
            MirrorSource(
                id: source.id,
                name: source.name,
                url: source.url,
                description: source.description,
                pingTime: getPingTime(for: source.id),
                isSelected: currentSelection[toolId] == source.id
            )
        }
    }

    /// 获取工具的镜像源列表（支持 ToolType）
    func getSources(for tool: ToolType) -> [MirrorSource] {
        return getSources(for: tool.rawValue)
    }

    /// 切换到指定镜像源
    func switchSource(toolId: String, sourceId: String) async throws {
        guard let toolConfig = cachedTools[toolId] else {
            throw SourceManagerError.toolNotFound(toolId)
        }

        guard let source = toolConfig.sources.first(where: { $0.id == sourceId }) else {
            throw SourceManagerError.sourceNotFound(sourceId)
        }

        print("🔄 开始切换 \(toolConfig.name) 镜像源: \(source.name)")

        // 执行策略
        try await strategyExecutor.execute(
            strategy: toolConfig.strategy,
            source: source,
            tool: toolConfig
        )

        // 保存选择
        currentSelection[toolId] = sourceId
        saveCurrentSelection(toolId: toolId, sourceId: sourceId)

        print("✓ \(toolConfig.name) 镜像源切换完成")
    }

    /// 切换到指定镜像源（支持 ToolType 和 MirrorSource）
    func switchSource(tool: ToolType, source: MirrorSource) async throws {
        try await switchSource(toolId: tool.rawValue, sourceId: source.id)
    }

    /// 获取当前配置
    func getCurrentConfig(for toolId: String) async throws -> String {
        guard let tool = cachedTools[toolId] else {
            throw SourceManagerError.toolNotFound(toolId)
        }

        return try await strategyExecutor.getCurrentConfig(
            strategy: tool.strategy,
            tool: tool
        )
    }

    /// 获取当前配置（支持 ToolType）
    func getCurrentConfig(for tool: ToolType) async throws -> String {
        return try await getCurrentConfig(for: tool.rawValue)
    }

    /// 获取当前选中的镜像源 ID
    func getCurrentSelection(toolId: String) -> String? {
        return currentSelection[toolId]
    }

    /// 备份配置
    func backupConfig(for toolId: String) async throws {
        guard let tool = cachedTools[toolId],
              let backup = tool.backup else {
            throw SourceManagerError.backupNotSupported
        }

        try await backupConfig(backup: backup, tool: tool)
    }

    /// 备份配置（支持 ToolType）
    func backupConfig(for tool: ToolType) async throws {
        try await backupConfig(for: tool.rawValue)
    }

    /// 恢复配置
    func restoreConfig(for toolId: String) async throws {
        print("🔍 [DEBUG] 尝试恢复配置，toolId: \(toolId)")
        print("🔍 [DEBUG] cachedTools keys: \(cachedTools.keys.sorted())")

        guard let tool = cachedTools[toolId] else {
            print("🔍 [DEBUG] 工具未找到: \(toolId)")
            throw SourceManagerError.toolNotFound(toolId)
        }

        print("🔍 [DEBUG] 工具已找到: \(tool.name), backup: \(tool.backup != nil ? "存在" : "nil")")

        guard let backup = tool.backup else {
            print("🔍 [DEBUG] 备份配置不存在")
            throw SourceManagerError.backupNotSupported
        }

        try await restoreConfig(backup: backup, tool: tool)

        // 恢复后重新检测当前使用的镜像源
        await detectCurrentSource(for: toolId)
    }

    /// 恢复配置（支持 ToolType）
    func restoreConfig(for tool: ToolType) async throws {
        try await restoreConfig(for: tool.rawValue)
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

    // MARK: - 私有方法

    /// 构建工具缓存
    private func buildToolCache() {
        cachedTools.removeAll()
        for tool in toolsConfiguration?.tools ?? [] {
            cachedTools[tool.id] = tool
        }
    }

    /// 加载当前选中状态
    private func loadCurrentSelection() {
        // 从 ConfigManager 加载保存的选中状态
        // 需要适配 ConfigManager 的接口
        for tool in cachedTools.values {
            // 尝试映射到旧的 ToolType
            if let toolType = ToolType(rawValue: tool.id) {
                if let sourceId = configManager.getCurrentSelection(for: toolType) {
                    currentSelection[tool.id] = sourceId
                }
            }
        }
    }

    /// 保存当前选中状态
    private func saveCurrentSelection(toolId: String, sourceId: String) {
        // 保存到 ConfigManager
        if let toolType = ToolType(rawValue: toolId) {
            configManager.saveCurrentSelection(tool: toolType, sourceId: sourceId)
        }

        // 也可以保存到新的配置文件
        // TODO: 实现新的选中状态保存机制
    }

    /// 检测当前实际使用的镜像源
    private func detectCurrentSources() async {
        for toolId in cachedTools.keys {
            await detectCurrentSource(for: toolId)
        }
    }

    /// 检测指定工具当前实际使用的镜像源
    func detectCurrentSource(for toolId: String) async {
        guard let tool = cachedTools[toolId] else { return }

        do {
            let currentConfig = try await getCurrentConfig(for: toolId)

            // 查找匹配的镜像源
            if let matchingSource = findMatchingSource(for: tool, currentConfig: currentConfig) {
                // 更新选中状态
                currentSelection[toolId] = matchingSource.id
                saveCurrentSelection(toolId: toolId, sourceId: matchingSource.id)

                print("✓ 检测到 \(tool.name) 当前使用: \(matchingSource.name)")
            } else {
                // 没有找到匹配的镜像源
                currentSelection.removeValue(forKey: toolId)
                if let toolType = ToolType(rawValue: toolId) {
                    configManager.clearCurrentSelection(tool: toolType)
                }
                print("✓ \(tool.name) 未配置或无法识别当前配置")
            }
        } catch {
            print("⚠️ 无法检测 \(tool.name) 当前配置: \(error.localizedDescription)")
        }
    }

    /// 根据当前配置查找匹配的镜像源
    private func findMatchingSource(for tool: ToolConfiguration, currentConfig: String) -> SourceConfiguration? {
        // 优先精确 URL 匹配
        for source in tool.sources {
            if currentConfig.contains(source.url) {
                return source
            }
        }

        // 如果没有精确匹配，尝试域名匹配
        for source in tool.sources {
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

    /// 更新延迟时间
    private func updatePingTime(sourceId: String, pingTime: Int?) {
        // 更新内存中的延迟时间
        // 注意：这不会持久化，需要重新从工具配置获取
        pingTimeCache[sourceId] = pingTime
    }

    /// 获取缓存的延迟时间
    private func getPingTime(for sourceId: String) -> Int? {
        return pingTimeCache[sourceId]
    }

    /// 延迟时间缓存
    private var pingTimeCache: [String: Int] = [:]

    // MARK: - 备份和恢复

    /// 备份配置
    private func backupConfig(backup: BackupConfiguration, tool: ToolConfiguration) async throws {
        let filePath = try await expandPath(backup.filePath, tool: tool)

        guard FileManager.default.fileExists(atPath: filePath) else {
            print("⚠️ 文件不存在，跳过备份: \(filePath)")
            return
        }

        let backupPath = BackupManager.shared.backupDirectory(
            for: ToolType(rawValue: tool.id) ?? .npm
        ).appendingPathComponent(backup.backupFileName)

        // 确保备份目录存在
        try FileManager.default.createDirectory(
            at: backupPath.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        // 删除旧备份
        if FileManager.default.fileExists(atPath: backupPath.path) {
            try FileManager.default.removeItem(at: backupPath)
        }

        // 复制文件
        try FileManager.default.copyItem(atPath: filePath, toPath: backupPath.path)

        print("✓ 配置已备份: \(backupPath.path)")
    }

    /// 恢复配置
    private func restoreConfig(backup: BackupConfiguration, tool: ToolConfiguration) async throws {
        let filePath = try await expandPath(backup.filePath, tool: tool)
        let backupDir = BackupManager.shared.backupDirectory(
            for: ToolType(rawValue: tool.id) ?? .npm
        )

        print("🔍 [DEBUG] 原始文件路径: \(filePath)")
        print("🔍 [DEBUG] 备份目录: \(backupDir.path)")

        // 尝试多种可能的备份文件名
        let possibleBackupNames = [
            backup.backupFileName,  // JSON 配置中指定的名称
            ((filePath as NSString).lastPathComponent + ".original"),  // 旧的 BackupManager 格式
            ("original_" + (filePath as NSString).lastPathComponent)  // 另一种可能的格式
        ]

        var actualBackupPath: URL?
        for backupName in possibleBackupNames {
            let path = backupDir.appendingPathComponent(backupName)
            print("🔍 [DEBUG] 检查备份文件: \(path.path), 存在: \(FileManager.default.fileExists(atPath: path.path))")
            if FileManager.default.fileExists(atPath: path.path) {
                actualBackupPath = path
                break
            }
        }

        guard let backupPath = actualBackupPath else {
            print("🔍 [DEBUG] 备份文件不存在，抛出 backupNotFound 错误")
            throw SourceManagerError.backupNotFound
        }

        print("🔍 [DEBUG] 找到备份文件: \(backupPath.path)")

        // 删除原文件
        if FileManager.default.fileExists(atPath: filePath) {
            try FileManager.default.removeItem(atPath: filePath)
        }

        // 确保目录存在
        let directory = (filePath as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(
            atPath: directory,
            withIntermediateDirectories: true
        )

        // 复制备份
        try FileManager.default.copyItem(atPath: backupPath.path, toPath: filePath)

        print("✓ 配置已恢复")
    }

    /// 展开路径（支持 ~ 和模板变量）
    private func expandPath(_ path: String, tool: ToolConfiguration) async throws -> String {
        // 1. 先展开 ~
        var expandedPath = (path as NSString).expandingTildeInPath

        // 2. 检查是否包含模板变量
        if !expandedPath.contains("{{") {
            return expandedPath
        }

        // 3. 执行 preCommands 捕获变量
        var context: [String: String] = [:]

        if case .command(let commandStrategy) = tool.strategy,
           let preCommands = commandStrategy.set.preCommands {
            for preCommand in preCommands {
                do {
                    let result = try await ShellExecutor.execute(
                        preCommand.command,
                        arguments: preCommand.arguments
                    )

                    // 解析输出
                    let output = parseOutput(
                        result.standardOutput,
                        parser: OutputParser(rawValue: preCommand.outputParser ?? "trim") ?? .trim
                    )

                    context[preCommand.captureAs] = output
                    print("🔍 [DEBUG] 捕获变量 \(preCommand.captureAs) = \(output)")
                } catch {
                    print("⚠️ [DEBUG] 执行 preCommand 失败: \(error.localizedDescription)")
                    // 继续执行，不中断
                }
            }
        }

        // 4. 使用 TemplateVariableParser 解析路径
        if !context.isEmpty {
            do {
                expandedPath = try TemplateVariableParser.parse(expandedPath, variables: context)
                print("🔍 [DEBUG] 路径解析: \(path) -> \(expandedPath)")
            } catch {
                print("⚠️ [DEBUG] 模板变量解析失败: \(error.localizedDescription)")
                // 如果解析失败，返回原路径
            }
        }

        return expandedPath
    }

    /// 解析命令输出
    private func parseOutput(_ output: String, parser: OutputParser) -> String {
        switch parser {
        case .trim:
            return output.trimmingCharacters(in: .whitespacesAndNewlines)
        case .extractUrl:
            // 从输出中提取 URL
            if let urlRange = output.range(of: "https?://[^\n]+", options: .regularExpression) {
                return String(output[urlRange])
            }
            return output.trimmingCharacters(in: .whitespacesAndNewlines)
        case .extractDomain:
            // 从输出中提取域名
            if let urlRange = output.range(of: "https?://[^/\n]+", options: .regularExpression) {
                let urlString = String(output[urlRange])
                if let url = URL(string: urlString) {
                    return url.host ?? urlString
                }
            }
            return output.trimmingCharacters(in: .whitespacesAndNewlines)
        case .firstLine:
            return output.components(separatedBy: .newlines).first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? output
        case .json:
            // JSON 解析（返回原始输出，稍后处理）
            return output.trimmingCharacters(in: .whitespacesAndNewlines)
        case .regex:
            // 正则表达式解析（返回原始输出，需要进一步处理）
            return output.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}

// MARK: - 错误扩展

extension SourceManagerError {
    enum ConfigurationError: Error {
        case toolNotFound(String)
        case sourceNotFound(String)
        case backupNotFound
        case backupNotSupported
    }
}
