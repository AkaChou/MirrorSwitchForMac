//
//  AppConfiguration.swift
//  MirrorSwitch
//
//  Created by Haruko on 2025-01-11.
//

import Foundation

/// 应用配置模型
struct AppConfiguration: Codable {
    let version: String
    let app: AppInfo
    let ui: UIConfiguration
    let behavior: BehaviorConfiguration
    let network: NetworkConfiguration
    let paths: PathsConfiguration
    let remoteConfig: RemoteConfigConfiguration?
    let features: FeaturesConfiguration

    // MARK: - 子配置模型

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

        enum CodingKeys: String, CodingKey {
            case defaultSourceName = "defaultSourceName"
            case testingText
            case testButtonText
            case resetButtonText
            case quitButtonText
        }
    }

    struct BehaviorConfiguration: Codable {
        let autoDetectTools: Bool
        let autoBackupBeforeSwitch: Bool
        let confirmBeforeReset: Bool
        let closeMenuAfterSwitch: Bool
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

        func expandTilde() -> PathsConfiguration {
            func expandPath(_ path: String) -> String {
                if path.hasPrefix("~/") {
                    let home = FileManager.default.homeDirectoryForCurrentUser.path
                    return home + String(path.dropFirst(2))
                }
                return path
            }

            return PathsConfiguration(
                configDirectory: expandPath(configDirectory),
                cacheDirectory: expandPath(cacheDirectory),
                backupDirectory: expandPath(backupDirectory),
                logDirectory: expandPath(logDirectory)
            )
        }
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

/// UI 字符串配置模型
struct UIStringsConfiguration: Codable {
    let version: String
    let language: String
    let strings: Strings

    struct Strings: Codable {
        let app: AppStrings
        let menu: MenuStrings
        let sources: SourceStrings
        let errors: ErrorStrings
        let notifications: NotificationStrings
        let settings: SettingsStrings
        let about: AboutStrings

        struct AppStrings: Codable {
            let name: String
            let menuTitle: String
        }

        struct MenuStrings: Codable {
            let preferences: String
            let about: String
            let quit: String
        }

        struct SourceStrings: Codable {
            let `default`: String
            let official: String
            let testing: String
            let speed: String
            let reset: String
            let resetToDefault: String
            let resetConfirmTitle: String
            let resetConfirmMessage: String
            let resetSuccess: String
            let resetFailed: String
        }

        struct ErrorStrings: Codable {
            let toolNotFound: String
            let sourceNotFound: String
            let backupNotFound: String
            let backupNotSupported: String
            let switchFailed: String
            let configLoadFailed: String
            let networkError: String
            let parseError: String
        }

        struct NotificationStrings: Codable {
            let switchSuccess: String
            let switchFailed: String
        }

        struct SettingsStrings: Codable {
            let title: String
            let general: String
            let advanced: String
            let remoteConfig: String
            let remoteConfigUrl: String
            let updateInterval: String
            let enableRemoteConfig: String
            let autoUpdate: String
            let checkForUpdates: String
            let save: String
            let cancel: String
        }

        struct AboutStrings: Codable {
            let title: String
            let version: String
            let description: String
            let homepage: String
            let license: String
        }
    }
}
