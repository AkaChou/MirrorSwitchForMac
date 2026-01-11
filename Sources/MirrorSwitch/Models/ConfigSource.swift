//
//  ConfigSource.swift
//  MirrorSwitch
//
//  配置源数据模型
//  用于管理本地和远程配置源
//

import Foundation

/// 配置源数据模型
struct ConfigSource: Identifiable, Codable, Equatable {
    /// 唯一标识
    let id: UUID

    /// 配置源名称
    var name: String

    /// 配置源类型
    var type: ConfigType

    /// 配置源 URL（远程 URL 或本地文件路径）
    var url: String?

    /// 是否启用
    var isEnabled: Bool

    /// 最后更新时间
    var lastUpdated: Date?

    /// 配置源状态
    var status: ConfigStatus

    /// 创建时间
    let createdAt: Date

    /// 初始化方法（非 builtin 类型使用）
    init(
        id: UUID = UUID(),
        name: String,
        type: ConfigType,
        url: String? = nil,
        isEnabled: Bool = true,
        lastUpdated: Date? = nil,
        status: ConfigStatus = .valid
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.url = url
        self.isEnabled = isEnabled
        self.lastUpdated = lastUpdated
        self.status = status
        self.createdAt = Date()
    }

    /// 创建内置配置源
    static func builtin(name: String) -> ConfigSource {
        return ConfigSource(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, // 固定 UUID
            name: name,
            type: .builtin,
            url: nil,
            isEnabled: true,
            lastUpdated: nil,
            status: .valid
        )
    }

    /// Equatable 实现
    static func == (lhs: ConfigSource, rhs: ConfigSource) -> Bool {
        lhs.id == rhs.id
    }
}

/// 配置源类型
enum ConfigType: String, Codable {
    /// 内置配置
    case builtin

    /// 本地文件
    case local

    /// 远程 URL
    case remote

    /// 显示名称
    var displayName: String {
        switch self {
        case .builtin: return "内置"
        case .local: return "本地"
        case .remote: return "远程"
        }
    }

    /// 图标
    var icon: String {
        switch self {
        case .builtin: return "📦"
        case .local: return "📁"
        case .remote: return "☁️"
        }
    }
}

/// 配置源状态
enum ConfigStatus: String, Codable {
    /// 有效
    case valid

    /// 错误
    case error

    /// 加载中
    case loading

    /// 未验证
    case unverified

    /// 显示名称
    var displayName: String {
        switch self {
        case .valid: return "有效"
        case .error: return "错误"
        case .loading: return "加载中..."
        case .unverified: return "未验证"
        }
    }

    /// 图标
    var icon: String {
        switch self {
        case .valid: return "✅"
        case .error: return "❌"
        case .loading: return "⏳"
        case .unverified: return "❓"
        }
    }

    /// 颜色（用于 NSColor）
    var colorName: String {
        switch self {
        case .valid: return "systemGreenColor"
        case .error: return "systemRedColor"
        case .loading: return "systemBlueColor"
        case .unverified: return "systemGrayColor"
        }
    }
}
