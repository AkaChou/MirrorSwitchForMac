//
//  AppConfigurationLoader.swift
//  MirrorSwitch
//
//  Created by Haruko on 2025-01-11.
//

import Foundation

/// 应用配置加载器
/// 负责 app_config.json 和 ui_strings.json 的加载和管理
/// 支持远程配置加载、缓存机制和配置合并
actor AppConfigurationLoader {
    static let shared = AppConfigurationLoader()

    private var appConfig: AppConfiguration?
    private var uiStrings: UIStringsConfiguration?
    private var remoteConfigURL: URL?

    // MARK: - Bundle 访问

    /// 获取包含资源配置的 Bundle
    /// 对于 Swift Package Manager，资源通常在单独的 Bundle 中
    private var resourceBundle: Bundle {
        // 方法 1: 尝试从 Bundle.allBundles 中查找
        for bundle in Bundle.allBundles {
            let bundlePath = bundle.bundlePath
            // 查找包含 "MirrorSwitch" 且以 ".bundle" 结尾的路径
            if bundlePath.contains("MirrorSwitch") && bundlePath.hasSuffix(".bundle") {
                print("✅ 找到资源 Bundle (allBundles): \(bundlePath)")
                return bundle
            }
        }

        // 方法 2: 尝试从 Bundle.main 的资源目录中查找
        if let resourcePath = Bundle.main.resourcePath,
           let resourceContents = try? FileManager.default.contentsOfDirectory(atPath: resourcePath) {
            // 查找 MirrorSwitch_MirrorSwitch.bundle 目录
            if let bundleName = resourceContents.first(where: { $0.hasSuffix("MirrorSwitch.bundle") }) {
                let bundlePath = resourcePath + "/" + bundleName
                if let bundle = Bundle(path: bundlePath) {
                    print("✅ 找到资源 Bundle (手动创建): \(bundlePath)")
                    return bundle
                }
            }
        }

        // 如果找不到，使用 Bundle.main（虽然对于 SPM 可执行目标通常不会成功）
        print("⚠️ 未找到资源 Bundle，使用 Bundle.main")
        return Bundle.main
    }

    // MARK: - 缓存目录

    private var cacheDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".mirror-switch")
            .appendingPathComponent("cache")
    }

    private var metadataFile: URL {
        cacheDirectory.appendingPathComponent("remote_config.meta")
    }

    private init() {
        // 确保缓存目录存在（在 init 中直接计算路径）
        let cacheDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".mirror-switch")
            .appendingPathComponent("cache")
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    }

    // MARK: - 缓存元数据

    /// 远程配置缓存元数据
    struct CacheMetadata: Codable {
        let etag: String?
        let lastModified: String?
        let expiryDate: Date
        let cachedAt: Date
        let url: String

        /// 检查缓存是否过期
        var isExpired: Bool {
            Date() > expiryDate
        }
    }

    // MARK: - 配置加载

    /// 加载应用配置
    /// - Returns: 应用配置
    func loadAppConfiguration() throws -> AppConfiguration {
        if let cached = appConfig {
            return cached
        }

        let config = try loadAppConfigurationFromBundle()
        appConfig = config
        return config
    }

    /// 加载 UI 字符串配置
    /// - Returns: UI 字符串配置
    func loadUIStrings() throws -> UIStringsConfiguration {
        if let cached = uiStrings {
            return cached
        }

        let strings = try loadUIStringsFromBundle()
        uiStrings = strings
        return strings
    }

    /// 从 Bundle 加载应用配置
    private func loadAppConfigurationFromBundle() throws -> AppConfiguration {
        // 尝试多种路径
        var bundleURL: URL?

        // 方式 1: 使用 subdirectory
        bundleURL = resourceBundle.url(forResource: "app_config", withExtension: "json", subdirectory: "configs")

        // 方式 2: 不使用 subdirectory
        if bundleURL == nil {
            bundleURL = resourceBundle.url(forResource: "app_config", withExtension: "json")
        }

        guard let url = bundleURL else {
            print("❌ 无法在 Bundle 中找到 app_config.json")
            print("🔍 Bundle 路径: \(resourceBundle.bundlePath)")
            // 列出 Bundle 中的所有资源用于调试
            if let resourcePath = resourceBundle.resourcePath {
                let resourceContents = try? FileManager.default.contentsOfDirectory(atPath: resourcePath)
                print("🔍 Bundle 资源: \(resourceContents?.joined(separator: ", ") ?? "无")")
            }
            throw ConfigError.fileNotFound("app_config.json")
        }

        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        do {
            let config = try decoder.decode(AppConfiguration.self, from: data)
            print("✅ 应用配置加载成功 (从 Bundle: \(url.lastPathComponent))")
            return config
        } catch {
            print("❌ 应用配置解析失败: \(error)")
            throw ConfigError.parseFailed(error.localizedDescription)
        }
    }

    /// 从 Bundle 加载 UI 字符串配置
    private func loadUIStringsFromBundle() throws -> UIStringsConfiguration {
        // 尝试多种路径
        var bundleURL: URL?

        // 方式 1: 使用 subdirectory
        bundleURL = resourceBundle.url(forResource: "ui_strings", withExtension: "json", subdirectory: "configs")

        // 方式 2: 不使用 subdirectory
        if bundleURL == nil {
            bundleURL = resourceBundle.url(forResource: "ui_strings", withExtension: "json")
        }

        guard let url = bundleURL else {
            print("❌ 无法在 Bundle 中找到 ui_strings.json")
            throw ConfigError.fileNotFound("ui_strings.json")
        }

        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        do {
            let strings = try decoder.decode(UIStringsConfiguration.self, from: data)
            print("✅ UI 字符串配置加载成功 (从 Bundle: \(url.lastPathComponent))")
            return strings
        } catch {
            print("❌ UI 字符串配置解析失败: \(error)")
            throw ConfigError.parseFailed(error.localizedDescription)
        }
    }

    /// 从远程加载应用配置（带缓存和 ETag 支持）
    /// - Parameters:
    ///   - useCache: 是否使用缓存（默认 true）
    ///   - cacheExpiry: 缓存过期时间（秒，默认 3600 = 1 小时）
    /// - Returns: 应用配置
    func loadRemoteAppConfiguration(useCache: Bool = true, cacheExpiry: Int = 3600) async throws -> AppConfiguration {
        guard let remoteURL = remoteConfigURL else {
            throw ConfigError.remoteConfigNotEnabled
        }

        let url = remoteURL.appendingPathComponent("app_config.json")
        let cacheFile = cacheDirectory.appendingPathComponent("app_config.json")

        // 1. 尝试使用缓存
        if useCache {
            if let cached = loadFromCache(file: cacheFile) {
                if !cached.isExpired {
                    print("✅ 使用缓存的配置（过期时间: \(cached.expiryDate)）")
                    return try loadCachedConfig(from: cacheFile)
                } else {
                    print("⚠️ 缓存已过期，尝试从远程获取新配置")
                }
            }
        }

        // 2. 从远程获取（带 ETag 支持）
        var request = URLRequest(url: url)

        // 如果有缓存的 ETag，添加 If-None-Match 头
        if let metadata = loadMetadata(),
           let etag = metadata.etag {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
            print("📡 添加 ETag: \(etag)")
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        // 检查是否是 304 Not Modified（配置未变化）
        if let httpResponse = response as? HTTPURLResponse,
           httpResponse.statusCode == 304 {
            print("✅ 配置未变化，使用缓存")
            return try loadCachedConfig(from: cacheFile)
        }

        // 3. 解析新配置
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        let config = try decoder.decode(AppConfiguration.self, from: data)
        print("✅ 远程应用配置加载成功")

        // 4. 保存到本地缓存
        try saveToCache(data: data, filename: "app_config.json")

        // 5. 保存缓存元数据
        if let httpResponse = response as? HTTPURLResponse {
            let etag = httpResponse.value(forHTTPHeaderField: "ETag")
            let lastModified = httpResponse.value(forHTTPHeaderField: "Last-Modified")

            let metadata = CacheMetadata(
                etag: etag,
                lastModified: lastModified,
                expiryDate: Date().addingTimeInterval(TimeInterval(cacheExpiry)),
                cachedAt: Date(),
                url: url.absoluteString
            )

            saveMetadata(metadata)
        }

        return config
    }

    /// 从本地缓存加载配置
    private func loadCachedConfig(from file: URL) throws -> AppConfiguration {
        let data = try Data(contentsOf: file)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(AppConfiguration.self, from: data)
    }

    // MARK: - 配置缓存

    /// 加载缓存元数据
    private func loadMetadata() -> CacheMetadata? {
        guard FileManager.default.fileExists(atPath: metadataFile.path),
              let data = try? Data(contentsOf: metadataFile) else {
            return nil
        }

        return try? JSONDecoder().decode(CacheMetadata.self, from: data)
    }

    /// 保存缓存元数据
    private func saveMetadata(_ metadata: CacheMetadata) {
        if let data = try? JSONEncoder().encode(metadata) {
            try? data.write(to: metadataFile)
            print("✅ 缓存元数据已保存")
        }
    }

    /// 从缓存文件加载元数据
    private func loadFromCache(file: URL) -> CacheMetadata? {
        guard let metadata = loadMetadata() else {
            return nil
        }

        // 检查缓存文件是否存在
        guard FileManager.default.fileExists(atPath: file.path) else {
            return nil
        }

        return metadata
    }

    /// 保存配置到本地缓存
    private func saveToCache(data: Data, filename: String) throws {
        let cacheURL = cacheDirectory.appendingPathComponent(filename)
        try data.write(to: cacheURL)
        print("✅ 配置已缓存: \(filename)")
    }

    // MARK: - 配置管理

    /// 设置远程配置 URL
    func setRemoteConfigURL(_ url: String?) {
        remoteConfigURL = url.flatMap { URL(string: $0) }
        print("📡 远程配置 URL 已设置: \(url ?? "nil")")
    }

    /// 清除缓存的配置
    func clearCache() {
        appConfig = nil
        uiStrings = nil
        print("🗑️ 配置缓存已清除")
    }

    /// 重新加载所有配置（支持远程、内置配置的优先级）
    /// 注意：app_config.json 只从 Bundle 或远程加载，不从用户目录加载
    /// - Parameters:
    ///   - useRemote: 是否尝试加载远程配置（默认 true）
    ///   - cacheExpiry: 缓存过期时间（秒）
    /// - Returns: (应用配置, UI 字符串配置)
    func reload(useRemote: Bool = true, cacheExpiry: Int = 3600) async throws -> (appConfig: AppConfiguration, uiStrings: UIStringsConfiguration) {
        clearCache()

        var finalConfig: AppConfiguration?

        // 1. 尝试加载远程配置（最高优先级）
        if useRemote && remoteConfigURL != nil {
            do {
                let remoteConfig = try await loadRemoteAppConfiguration(useCache: true, cacheExpiry: cacheExpiry)
                finalConfig = remoteConfig
                print("📡 已使用远程 app_config")
            } catch {
                print("⚠️ 远程配置加载失败: \(error.localizedDescription)")
            }
        }

        // 2. 使用内置默认配置（从 Bundle 加载）
        if finalConfig == nil {
            finalConfig = try loadAppConfiguration()
            print("📦 已使用内置 app_config（从 Bundle）")
        }

        guard let config = finalConfig else {
            throw ConfigError.fileNotFound("无法加载 app_config")
        }

        appConfig = config
        let strings = try loadUIStrings()

        return (config, strings)
    }

    // MARK: - 字符串格式化

    /// 格式化字符串（替换占位符）
    func formatString(_ template: String, variables: [String: String]) -> String {
        var result = template
        for (key, value) in variables {
            result = result.replacingOccurrences(of: "{\(key)}", with: value)
        }
        return result
    }

    // MARK: - 错误定义

    enum ConfigError: Error, LocalizedError {
        case fileNotFound(String)
        case parseFailed(String)
        case remoteConfigNotEnabled
        case networkError(String)
        case validationFailed(String)

        var errorDescription: String? {
            switch self {
            case .fileNotFound(let path):
                return "配置文件未找到: \(path)"
            case .parseFailed(let message):
                return "配置解析失败: \(message)"
            case .remoteConfigNotEnabled:
                return "远程配置未启用"
            case .networkError(let message):
                return "网络错误: \(message)"
            case .validationFailed(let message):
                return "配置验证失败: \(message)"
            }
        }
    }
}
