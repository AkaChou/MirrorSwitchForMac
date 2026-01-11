//
//  ConfigModel.swift
//  MirrorSwitch
//
//  应用配置数据结构
//

import Foundation

/// 应用配置数据结构
struct AppConfiguration: Codable {
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

    /// 默认配置
    static var defaultConfig: AppConfiguration {
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

        let mavenSources = [
            MirrorSource(
                id: "maven-official",
                name: "官方源",
                url: "https://repo.maven.apache.org/maven2/",
                description: "Maven 中央仓库"
            ),
            MirrorSource(
                id: "maven-aliyun",
                name: "阿里云",
                url: "https://maven.aliyun.com/repository/public/",
                description: "阿里云公共仓库"
            ),
            MirrorSource(
                id: "maven-tencent",
                name: "腾讯云",
                url: "https://mirrors.cloud.tencent.com/repository/maven/",
                description: "腾讯云公共仓库"
            ),
            MirrorSource(
                id: "maven-huawei",
                name: "华为云",
                url: "https://mirrors.huaweicloud.com/repository/maven/",
                description: "华为云 Maven 镜像"
            ),
            MirrorSource(
                id: "maven-tsinghua",
                name: "清华源",
                url: "https://mirrors.tuna.tsinghua.edu.cn/maven/",
                description: "清华大学镜像"
            ),
        ]

        let homebrewSources = [
            MirrorSource(
                id: "homebrew-official",
                name: "官方源",
                url: "https://github.com/Homebrew/brew",
                description: "Homebrew 官方"
            ),
            MirrorSource(
                id: "homebrew-tsinghua",
                name: "清华源",
                url: "https://mirrors.tuna.tsinghua.edu.cn/git/homebrew/brew.git",
                description: "清华大学镜像"
            ),
            MirrorSource(
                id: "homebrew-ustc",
                name: "中科大",
                url: "https://mirrors.ustc.edu.cn/brew.git",
                description: "中科大镜像"
            ),
        ]

        let orbstackSources = [
            MirrorSource(
                id: "orbstack-official",
                name: "官方源",
                url: "https://docker.io",
                description: "Docker Hub 官方"
            ),
            MirrorSource(
                id: "orbstack-aliyun",
                name: "阿里云",
                url: "https://registry.cn-hangzhou.aliyuncs.com",
                description: "阿里云容器镜像（仅阿里云内网推荐）"
            ),
            MirrorSource(
                id: "orbstack-tencent",
                name: "腾讯云",
                url: "https://mirror.ccs.tencentyun.com",
                description: "腾讯云容器镜像（仅腾讯云内网推荐）"
            )
        ]

        return AppConfiguration(
            version: "1.0.0",
            tools: [
                .npm: npmSources,
                .maven: mavenSources,
                .homebrew: homebrewSources,
                .orbstack: orbstackSources
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
