//
//  ConfigSourceManager.swift
//  MirrorSwitch
//
//  配置源管理器
//  负责管理配置源的增删改查和持久化
//

import Foundation

/// 配置源管理器
@MainActor
class ConfigSourceManager {
    /// 单例
    static let shared = ConfigSourceManager()

    // MARK: - 属性

    /// 配置源列表
    private var configSources: [ConfigSource] = []

    /// 配置文件路径
    private let configFilePath: URL

    /// 文件管理器
    private let fileManager = FileManager.default

    // MARK: - 初始化

    private init() {
        // 配置文件路径：~/.mirror-switch/config_sources.json
        let homeDir = fileManager.homeDirectoryForCurrentUser
        let appDir = homeDir.appendingPathComponent(".mirror-switch")
        self.configFilePath = appDir.appendingPathComponent("config_sources.json")

        // 确保目录存在
        try? fileManager.createDirectory(at: appDir, withIntermediateDirectories: true)

        // 加载配置源
        loadConfigSources()
    }

    // MARK: - 公共方法

    /// 获取所有配置源
    func getAllSources() -> [ConfigSource] {
        return configSources
    }

    /// 获取启用的配置源（按类型排序：builtin > local > remote）
    func getEnabledSources() -> [ConfigSource] {
        return configSources
            .filter { $0.isEnabled }
            .sorted { lhs, rhs in
                // 内置配置优先级最高
                if lhs.type == .builtin && rhs.type != .builtin {
                    return true
                } else if lhs.type != .builtin && rhs.type == .builtin {
                    return false
                }
                // 同类型按创建时间排序
                return lhs.createdAt < rhs.createdAt
            }
    }

    /// 添加配置源
    func addConfigSource(_ source: ConfigSource) {
        // 检查是否已存在同名配置
        if configSources.contains(where: { $0.name == source.name && $0.type == source.type }) {
            print("⚠️ 配置源已存在: \(source.name)")
            return
        }

        configSources.append(source)
        saveConfigSources()
        print("✅ 已添加配置源: \(source.name)")
    }

    /// 删除配置源
    func removeConfigSource(id: UUID) {
        // 不允许删除内置配置
        guard let source = configSources.first(where: { $0.id == id }),
              source.type != .builtin else {
            print("⚠️ 不允许删除内置配置")
            return
        }

        configSources.removeAll { $0.id == id }
        saveConfigSources()
        print("✅ 已删除配置源")
    }

    /// 切换配置源启用状态
    func toggleConfigSource(id: UUID) {
        // 内置配置始终启用
        guard let index = configSources.firstIndex(where: { $0.id == id }),
              configSources[index].type != .builtin else {
            return
        }

        configSources[index].isEnabled.toggle()
        saveConfigSources()
    }

    /// 更新配置源状态
    func updateConfigSourceStatus(id: UUID, status: ConfigStatus) {
        guard let index = configSources.firstIndex(where: { $0.id == id }) else {
            return
        }

        configSources[index].status = status
        if status == .valid {
            configSources[index].lastUpdated = Date()
        }
        saveConfigSources()
    }

    /// 更新配置源
    func updateConfigSource(_ source: ConfigSource) {
        guard let index = configSources.firstIndex(where: { $0.id == source.id }) else {
            return
        }

        // 不允许修改内置配置的类型和 URL
        if configSources[index].type == .builtin {
            configSources[index].name = source.name
            configSources[index].isEnabled = source.isEnabled
        } else {
            configSources[index] = source
        }

        saveConfigSources()
    }

    /// 验证配置源
    func validateConfigSource(_ source: ConfigSource) async -> Bool {
        guard source.type != .builtin, let urlString = source.url else {
            return true
        }

        // 更新状态为加载中
        updateConfigSourceStatus(id: source.id, status: .loading)

        do {
            if source.type == .remote {
                // 验证远程 URL
                guard let url = URL(string: urlString) else {
                    updateConfigSourceStatus(id: source.id, status: .error)
                    return false
                }

                let (_, response) = try await URLSession.shared.data(from: url)

                if let httpResponse = response as? HTTPURLResponse,
                   httpResponse.statusCode == 200 {
                    updateConfigSourceStatus(id: source.id, status: .valid)
                    return true
                } else {
                    updateConfigSourceStatus(id: source.id, status: .error)
                    return false
                }
            } else {
                // 验证本地文件
                let url = URL(fileURLWithPath: urlString)
                let fileExists = fileManager.fileExists(atPath: url.path)

                let status: ConfigStatus = fileExists ? .valid : .error
                updateConfigSourceStatus(id: source.id, status: status)
                return fileExists
            }
        } catch {
            updateConfigSourceStatus(id: source.id, status: .error)
            print("⚠️ 配置源验证失败: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - 私有方法

    /// 加载配置源
    private func loadConfigSources() {
        // 检查文件是否存在
        guard fileManager.fileExists(atPath: configFilePath.path) else {
            // 文件不存在，创建默认配置
            createDefaultSources()
            return
        }

        do {
            let data = try Data(contentsOf: configFilePath)
            let decoder = JSONDecoder()
            configSources = try decoder.decode([ConfigSource].self, from: data)
            print("✅ 已加载 \(configSources.count) 个配置源")
        } catch {
            print("⚠️ 配置源加载失败: \(error.localizedDescription)")
            // 加载失败，创建默认配置
            createDefaultSources()
        }

        // 确保内置配置存在
        ensureBuiltinSourceExists()
    }

    /// 保存配置源
    private func saveConfigSources() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(configSources)
            try data.write(to: configFilePath)
            print("✅ 已保存配置源")
        } catch {
            print("⚠️ 配置源保存失败: \(error.localizedDescription)")
        }
    }

    /// 创建默认配置源
    private func createDefaultSources() {
        configSources = [
            ConfigSource.builtin(name: "内置配置 (npm)")
        ]
        saveConfigSources()
        print("✅ 已创建默认配置源")
    }

    /// 确保内置配置源存在
    private func ensureBuiltinSourceExists() {
        let builtinUUID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        if !configSources.contains(where: { $0.id == builtinUUID }) {
            let builtin = ConfigSource.builtin(name: "内置配置 (npm)")
            // 插入到开头
            configSources.insert(builtin, at: 0)
            saveConfigSources()
        }
    }
}
