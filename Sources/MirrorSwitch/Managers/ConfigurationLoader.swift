//
//  ConfigurationLoader.swift
//  MirrorSwitch
//
//  配置加载器 - 支持远程 HTTP 加载、本地文件和内置配置
//  包含缓存机制、JSON Schema 验证和审计日志
//

import Foundation

/// 配置加载器
@MainActor
class ConfigurationLoader {
    /// 单例
    static let shared = ConfigurationLoader()

    // MARK: - 路径配置

    /// 用户配置目录
    private let configDirectory: URL

    /// 用户配置文件路径
    private let userConfigPath: URL

    /// 缓存目录
    private let cacheDirectory: URL

    /// 日志目录
    private let logsDirectory: URL

    /// 远程配置缓存路径
    private let remoteConfigCachePath: URL

    /// 远程配置元数据路径
    private let remoteConfigMetaPath: URL

    /// 审计日志路径
    private let auditLogPath: URL

    // MARK: - 配置

    /// 缓存过期时间（秒），默认 1 小时
    private let cacheExpiry: TimeInterval = 3600

    /// 启用缓存
    private let enableCache: Bool = true

    // MARK: - 初始化

    private init() {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        let appDir = homeDir.appendingPathComponent(".mirror-switch")

        // 配置目录
        self.configDirectory = appDir
        self.userConfigPath = appDir.appendingPathComponent("tools_config.json")

        // 缓存目录
        self.cacheDirectory = appDir.appendingPathComponent("cache")
        self.remoteConfigCachePath = cacheDirectory.appendingPathComponent("remote_config.json")
        self.remoteConfigMetaPath = cacheDirectory.appendingPathComponent("remote_config.meta")

        // 日志目录
        self.logsDirectory = appDir.appendingPathComponent("logs")
        self.auditLogPath = logsDirectory.appendingPathComponent("config_audit.log")

        // 确保目录存在
        createDirectoriesIfNeeded()

        // 检查环境变量，如果设置了远程配置 URL，自动添加到 ConfigSourceManager
        checkAndImportEnvConfig()
    }

    /// 检查环境变量并导入远程配置
    private func checkAndImportEnvConfig() {
        guard let urlString = ProcessInfo.processInfo.environment["MIRROR_SWITCH_CONFIG_URL"],
              URL(string: urlString) != nil else {
            return
        }

        // 检查是否已存在相同的远程配置
        let sources = ConfigSourceManager.shared.getAllSources()
        let alreadyExists = sources.contains { $0.type == .remote && $0.url == urlString }

        if !alreadyExists {
            let envConfig = ConfigSource(
                name: "环境变量配置",
                type: .remote,
                url: urlString,
                isEnabled: true
            )
            ConfigSourceManager.shared.addConfigSource(envConfig)
            print("✓ 已从环境变量导入远程配置: \(urlString)")
        }
    }

    // MARK: - 公共方法

    /// 加载配置（从 ConfigSourceManager 获取配置源）
    func loadConfiguration() async throws -> ToolsConfiguration {
        auditLog("CONFIG_LOAD_START", info: ["mode": "multi-source"])

        var mergedConfig: ToolsConfiguration?

        // 从 ConfigSourceManager 获取启用的配置源
        let enabledSources = ConfigSourceManager.shared.getEnabledSources()

        print("📋 已启用 \(enabledSources.count) 个配置源")

        // 按顺序加载每个配置源
        for source in enabledSources {
            do {
                let config = try await loadConfig(from: source)

                if let existing = mergedConfig {
                    // 合并配置
                    mergedConfig = mergeConfigurations(base: existing, user: config)
                    print("✓ 已加载配置: \(source.name) (合并)")
                } else {
                    // 第一个配置
                    mergedConfig = config
                    print("✓ 已加载配置: \(source.name)")
                }

                auditLog("CONFIG_LOADED", info: [
                    "source": source.name,
                    "type": source.type.rawValue,
                    "tools_count": config.tools.count
                ])
            } catch {
                auditLog("CONFIG_LOAD_FAILED", info: [
                    "source": source.name,
                    "type": source.type.rawValue,
                    "error": error.localizedDescription
                ])
                print("⚠️ 配置加载失败: \(source.name) - \(error.localizedDescription)")

                // 更新配置源状态为错误
                if source.type != .builtin {
                    ConfigSourceManager.shared.updateConfigSourceStatus(id: source.id, status: .error)
                }
            }
        }

        // 如果没有任何配置源成功加载，使用内置配置
        guard let finalConfig = mergedConfig else {
            print("⚠️ 所有配置源加载失败，使用内置配置")
            let builtinConfig = loadBuiltinConfiguration()
            auditLog("CONFIG_LOADED", info: ["source": "builtin_fallback", "tools_count": builtinConfig.tools.count])
            return builtinConfig
        }

        print("✓ 配置加载完成，共 \(finalConfig.tools.count) 个工具")
        return finalConfig
    }

    /// 从单个配置源加载配置
    private func loadConfig(from source: ConfigSource) async throws -> ToolsConfiguration {
        switch source.type {
        case .builtin:
            return loadBuiltinConfiguration()

        case .local:
            guard let path = source.url else {
                throw ConfigurationError.fileNotFound("本地配置路径为空")
            }
            // 展开波浪号
            let expandedPath = NSString(string: path).expandingTildeInPath
            debugLog("🔍 本地配置路径: \(path)")
            debugLog("🔍 展开后路径: \(expandedPath)")
            let url = URL(fileURLWithPath: expandedPath)
            debugLog("🔍 URL path: \(url.path)")
            debugLog("🔍 URL 绝对路径: \(url.absoluteString)")
            debugLog("🔍 文件存在: \(FileManager.default.fileExists(atPath: url.path))")
            return try loadLocalConfiguration(from: url)

        case .remote:
            guard let urlString = source.url else {
                throw ConfigurationError.fileNotFound("远程配置 URL 为空")
            }
            guard let url = URL(string: urlString) else {
                throw ConfigurationError.networkError(URLError(.badURL))
            }
            return try await loadRemoteConfiguration(from: url)
        }
    }

    /// 保存用户配置
    func saveUserConfiguration(_ config: ToolsConfiguration) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let data = try encoder.encode(config)

        // 确保目录存在
        try FileManager.default.createDirectory(at: configDirectory, withIntermediateDirectories: true)

        // 写入文件
        try data.write(to: userConfigPath)

        auditLog("CONFIG_SAVED", info: ["path": userConfigPath.path])
        print("✓ 用户配置已保存")
    }

    /// 重新加载配置（刷新所有配置源）
    func reloadConfiguration() async throws {
        // 重新加载所有配置源
        _ = try await loadConfiguration()

        // 验证所有远程和本地配置源
        let sources = ConfigSourceManager.shared.getAllSources()
        for source in sources where source.type != .builtin {
            _ = await ConfigSourceManager.shared.validateConfigSource(source)
        }

        auditLog("CONFIG_RELOADED", info: ["sources_count": sources.count])
        print("✓ 配置已重新加载")
    }

    // MARK: - 远程配置加载

    /// 加载远程配置（带缓存支持）
    private func loadRemoteConfiguration(from url: URL, skipCache: Bool = false) async throws -> ToolsConfiguration {
        // 检查缓存
        if !skipCache, enableCache, let cached = loadFromCache(), !cached.isExpired {
            print("✓ 使用缓存的远程配置")
            return cached.config
        }

        // 请求远程配置（支持 ETag）
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData

        // 添加 If-None-Match 头（如果缓存存在）
        if !skipCache, let meta = loadCacheMetadata(), let etag = meta.etag {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        // 检查是否为 304 Not Modified
        if let httpResponse = response as? HTTPURLResponse,
           httpResponse.statusCode == 304,
           let cached = loadFromCache() {
            print("✓ 远程配置未修改，使用缓存")
            return cached.config
        }

        // 验证配置
        try validateConfiguration(data)

        // 解析配置
        let decoder = JSONDecoder()
        let config = try decoder.decode(ToolsConfiguration.self, from: data)

        // 更新缓存
        if enableCache {
            saveToCache(config, data: data, response: response)
        }

        return config
    }

    // MARK: - 本地配置加载

    /// 加载本地配置文件
    private func loadLocalConfiguration(from url: URL) throws -> ToolsConfiguration {
        debugLog("📖 开始加载本地配置: \(url.path)")
        let data: Data
        do {
            data = try Data(contentsOf: url)
            debugLog("✅ 成功读取数据，大小: \(data.count) bytes")
        } catch {
            debugLog("❌ 读取数据失败: \(error.localizedDescription)")
            throw ConfigurationError.fileNotFound("无法读取配置文件: \(error.localizedDescription)")
        }

        // 验证配置
        try validateConfiguration(data)

        // 解析配置
        let decoder = JSONDecoder()
        return try decoder.decode(ToolsConfiguration.self, from: data)
    }

    // MARK: - 内置配置

    /// 加载内置默认配置
    func loadBuiltinConfiguration() -> ToolsConfiguration {
        // 从 Bundle 加载 npm_mirror.json
        do {
            if let bundleURL = Bundle.main.url(forResource: "npm_mirror", withExtension: "json", subdirectory: "configs") {
                let data = try Data(contentsOf: bundleURL)
                let decoder = JSONDecoder()
                let config = try decoder.decode(ToolsConfiguration.self, from: data)
                print("✅ 已从 Bundle 加载内置配置，共 \(config.tools.count) 个工具")
                return config
            } else if let bundleURL = Bundle.main.url(forResource: "npm_mirror", withExtension: "json") {
                let data = try Data(contentsOf: bundleURL)
                let decoder = JSONDecoder()
                let config = try decoder.decode(ToolsConfiguration.self, from: data)
                print("✅ 已从 Bundle 加载内置配置，共 \(config.tools.count) 个工具")
                return config
            }
        } catch {
            print("⚠️ 从 Bundle 加载配置失败: \(error.localizedDescription)")
        }

        // 如果 Bundle 加载失败，返回硬编码的 npm 配置（最小化配置）
        print("✓ 使用硬编码的最小化内置配置（仅 npm）")
        return ToolsConfiguration(
            version: "1.0.0",
            tools: loadMinimalTools()
        )
    }

    /// 加载最小化工具配置（仅 npm）
    private func loadMinimalTools() -> [ToolConfiguration] {
        // NPM
        let npm = ToolConfiguration(
            id: "npm",
            name: "NPM",
            description: "Node Package Manager",
            detection: DetectionConfiguration(
                command: "npm",
                arguments: ["--version"],
                customPaths: nil,
                fallbackDetection: nil
            ),
            sources: [
                SourceConfiguration(
                    id: "npm-official",
                    name: "官方源",
                    url: "https://registry.npmjs.org/",
                    description: "npm 官方源",
                    region: nil,
                    requiresAuth: nil,
                    auth: nil,
                    configSourceId: nil,
                    configSourceName: nil,
                    configSourceIsBuiltin: nil
                ),
                SourceConfiguration(
                    id: "npm-taobao",
                    name: "淘宝源",
                    url: "https://registry.npmmirror.com/",
                    description: "淘宝镜像",
                    region: "CN",
                    requiresAuth: nil,
                    auth: nil,
                    configSourceId: nil,
                    configSourceName: nil,
                    configSourceIsBuiltin: nil
                ),
                SourceConfiguration(
                    id: "npm-tencent",
                    name: "腾讯云",
                    url: "https://mirrors.cloud.tencent.com/npm/",
                    description: "腾讯云镜像",
                    region: "CN",
                    requiresAuth: nil,
                    auth: nil,
                    configSourceId: nil,
                    configSourceName: nil,
                    configSourceIsBuiltin: nil
                ),
                SourceConfiguration(
                    id: "npm-huawei",
                    name: "华为云",
                    url: "https://mirrors.huaweicloud.com/repository/npm/",
                    description: "华为云镜像",
                    region: "CN",
                    requiresAuth: nil,
                    auth: nil,
                    configSourceId: nil,
                    configSourceName: nil,
                    configSourceIsBuiltin: nil
                )
            ],
            strategy: .command(CommandStrategy(
                set: CommandSetConfiguration(
                    command: "npm",
                    arguments: ["config", "set", "registry", "{{url}}"],
                    environment: nil,
                    requiresAdmin: false,
                    workingDirectory: nil,
                    preCommands: nil,
                    timeout: 30
                ),
                get: CommandGetConfiguration(
                    command: "npm",
                    arguments: ["config", "get", "registry"],
                    outputParser: .trim,
                    timeout: 30
                )
            )),
            backup: BackupConfiguration(
                filePath: "~/.npmrc",
                backupFileName: ".npmrc.backup",
                backupOriginal: true,
                originalBackupSuffix: nil
            ),
            metadata: ToolMetadata(
                supportedPlatforms: ["macOS", "linux", "windows"],
                supportsSpeedTest: true,
                dependencies: nil,
                documentationURL: "https://docs.npmjs.com/"
            ),
            postActions: nil
        )

        return [npm]
    }

    // MARK: - 配置合并

    /// 合并配置
    private func mergeConfigurations(
        base: ToolsConfiguration,
        user: ToolsConfiguration
    ) -> ToolsConfiguration {
        var mergedTools = base.tools

        // 用户配置可以覆盖工具定义
        for userTool in user.tools {
            if let index = mergedTools.firstIndex(where: { $0.id == userTool.id }) {
                mergedTools[index] = userTool
            } else {
                mergedTools.append(userTool)
            }
        }

        return ToolsConfiguration(
            version: user.version,
            tools: mergedTools
        )
    }

    // MARK: - 配置验证

    /// 验证配置
    private func validateConfiguration(_ data: Data) throws {
        debugLog("🔍 开始验证配置...")
        let decoder = JSONDecoder()

        do {
            // 尝试解码，基本验证 JSON 结构
            debugLog("🔍 尝试解码 JSON...")
            let config = try decoder.decode(ToolsConfiguration.self, from: data)
            debugLog("✅ JSON 解码成功，工具数量: \(config.tools.count)")

            // 验证版本兼容性
            guard isVersionCompatible(config.version) else {
                debugLog("❌ 版本不兼容: \(config.version)")
                throw ConfigurationError.versionMismatch(config.version)
            }
            debugLog("✅ 版本验证通过: \(config.version)")

            // 验证每个工具的必需字段
            var errors: [String] = []
            for tool in config.tools {
                if let toolErrors = validateTool(tool) {
                    errors.append(contentsOf: toolErrors)
                }
            }

            if !errors.isEmpty {
                debugLog("❌ 工具验证失败: \(errors)")
                throw ConfigurationError.validationFailed(errors)
            }

            debugLog("✅ 配置验证通过")
        } catch let error as ConfigurationError {
            debugLog("❌ 配置错误: \(error.localizedDescription)")
            throw error
        } catch {
            debugLog("❌ 解析错误: \(error.localizedDescription)")
            throw ConfigurationError.parseFailed(error.localizedDescription)
        }
    }

    /// 验证版本兼容性
    private func isVersionCompatible(_ version: String) -> Bool {
        // 简单的版本检查，实际可以根据需要实现更复杂的逻辑
        return version.hasPrefix("1.")
    }

    /// 验证工具配置
    private func validateTool(_ tool: ToolConfiguration) -> [String]? {
        var errors: [String] = []

        // 验证 ID 格式
        let idPattern = "^[a-z][a-z0-9-]*$"
        if let regex = try? NSRegularExpression(pattern: idPattern),
           regex.firstMatch(in: tool.id, range: NSRange(tool.id.startIndex..., in: tool.id)) == nil {
            errors.append("工具 \(tool.name) 的 ID 格式不正确: \(tool.id)")
        }

        // 验证镜像源
        if tool.sources.isEmpty {
            errors.append("工具 \(tool.name) 必须至少有一个镜像源")
        }

        for source in tool.sources {
            if let url = URL(string: source.url), url.scheme == nil || url.host == nil {
                errors.append("工具 \(tool.name) 的镜像源 \(source.name) URL 格式不正确: \(source.url)")
            }
        }

        return errors.isEmpty ? nil : errors
    }

    // MARK: - 缓存管理

    /// 缓存元数据
    private struct CacheMetadata: Codable {
        let etag: String?
        let lastModified: Date
        let expiry: Date
        let version: String

        var isExpired: Bool {
            return Date() > expiry
        }
    }

    /// 缓存的配置
    private struct CachedConfiguration {
        let config: ToolsConfiguration
        let metadata: CacheMetadata

        var isExpired: Bool {
            return metadata.isExpired
        }
    }

    /// 从缓存加载
    private func loadFromCache() -> CachedConfiguration? {
        guard FileManager.default.fileExists(atPath: remoteConfigCachePath.path),
              FileManager.default.fileExists(atPath: remoteConfigMetaPath.path) else {
            return nil
        }

        do {
            // 读取元数据
            let metaData = try Data(contentsOf: remoteConfigMetaPath)
            let metadata = try JSONDecoder().decode(CacheMetadata.self, from: metaData)

            // 读取配置
            let configData = try Data(contentsOf: remoteConfigCachePath)
            let config = try JSONDecoder().decode(ToolsConfiguration.self, from: configData)

            return CachedConfiguration(config: config, metadata: metadata)
        } catch {
            print("⚠️ 缓存读取失败: \(error)")
            return nil
        }
    }

    /// 保存到缓存
    private func saveToCache(_ config: ToolsConfiguration, data: Data, response: URLResponse) {
        do {
            // 确保缓存目录存在
            try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)

            // 保存配置
            try data.write(to: remoteConfigCachePath)

            // 提取 ETag 和 Last-Modified
            var etag: String?
            var lastModified = Date()
            if let httpResponse = response as? HTTPURLResponse {
                etag = httpResponse.value(forHTTPHeaderField: "ETag")
                if let lastModifiedStr = httpResponse.value(forHTTPHeaderField: "Last-Modified") {
                    let formatter = DateFormatter()
                    formatter.locale = Locale(identifier: "en_US_POSIX")
                    formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
                    lastModified = formatter.date(from: lastModifiedStr) ?? Date()
                }
            }

            // 创建元数据
            let metadata = CacheMetadata(
                etag: etag,
                lastModified: lastModified,
                expiry: Date().addingTimeInterval(cacheExpiry),
                version: config.version
            )

            // 保存元数据
            let metaData = try JSONEncoder().encode(metadata)
            try metaData.write(to: remoteConfigMetaPath)

            print("✓ 配置已缓存")
        } catch {
            print("⚠️ 缓存保存失败: \(error)")
        }
    }

    /// 加载缓存元数据
    private func loadCacheMetadata() -> CacheMetadata? {
        guard FileManager.default.fileExists(atPath: remoteConfigMetaPath.path) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: remoteConfigMetaPath)
            return try JSONDecoder().decode(CacheMetadata.self, from: data)
        } catch {
            return nil
        }
    }

    // MARK: - 审计日志

    /// 记录审计日志
    private func auditLog(_ event: String, info: [String: Any] = [:]) {
        do {
            let timestamp = ISO8601DateFormatter().string(from: Date())
            var logEntry = "[\(timestamp)] \(event)"

            if !info.isEmpty {
                let infoString = info.map { "\($0.key)=\($0.value)" }.joined(separator: " ")
                logEntry += " \(infoString)"
            }

            // 确保日志目录存在
            try FileManager.default.createDirectory(at: logsDirectory, withIntermediateDirectories: true)

            // 追加到日志文件
            if let handle = FileHandle(forWritingAtPath: auditLogPath.path) {
                handle.seekToEndOfFile()
                if let data = (logEntry + "\n").data(using: .utf8) {
                    handle.write(data)
                }
                handle.closeFile()
            } else {
                try (logEntry + "\n").write(to: auditLogPath, atomically: true, encoding: .utf8)
            }
        } catch {
            print("⚠️ 审计日志写入失败: \(error)")
        }
    }

    // MARK: - 辅助方法

    /// 确保必要的目录存在
    private func createDirectoriesIfNeeded() {
        let directories = [configDirectory, cacheDirectory, logsDirectory]

        for directory in directories {
            if !FileManager.default.fileExists(atPath: directory.path) {
                try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            }
        }
    }
}
