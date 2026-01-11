//
//  ToolType.swift
//  MirrorSwitch
//
//  支持的开发工具类型枚举
//

import Foundation

/// 支持的开发工具类型
enum ToolType: String, CaseIterable, Codable {
    case npm = "NPM"
    case maven = "Maven"
    case homebrew = "Homebrew"
    case orbstack = "OrbStack"

    /// 显示名称
    var displayName: String {
        rawValue
    }

    /// 配置文件名
    var configFileName: String {
        switch self {
        case .npm:
            return ".npmrc"
        case .maven:
            return "settings.xml"
        case .homebrew:
            return ".zshrc"
        case .orbstack:
            return "config.json"
        }
    }

    /// 配置文件所在目录
    var configDirectory: String {
        switch self {
        case .npm:
            return "~"
        case .maven:
            return "~/.m2"
        case .homebrew:
            return "~"
        case .orbstack:
            return "~/.orbstack"
        }
    }

    /// 配置文件的完整路径
    var configFilePath: String {
        return "\(configDirectory)/\(configFileName)"
    }

    /// 是否支持测速功能
    var supportsSpeedTest: Bool {
        return true
    }
}
