//
//  ConfigModel.swift
//  MirrorSwitch
//
//  应用配置数据结构（运行时状态）
//  ⚠️ 注意：此文件仅用于向后兼容，实际配置应从 tools_config.json 加载
//

import Foundation

/// 镜像源配置数据结构（运行时状态）
/// 用于存储工具的镜像源列表和当前选择状态
/// ⚠️ 这是一个向后兼容层，新代码应该使用 ConfigurationDrivenSourceManager
struct MirrorSourceConfiguration: Codable {
    /// 配置版本
    let version: String

    /// 各工具的镜像源列表
    var tools: [ToolType: [MirrorSource]]

    /// 当前选中的镜像源（tool -> sourceId）
    var currentSelection: [String: String]

    /// 初始化方法
    init(version: String, tools: [ToolType: [MirrorSource]], currentSelection: [String: String] = [:]) {
        self.version = version
        self.tools = tools
        self.currentSelection = currentSelection
    }

    /// 默认配置（仅 npm，其他工具从配置文件动态加载）
    static var defaultConfig: MirrorSourceConfiguration {
        let npmSources = [
            MirrorSource(
                id: "npm-official",
                name: "官方源",
                url: "https://registry.npmjs.org/",
                description: "npm 官方源"
            ),
            MirrorSource(
                id: "npm-taobao",
                name: "淘宝源",
                url: "https://registry.npmmirror.com/",
                description: "淘宝镜像（npmmirror，阿里巴巴赞助）"
            ),
            MirrorSource(
                id: "npm-tencent",
                name: "腾讯云",
                url: "https://mirrors.cloud.tencent.com/npm/",
                description: "腾讯云镜像"
            ),
            MirrorSource(
                id: "npm-huawei",
                name: "华为云",
                url: "https://mirrors.huaweicloud.com/repository/npm/",
                description: "华为云镜像"
            ),
        ]

        return MirrorSourceConfiguration(
            version: "1.0.0",
            tools: [
                .npm: npmSources
            ],
            currentSelection: [:]
        )
    }

    /// 获取指定工具的镜像源列表
    func getSources(for tool: ToolType) -> [MirrorSource] {
        return tools[tool] ?? []
    }

    /// 获取指定工具的当前选中镜像源
    func getSelectedSource(for tool: ToolType) -> MirrorSource? {
        guard let selectedId = currentSelection[tool.rawValue] else {
            return nil
        }
        return getSources(for: tool).first { $0.id == selectedId }
    }
}
