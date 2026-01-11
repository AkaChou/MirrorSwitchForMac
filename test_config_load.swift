import Foundation

// 复制必要的模型结构
struct AppConfiguration: Codable {
    let version: String
    let app: AppInfo
    let ui: UIConfiguration
    let behavior: BehaviorConfiguration
    let network: NetworkConfiguration
    let paths: PathsConfiguration
    let remoteConfig: RemoteConfigConfiguration?
    let features: FeaturesConfiguration

    struct AppInfo: Codable {
        let name: String
        let displayName: String
        let identifier: String
        let version: String
    }

    struct UIConfiguration: Codable {
        let menuBar: MenuBarConfiguration
        let speedTest: SpeedTestConfiguration
        let items: UIItemsConfiguration
    }

    struct MenuBarConfiguration: Codable {
        let icon: IconConfiguration
        let title: String
    }

    struct IconConfiguration: Codable {
        let systemSymbolName: String
        let template: Bool?
    }

    struct SpeedTestConfiguration: Codable {
        let enabled: Bool
        let autoRunOnLaunch: Bool
        let timeout: Int
        let retryCount: Int
    }

    struct UIItemsConfiguration: Codable {
        let defaultSourceName: String
        let testingText: String
        let testButtonText: String
        let resetButtonText: String
        let quitButtonText: String
    }

    struct BehaviorConfiguration: Codable {
        let autoDetectTools: Bool
        let autoBackupBeforeSwitch: Bool
        let confirmBeforeReset: Bool
        let closeMenuAfterSwitch: Bool
        let restartDockerAfterOrbStackSwitch: Bool
    }

    struct NetworkConfiguration: Codable {
        let userAgent: String
        let timeout: Int
        let maxRetries: Int
    }

    struct PathsConfiguration: Codable {
        let configDirectory: String
        let cacheDirectory: String
        let backupDirectory: String
        let logDirectory: String
    }

    struct RemoteConfigConfiguration: Codable {
        let enabled: Bool
        let url: String
        let updateInterval: Int
        let fallbackToLocal: Bool
        let validateSchema: Bool
    }

    struct FeaturesConfiguration: Codable {
        let speedTest: Bool
        let autoSelectFastest: Bool
        let notifications: NotificationsConfiguration
    }

    struct NotificationsConfiguration: Codable {
        let enabled: Bool
        let onSwitchSuccess: Bool
        let onSwitchFailure: Bool
    }
}

// 测试加载配置
func testLoadConfig() {
    let configPath = "Sources/MirrorSwitch/configs/app_config.json"

    guard let data = try? Data(contentsOf: URL(fileURLWithPath: configPath)) else {
        print("❌ 无法读取配置文件")
        return
    }

    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase

    guard let config = try? decoder.decode(AppConfiguration.self, from: data) else {
        print("❌ 解析配置文件失败")
        return
    }

    print("✅ 配置加载成功！")
    print("📱 应用名称: \(config.app.displayName)")
    print("🎨 菜单图标: \(config.ui.menuBar.icon.systemSymbolName)")
    print("⚡️ 测速配置: enabled=\(config.ui.speedTest.enabled), timeout=\(config.ui.speedTest.timeout)s")
    print("📁 配置目录: \(config.paths.configDirectory)")
}

testLoadConfig()
