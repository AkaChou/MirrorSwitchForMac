//
//  Notifications.swift
//  MirrorSwitch
//
//  应用通知名称定义
//  用于组件之间的通信
//

import Foundation

/// 应用通知名称
extension Notification.Name {
    /// 配置源列表已变更
    /// 当添加、删除或切换配置源的启用状态时发送此通知
    static let configSourcesDidChange = Notification.Name("configSourcesDidChange")

    /// 工具可见性已变更
    /// 当工具的可见性设置发生变化时发送此通知（仅影响菜单显示，不需要重新加载配置）
    static let toolVisibilityDidChange = Notification.Name("toolVisibilityDidChange")

    /// 工具配置已重新加载
    /// 当工具配置重新加载完成时发送此通知
    static let toolsConfigurationDidReload = Notification.Name("toolsConfigurationDidReload")

    /// 工具列表已更新
    /// 当工具列表发生变化时发送此通知
    static let toolsListDidUpdate = Notification.Name("toolsListDidUpdate")
}
