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

    /// 镜像源到配置源的映射
    private var sourceToConfigSource: [String: (configSourceId: String, configSourceName: String)] =
        [:]

    /// 镜像源可见性设置
    private var sourceVisibility: [String: Bool] = [:]

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

        await withTaskGroup(of: Void.self) { group in
            // 1. 加载配置
            group.addTask {
                await self.loadAndCacheConfiguration()
            }

            // 2. 加载可见性设置
            group.addTask {
                await self.loadSourceVisibility()
            }
        }

        // 3. 加载选中状态 (依赖工具缓存，需在配置加载后执行)
        loadCurrentSelection()

        // 4. 检测当前实际使用的镜像源
        await detectCurrentSources()

        isInitialized = true
        print("✓ ConfigurationDrivenSourceManager 初始化完成")
    }

    private func loadAndCacheConfiguration() async {
        do {
            toolsConfiguration = try await configLoader.loadConfiguration()
            buildToolCache()
            print("✓ 配置加载成功，共 \(cachedTools.count) 个工具")
        } catch {
            print("⚠️ 配置加载失败: \(error.localizedDescription)")
            // 使用内置默认配置
            toolsConfiguration = await configLoader.loadBuiltinConfiguration()
            buildToolCache()
            print("✓ 使用内置默认配置")
        }
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

    // MARK: - 配置源分组工具获取

    /// 获取按配置源分组的工具列表
    /// - Returns: [(ConfigSource, [ToolConfiguration])] - 配置源与其包含的工具
    func getToolsGroupedByConfigSource() async -> [(ConfigSource, [ToolConfiguration])] {
        // 获取启用的配置源
        let enabledSources = ConfigSourceManager.shared.getEnabledSources()

        // 直接从缓存中获取所有工具，并按配置源分组
        var groupedTools: [String: [ToolConfiguration]] = [:]

        for tool in cachedTools.values {
            if let sourceId = tool.configSourceId {
                groupedTools[sourceId, default: []].append(tool)
            }
        }

        // 按配置源顺序构建结果
        var results: [(ConfigSource, [ToolConfiguration])] = []
        for source in enabledSources {
            if let tools = groupedTools[source.id.uuidString] {
                // 对工具按名称排序，保证显示顺序一致
                let sortedTools = tools.sorted { $0.name < $1.name }
                results.append((source, sortedTools))
            }
        }

        return results
    }

    /// 获取指定配置源的工具列表
    /// - Parameter configSourceId: 配置源 ID
    /// - Returns: 该配置源包含的工具列表，如果未找到返回 nil
    func getTools(forConfigSource configSourceId: UUID) async -> [ToolConfiguration]? {
        // 获取启用的配置源
        let enabledSources = ConfigSourceManager.shared.getEnabledSources()

        // 查找指定的配置源
        guard let source = enabledSources.first(where: { $0.id == configSourceId }) else {
            return nil
        }

        // 从该配置源加载工具
        return await loadToolsFromConfigSource(source)
    }

    /// 从单个配置源加载工具列表（不去重）
    /// - Parameter source: 配置源
    /// - Returns: 工具配置列表
    private func loadToolsFromConfigSource(_ source: ConfigSource) async -> [ToolConfiguration]? {
        // 根据配置源类型加载
        switch source.type {
        case .builtin:
            // 内置配置：尝试从 Bundle 加载
            if let config = await loadBuiltinToolsConfig() {
                return annotateToolsWithConfigSource(tools: config.tools, source: source)
            }

            // Bundle 加载失败，使用硬编码的最小化配置作为后备
            debugLog("⚠️ Bundle 加载失败，使用硬编码的最小化内置配置（仅 npm）")
            let fallbackConfig = await configLoader.loadBuiltinConfiguration()
            return annotateToolsWithConfigSource(tools: fallbackConfig.tools, source: source)

        case .local:
            // 本地文件：从文件路径加载
            guard let path = source.url else { return nil }
            let expandedPath = NSString(string: path).expandingTildeInPath
            let url = URL(fileURLWithPath: expandedPath)

            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                let config = try JSONDecoder().decode(ToolsConfiguration.self, from: data)
                return annotateToolsWithConfigSource(tools: config.tools, source: source)
            } catch {
                debugLog("❌ 加载本地工具配置失败: \(error.localizedDescription)")
                return nil
            }

        case .remote:
            // 远程配置：暂时跳过（需要异步加载）
            // TODO: 远程配置需要异步加载，这里暂时返回 nil
            return nil
        }
    }

    /// 为工具及其镜像源标记配置源信息
    /// - Parameters:
    ///   - tools: 工具配置列表
    ///   - source: 配置源
    /// - Returns: 标记后的工具配置列表
    private func annotateToolsWithConfigSource(
        tools: [ToolConfiguration],
        source: ConfigSource
    ) -> [ToolConfiguration] {
        let sourceId = source.id.uuidString
        let isBuiltin = (source.type == .builtin)

        return tools.map { tool in
            // 为每个镜像源添加配置源信息，并重写 ID 以确保唯一性
            let annotatedSources = tool.sources.map { sourceConfig -> SourceConfiguration in
                // 先更新配置源信息
                var newSource = sourceConfig.withConfigSource(
                    configSourceId: sourceId,
                    configSourceName: source.name,
                    configSourceIsBuiltin: isBuiltin
                )

                // 重写镜像源 ID (配置源ID_原ID)
                // 注意：这里需要 SourceConfiguration.id 是可变的或有方法修改
                // 暂时假设我们通过新建实例修改，或者稍后修改模型
                // 由于 SourceConfiguration 是不可变的 struct，我们需要如果它是 let id，需要修改模型
                // 假设我们已经修改了模型让 id 是 var
                newSource.id = "\(sourceId)_\(sourceConfig.id)"
                return newSource
            }

            // 创建带有新镜像源列表的工具副本
            var newTool = tool.withSources(annotatedSources)

            // 重写工具 ID
            newTool.originalId = tool.id
            newTool.configSourceId = sourceId
            newTool.id = "\(sourceId)_\(tool.id)"

            return newTool
        }
    }

    /// 加载内置配置的工具部分（单独方法）
    /// - Returns: 工具配置
    private func loadBuiltinToolsConfig() async -> ToolsConfiguration? {
        // 从 Bundle 中加载内置配置
        // 注意：这里假设内置配置文件名为 npm_mirror.json
        return await Task {
            guard
                let url = Bundle.main.url(
                    forResource: "npm_mirror", withExtension: "json", subdirectory: "configs"),
                let data = try? Data(contentsOf: url),
                let config = try? JSONDecoder().decode(ToolsConfiguration.self, from: data)
            else {
                return nil
            }
            return config
        }.value
    }

    // MARK: - 旧方法（向后兼容）

    /// 根据 ID 获取工具配置
    func getTool(by id: String) -> ToolConfiguration? {
        return cachedTools[id]
    }

    /// 获取工具的镜像源列表
    func getSources(for toolId: String) -> [MirrorSource] {
        guard let tool = cachedTools[toolId] else { return [] }

        // 将 SourceConfiguration 转换为 MirrorSource，并过滤不可见的源
        return tool.sources
            .map { source in
                // 获取镜像源的配置源信息
                let configSourceInfo = getConfigSourceInfo(for: source.id)

                return MirrorSource(
                    id: source.id,
                    name: source.name,
                    url: source.url,
                    description: source.description,
                    pingTime: getPingTime(for: source.id),
                    isSelected: currentSelection[toolId] == source.id,
                    configSourceId: configSourceInfo?.0,
                    configSourceName: configSourceInfo?.1,
                    isVisible: isSourceVisible(sourceId: source.id)
                )
            }
            .filter { $0.isVisible }  // 只返回可见的镜像源
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

    /// 切换到指定镜像源（支持 toolId 和 MirrorSource）
    func switchSource(toolId: String, source: MirrorSource) async throws {
        try await switchSource(toolId: toolId, sourceId: source.id)
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
            let backup = tool.backup
        else {
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

        // 恢复后清除当前选择状态（重置为默认配置不应该自动匹配任何镜像源）
        currentSelection.removeValue(forKey: toolId)
        if let toolType = ToolType(rawValue: toolId) {
            configManager.clearCurrentSelection(tool: toolType)
        }
        print("✓ \(tool.name) 已恢复默认配置，清除镜像源选择状态")
    }

    /// 恢复配置（支持 ToolType）
    func restoreConfig(for tool: ToolType) async throws {
        try await restoreConfig(for: tool.rawValue)
    }

    /// 测试指定工具的所有镜像源延迟
    func testSpeed(sources: [MirrorSource], onUpdate: ((String, Int?) -> Void)? = nil) async {
        print("⚡️ 开始测速，共 \(sources.count) 个镜像源...")

        await withTaskGroup(of: (String, Int?).self) { group in
            for source in sources {
                group.addTask {
                    await self.networkTester.testSource(source)
                }
            }

            for await (sourceId, pingTime) in group {
                updatePingTime(sourceId: sourceId, pingTime: pingTime)
                // 收到结果后立即回调
                onUpdate?(sourceId, pingTime)
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
        let selections = configManager.getAllSelections()

        for tool in cachedTools.values {
            // 尝试直接通过 ID 获取
            if let sourceId = selections[tool.id] {
                currentSelection[tool.id] = sourceId
            }
            // 尝试映射到旧的 ToolType (为了兼容)
            else if let toolType = ToolType(rawValue: tool.id),
                let sourceId = selections[toolType.rawValue]
            {
                currentSelection[tool.id] = sourceId
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
        await withTaskGroup(of: Void.self) { group in
            for toolId in cachedTools.keys {
                group.addTask {
                    await self.detectCurrentSource(for: toolId)
                }
            }
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
    private func findMatchingSource(for tool: ToolConfiguration, currentConfig: String)
        -> SourceConfiguration?
    {
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
                sourceDomain == currentDomain
            {
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
            for: tool.id
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
            for: tool.id
        )

        print("🔍 [DEBUG] 原始文件路径: \(filePath)")
        print("🔍 [DEBUG] 备份目录: \(backupDir.path)")

        // 尝试多种可能的备份文件名
        let possibleBackupNames = [
            backup.backupFileName,  // JSON 配置中指定的名称
            ((filePath as NSString).lastPathComponent + ".original"),  // 旧的 BackupManager 格式
            ("original_" + (filePath as NSString).lastPathComponent),  // 另一种可能的格式
        ]

        var actualBackupPath: URL?
        for backupName in possibleBackupNames {
            let path = backupDir.appendingPathComponent(backupName)
            print(
                "🔍 [DEBUG] 检查备份文件: \(path.path), 存在: \(FileManager.default.fileExists(atPath: path.path))"
            )
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
            let preCommands = commandStrategy.set.preCommands
        {
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

    /// 获取镜像源所属的配置源信息
    /// - Parameter sourceId: 镜像源 ID
    /// - Returns: (配置源 ID, 配置源名称)
    private func getConfigSourceInfo(for sourceId: String) -> (String, String)? {
        return sourceToConfigSource[sourceId]
    }

    /// 检查镜像源是否可见
    /// - Parameter sourceId: 镜像源 ID
    /// - Returns: 是否可见（默认可见）
    private func isSourceVisible(sourceId: String) -> Bool {
        return sourceVisibility[sourceId] ?? true
    }

    /// 设置镜像源可见性
    /// - Parameters:
    ///   - sourceId: 镜像源 ID
    ///   - isVisible: 是否可见
    func setSourceVisibility(sourceId: String, isVisible: Bool) {
        sourceVisibility[sourceId] = isVisible
        saveSourceVisibility()
    }

    /// 保存镜像源可见性设置
    private func saveSourceVisibility() {
        // 保存到配置文件
        if let data = try? JSONEncoder().encode(sourceVisibility) {
            let filePath = getConfigSourceVisibilityFilePath()
            do {
                try data.write(to: filePath)
                debugLog("✓ 镜像源可见性已保存")
            } catch {
                print("⚠️ 镜像源可见性保存失败: \(error.localizedDescription)")
            }
        }
    }

    /// 加载镜像源可见性设置
    private func loadSourceVisibility() async {
        let filePath = getConfigSourceVisibilityFilePath()
        guard FileManager.default.fileExists(atPath: filePath.path) else {
            return
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: filePath)
            if let visibility = try? JSONDecoder().decode([String: Bool].self, from: data) {
                sourceVisibility = visibility
                debugLog("✓ 镜像源可见性已加载")
            }
        } catch {
            print("⚠️ 镜像源可见性加载失败: \(error.localizedDescription)")
        }
    }

    /// 获取镜像源可见性配置文件路径
    private func getConfigSourceVisibilityFilePath() -> URL {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        let appDirectory = homeDir.appendingPathComponent(".mirror-switch")
        return appDirectory.appendingPathComponent("source_visibility.json")
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
            return output.components(separatedBy: .newlines).first?.trimmingCharacters(
                in: .whitespacesAndNewlines) ?? output
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
