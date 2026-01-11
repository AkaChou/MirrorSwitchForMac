//
//  ToolType.swift
//  MirrorSwitch
//
//  支持的开发工具类型枚举
//  ⚠️ 注意：此枚举仅用于向后兼容，新工具应通过配置文件动态添加
//

import Foundation

/// 支持的开发工具类型（仅内置工具）
/// ⚠️ 这是一个向后兼容层，不建议直接使用
/// 应该通过 ConfigurationDrivenSourceManager 动态获取工具配置
enum ToolType: String, CaseIterable, Codable {
    case npm = "npm"

    /// 显示名称
    var displayName: String {
        rawValue
    }

    /// 检测命令（用于检查工具是否已安装）
    var detectionCommand: String {
        return "npm"
    }

    /// 版本命令参数
    var versionArguments: [String] {
        return ["--version"]
    }

    /// 配置文件名
    var configFileName: String {
        return ".npmrc"
    }

    /// 配置文件所在目录
    var configDirectory: String {
        return "~"
    }

    /// 配置文件的完整路径
    var configFilePath: String {
        return "\(configDirectory)/\(configFileName)"
    }

    /// 是否支持测速功能
    var supportsSpeedTest: Bool {
        return true
    }

    /// 根据 toolId 创建 ToolType（兼容层）
    /// 如果 toolId 不在枚举中，返回 nil
    static func from(toolId: String) -> ToolType? {
        return ToolType(rawValue: toolId)
    }
}
