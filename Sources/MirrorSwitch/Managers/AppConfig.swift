//
//  AppConfig.swift
//  MirrorSwitch
//
//  应用配置管理器
//  提供全局访问应用配置的便捷接口
//

import Foundation

/// 应用配置管理器
/// 提供全局访问应用配置和 UI 字符串的便捷接口
@MainActor
class AppConfigManager {
    static let shared = AppConfigManager()

    private var appConfig: AppConfiguration?
    private var uiStrings: UIStringsConfiguration?

    private init() {}

    // MARK: - 配置加载

    /// 加载应用配置
    func loadConfig() async throws {
        let loader = AppConfigurationLoader.shared

        // 检查是否启用了远程配置（从环境变量）
        if let remoteURL = ProcessInfo.processInfo.environment["MIRROR_SWITCH_CONFIG_URL"] {
            await loader.setRemoteConfigURL(remoteURL)
        }

        // 加载配置
        let (config, strings) = try await loader.reload()
        self.appConfig = config
        self.uiStrings = strings

        print("✅ 应用配置加载完成")
        print("📱 应用名称: \(config.app.displayName)")
        print("🎨 菜单图标: \(config.ui.menuBar.icon.systemSymbolName)")
    }

    // MARK: - 应用信息访问

    var appName: String {
        appConfig?.app.name ?? "MirrorSwitch"
    }

    var appDisplayName: String {
        appConfig?.app.displayName ?? "镜像源切换器"
    }

    var appVersion: String {
        appConfig?.app.version ?? "1.0.0"
    }

    // MARK: - UI 配置访问

    /// 菜单栏图标配置
    var menuBarIcon: (systemSymbolName: String, template: Bool?) {
        (
            systemSymbolName: appConfig?.ui.menuBar.icon.systemSymbolName ?? "arrow.triangle.2.circlepath",
            template: appConfig?.ui.menuBar.icon.template
        )
    }

    /// 测速配置
    var speedTestConfig: (enabled: Bool, autoRunOnLaunch: Bool, timeout: Int, retryCount: Int) {
        guard let config = appConfig?.ui.speedTest else {
            return (enabled: true, autoRunOnLaunch: true, timeout: 5, retryCount: 3)
        }
        return (
            enabled: config.enabled,
            autoRunOnLaunch: config.autoRunOnLaunch,
            timeout: config.timeout,
            retryCount: config.retryCount
        )
    }

    // MARK: - 行为配置访问

    /// 是否自动检测工具
    var autoDetectTools: Bool {
        appConfig?.behavior.autoDetectTools ?? true
    }

    /// 是否在切换前自动备份
    var autoBackupBeforeSwitch: Bool {
        appConfig?.behavior.autoBackupBeforeSwitch ?? true
    }

    /// 是否在重置前确认
    var confirmBeforeReset: Bool {
        appConfig?.behavior.confirmBeforeReset ?? true
    }

    /// 是否在切换后关闭菜单
    var closeMenuAfterSwitch: Bool {
        appConfig?.behavior.closeMenuAfterSwitch ?? false
    }

    /// 是否在 OrbStack 切换后重启 Docker
    var restartDockerAfterOrbStackSwitch: Bool {
        appConfig?.behavior.restartDockerAfterOrbStackSwitch ?? true
    }

    // MARK: - 网络配置访问

    /// 网络用户代理
    var userAgent: String {
        appConfig?.network.userAgent ?? "MirrorSwitch/1.0.0"
    }

    /// 网络超时时间（秒）
    var networkTimeout: Int {
        appConfig?.network.timeout ?? 30
    }

    /// 最大重试次数
    var maxRetries: Int {
        appConfig?.network.maxRetries ?? 3
    }

    // MARK: - 路径配置访问

    /// 配置目录（已展开 ~）
    var configDirectory: String {
        appConfig?.paths.expandTilde().configDirectory ?? "~/.mirror-switch"
    }

    /// 缓存目录（已展开 ~）
    var cacheDirectory: String {
        appConfig?.paths.expandTilde().cacheDirectory ?? "~/.mirror-switch/cache"
    }

    /// 备份目录（已展开 ~）
    var backupDirectory: String {
        appConfig?.paths.expandTilde().backupDirectory ?? "~/.mirror-switch/backup"
    }

    /// 日志目录（已展开 ~）
    var logDirectory: String {
        appConfig?.paths.expandTilde().logDirectory ?? "~/.mirror-switch/logs"
    }

    // MARK: - 远程配置访问

    /// 远程配置是否启用
    var remoteConfigEnabled: Bool {
        appConfig?.remoteConfig?.enabled ?? false
    }

    /// 远程配置 URL
    var remoteConfigURL: String? {
        appConfig?.remoteConfig?.url
    }

    /// 远程配置更新间隔（秒）
    var remoteConfigUpdateInterval: Int {
        appConfig?.remoteConfig?.updateInterval ?? 86400
    }

    // MARK: - 功能开关访问

    /// 测速功能是否启用
    var speedTestEnabled: Bool {
        appConfig?.features.speedTest ?? true
    }

    /// 自动选择最快源是否启用
    var autoSelectFastest: Bool {
        appConfig?.features.autoSelectFastest ?? false
    }

    /// 通知配置
    var notificationsConfig: (enabled: Bool, onSwitchSuccess: Bool, onSwitchFailure: Bool) {
        guard let config = appConfig?.features.notifications else {
            return (enabled: true, onSwitchSuccess: true, onSwitchFailure: true)
        }
        return (
            enabled: config.enabled,
            onSwitchSuccess: config.onSwitchSuccess,
            onSwitchFailure: config.onSwitchFailure
        )
    }

    // MARK: - UI 字符串访问

    /// 格式化字符串（替换占位符）
    func formatString(_ key: String, variables: [String: String] = [:]) -> String {
        // 从 UI 字符串配置中查找对应的字符串
        // 这里简化处理，实际需要根据 key 查找对应的字符串
        return key
    }

    /// 获取镜像源相关字符串
    func sourceString(_ key: String) -> String {
        switch key {
        case "default": return uiStrings?.strings.sources.default ?? "未选择"
        case "official": return uiStrings?.strings.sources.official ?? "官方源"
        case "testing": return uiStrings?.strings.sources.testing ?? "测速中..."
        case "speed": return uiStrings?.strings.sources.speed ?? "测速"
        case "reset": return uiStrings?.strings.sources.reset ?? "重置为默认配置"
        case "resetToDefault": return uiStrings?.strings.sources.resetToDefault ?? "重置为默认配置"
        case "resetSuccess": return uiStrings?.strings.sources.resetSuccess ?? "已重置为默认配置"
        case "resetFailed": return uiStrings?.strings.sources.resetFailed ?? "重置失败"
        default: return key
        }
    }

    /// 获取工具相关字符串
    func toolString(toolId: String) -> (name: String, description: String)? {
        guard let tools = uiStrings?.strings.tools else {
            return nil
        }

        switch toolId {
        case "npm":
            return (name: tools.npm.name, description: tools.npm.description)
        case "maven":
            return (name: tools.maven.name, description: tools.maven.description)
        case "homebrew":
            return (name: tools.homebrew.name, description: tools.homebrew.description)
        case "orbstack":
            return (name: tools.orbstack.name, description: tools.orbstack.description)
        case "pip":
            return (name: tools.pip.name, description: tools.pip.description)
        case "gradle":
            return (name: tools.gradle.name, description: tools.gradle.description)
        default:
            return nil
        }
    }

    /// 获取错误消息
    func errorString(_ key: String) -> String {
        switch key {
        case "toolNotFound": return uiStrings?.strings.errors.toolNotFound ?? "未找到工具"
        case "sourceNotFound": return uiStrings?.strings.errors.sourceNotFound ?? "未找到镜像源"
        case "backupNotFound": return uiStrings?.strings.errors.backupNotFound ?? "备份文件不存在"
        case "backupNotSupported": return uiStrings?.strings.errors.backupNotSupported ?? "不支持备份"
        case "switchFailed": return uiStrings?.strings.errors.switchFailed ?? "切换失败"
        case "configLoadFailed": return uiStrings?.strings.errors.configLoadFailed ?? "配置加载失败"
        case "networkError": return uiStrings?.strings.errors.networkError ?? "网络错误"
        case "parseError": return uiStrings?.strings.errors.parseError ?? "解析错误"
        default: return key
        }
    }

    /// 获取菜单字符串
    func menuString(_ key: String) -> String {
        switch key {
        case "preferences": return uiStrings?.strings.menu.preferences ?? "偏好设置"
        case "about": return uiStrings?.strings.menu.about ?? "关于"
        case "quit": return uiStrings?.strings.menu.quit ?? "退出"
        default: return key
        }
    }
}
