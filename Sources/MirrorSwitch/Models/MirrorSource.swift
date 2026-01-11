//
//  MirrorSource.swift
//  MirrorSwitch
//
//  镜像源数据结构
//

import Foundation

/// 镜像源数据结构
struct MirrorSource: Codable, Identifiable, Equatable {
    /// 唯一标识符
    let id: String

    /// 显示名称
    let name: String

    /// 镜像 URL
    let url: String

    /// 描述信息
    let description: String?

    /// 延迟时间（毫秒）
    var pingTime: Int?

    /// 是否为当前选中的镜像源
    var isSelected: Bool

    /// 所属配置源 ID
    var configSourceId: String?

    /// 所属配置源名称
    var configSourceName: String?

    /// 是否在 UI 中可见
    var isVisible: Bool

    /// 初始化方法
    init(
        id: String,
        name: String,
        url: String,
        description: String? = nil,
        pingTime: Int? = nil,
        isSelected: Bool = false,
        configSourceId: String? = nil,
        configSourceName: String? = nil,
        isVisible: Bool = true
    ) {
        self.id = id
        self.name = name
        self.url = url
        self.description = description
        self.pingTime = pingTime
        self.isSelected = isSelected
        self.configSourceId = configSourceId
        self.configSourceName = configSourceName
        self.isVisible = isVisible
    }
}

/// 镜像源扩展方法
extension MirrorSource {
    /// 获取格式化的延迟时间字符串
    var formattedPingTime: String? {
        guard let ping = pingTime else { return nil }
        return "\(ping)ms"
    }

    /// 根据延迟时间获取状态颜色
    var pingTimeColor: String {
        guard let ping = pingTime else { return "gray" }

        switch ping {
        case 0..<100:
            return "green"    // 快速
        case 100..<300:
            return "yellow"   // 中等
        default:
            return "red"      // 慢
        }
    }
}
