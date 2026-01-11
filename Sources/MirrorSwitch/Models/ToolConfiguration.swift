//
//  ToolConfiguration.swift
//  MirrorSwitch
//
//  配置驱动的工具定义模型
//  通过 JSON 配置文件动态定义工具和镜像源
//

import Foundation

// MARK: - 根配置

/// 工具配置根结构
struct ToolsConfiguration: Codable {
    /// 配置版本
    let version: String

    /// 工具列表
    let tools: [ToolConfiguration]
}

// MARK: - 工具配置

/// 单个工具的完整配置
struct ToolConfiguration: Codable, Identifiable {
    /// 工具唯一标识
    let id: String

    /// 显示名称
    let name: String

    /// 描述信息
    let description: String?

    /// 工具检测配置
    let detection: DetectionConfiguration

    /// 镜像源列表
    let sources: [SourceConfiguration]

    /// 切换策略
    let strategy: StrategyConfiguration

    /// 备份配置
    let backup: BackupConfiguration?

    /// 工具元数据
    let metadata: ToolMetadata?

    /// 后置动作配置
    let postActions: PostActions?

    var identifier: String { id }

    /// 创建带有新镜像源列表的副本
    func withSources(_ sources: [SourceConfiguration]) -> ToolConfiguration {
        return ToolConfiguration(
            id: self.id,
            name: self.name,
            description: self.description,
            detection: self.detection,
            sources: sources,
            strategy: self.strategy,
            backup: self.backup,
            metadata: self.metadata,
            postActions: self.postActions
        )
    }
}

/// 工具元数据
struct ToolMetadata: Codable {
    /// 支持的操作系统
    let supportedPlatforms: [String]?

    /// 是否支持测速
    let supportsSpeedTest: Bool?

    /// 依赖的其他工具
    let dependencies: [String]?

    /// 文档链接
    let documentationURL: String?
}

// MARK: - 检测配置

/// 工具检测配置
struct DetectionConfiguration: Codable {
    /// 检测命令（可选，有些工具可能不需要命令检测）
    let command: String

    /// 命令参数（可选，有些工具可能不需要命令检测）
    let arguments: [String]

    /// 自定义路径列表 (支持通配符 *)
    let customPaths: [String]?

    /// 备用检测方式 (当命令检测失败时)
    let fallbackDetection: FallbackDetection?

    // 默认成员初始化器
    init(command: String = "", arguments: [String] = [], customPaths: [String]? = nil, fallbackDetection: FallbackDetection? = nil) {
        self.command = command
        self.arguments = arguments
        self.customPaths = customPaths
        self.fallbackDetection = fallbackDetection
    }

    // 自定义解码器，支持缺失的 command 和 arguments
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.command = try container.decodeIfPresent(String.self, forKey: .command) ?? ""
        self.arguments = try container.decodeIfPresent([String].self, forKey: .arguments) ?? []
        self.customPaths = try container.decodeIfPresent([String].self, forKey: .customPaths)
        self.fallbackDetection = try container.decodeIfPresent(FallbackDetection.self, forKey: .fallbackDetection)
    }

    /// 编码器
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if !command.isEmpty {
            try container.encode(command, forKey: .command)
        }
        if !arguments.isEmpty {
            try container.encode(arguments, forKey: .arguments)
        }
        try container.encodeIfPresent(customPaths, forKey: .customPaths)
        try container.encodeIfPresent(fallbackDetection, forKey: .fallbackDetection)
    }

    private enum CodingKeys: String, CodingKey {
        case command, arguments, customPaths, fallbackDetection
    }
}

/// 备用检测方式
enum FallbackDetection: Codable {
    /// 文件存在检测
    case file(path: String)

    /// 应用包检测 (macOS)
    case app(bundleId: String, path: String?)

    /// 环境变量检测
    case environmentVariable(name: String)

    /// 自定义脚本检测
    case script(command: String, arguments: [String])

    // Codable 实现
    private enum CodingKeys: String, CodingKey {
        case type, path, bundleId, name, command, arguments
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "file":
            self = .file(path: try container.decode(String.self, forKey: .path))
        case "app":
            self = .app(
                bundleId: try container.decode(String.self, forKey: .bundleId),
                path: try container.decodeIfPresent(String.self, forKey: .path)
            )
        case "environmentVariable":
            self = .environmentVariable(name: try container.decode(String.self, forKey: .name))
        case "script":
            self = .script(
                command: try container.decode(String.self, forKey: .command),
                arguments: try container.decode([String].self, forKey: .arguments)
            )
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Invalid fallback detection type: \(type)"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .file(let path):
            try container.encode("file", forKey: .type)
            try container.encode(path, forKey: .path)
        case .app(let bundleId, let path):
            try container.encode("app", forKey: .type)
            try container.encode(bundleId, forKey: .bundleId)
            try container.encodeIfPresent(path, forKey: .path)
        case .environmentVariable(let name):
            try container.encode("environmentVariable", forKey: .type)
            try container.encode(name, forKey: .name)
        case .script(let command, let arguments):
            try container.encode("script", forKey: .type)
            try container.encode(command, forKey: .command)
            try container.encode(arguments, forKey: .arguments)
        }
    }
}

// MARK: - 镜像源配置

/// 镜像源配置
struct SourceConfiguration: Codable, Identifiable {
    /// 唯一标识
    let id: String

    /// 显示名称
    let name: String

    /// 镜像 URL
    let url: String

    /// 描述信息
    let description: String?

    /// 地区信息
    let region: String?

    /// 是否需要认证
    let requiresAuth: Bool?

    /// 认证信息
    let auth: SourceAuth?

    // MARK: - 配置源跟踪字段

    /// 所属配置源 ID（用于跟踪镜像源来自哪个配置源）
    let configSourceId: String?

    /// 所属配置源名称（用于 UI 显示）
    let configSourceName: String?

    /// 是否来自内置配置（用于区分配置源类型）
    let configSourceIsBuiltin: Bool?

    var identifier: String { id }

    /// 创建带有配置源信息的副本
    func withConfigSource(
        configSourceId: String? = nil,
        configSourceName: String? = nil,
        configSourceIsBuiltin: Bool? = nil
    ) -> SourceConfiguration {
        return SourceConfiguration(
            id: self.id,
            name: self.name,
            url: self.url,
            description: self.description,
            region: self.region,
            requiresAuth: self.requiresAuth,
            auth: self.auth,
            configSourceId: configSourceId ?? self.configSourceId,
            configSourceName: configSourceName ?? self.configSourceName,
            configSourceIsBuiltin: configSourceIsBuiltin ?? self.configSourceIsBuiltin
        )
    }
}

/// 镜像源认证信息
struct SourceAuth: Codable {
    /// 认证类型
    let type: String

    /// 用户名
    let username: String?

    /// 密码
    let password: String?

    /// Token
    let token: String?
}

// MARK: - 策略配置

/// 策略配置 (使用枚举支持不同类型)
enum StrategyConfiguration: Codable {
    case command(CommandStrategy)
    case xml(XMLStrategy)
    case jsonpath(JSONPathStrategy)
    case regex(RegexStrategy)
    case keyvalue(KeyValueStrategy)

    private enum CodingKeys: String, CodingKey {
        case type
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "command":
            // 直接从当前容器解码 CommandStrategy
            self = .command(try CommandStrategy(from: decoder))
        case "xml":
            // 直接从当前容器解码 XMLStrategy
            self = .xml(try XMLStrategy(from: decoder))
        case "jsonpath":
            // 直接从当前容器解码 JSONPathStrategy
            self = .jsonpath(try JSONPathStrategy(from: decoder))
        case "regex":
            // 直接从当前容器解码 RegexStrategy
            self = .regex(try RegexStrategy(from: decoder))
        case "keyvalue":
            // 直接从当前容器解码 KeyValueStrategy
            self = .keyvalue(try KeyValueStrategy(from: decoder))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Invalid strategy type: \(type)"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .command(let strategy):
            try container.encode("command", forKey: .type)
            // 直接编码 strategy 的字段到当前容器
            try strategy.encode(to: encoder)
        case .xml(let strategy):
            try container.encode("xml", forKey: .type)
            try strategy.encode(to: encoder)
        case .jsonpath(let strategy):
            try container.encode("jsonpath", forKey: .type)
            try strategy.encode(to: encoder)
        case .regex(let strategy):
            try container.encode("regex", forKey: .type)
            try strategy.encode(to: encoder)
        case .keyvalue(let strategy):
            try container.encode("keyvalue", forKey: .type)
            try strategy.encode(to: encoder)
        }
    }
}

// MARK: - StrategyConfiguration Extensions

extension StrategyConfiguration {
    /// 获取配置文件目录
    /// - Returns: 配置文件目录路径，如果无法确定则返回 nil
    var configDirectory: String? {
        switch self {
        case .xml(let strategy):
            // XML 策略：从配置文件路径中提取目录
            return (strategy.filePath as NSString).deletingLastPathComponent
        case .jsonpath(let strategy):
            // JSONPath 策略：从配置文件路径中提取目录
            return (strategy.filePath as NSString).deletingLastPathComponent
        case .regex(let strategy):
            // Regex 策略：从配置文件路径中提取目录
            return (strategy.filePath as NSString).deletingLastPathComponent
        case .keyvalue(let strategy):
            // KeyValue 策略：从配置文件路径中提取目录
            return (strategy.filePath as NSString).deletingLastPathComponent
        case .command:
            // Command 策略：通常不涉及配置文件
            return nil
        }
    }
}

// MARK: - Command 策略

/// Shell 命令策略
struct CommandStrategy: Codable {
    /// 设置配置
    let set: CommandSetConfiguration

    /// 获取配置
    let get: CommandGetConfiguration
}

/// 命令设置配置
struct CommandSetConfiguration: Codable {
    /// 命令
    let command: String

    /// 参数列表 (支持模板变量 {{url}}, {{variable}})
    let arguments: [String]

    /// 环境变量
    let environment: [String: String]?

    /// 是否需要管理员权限
    let requiresAdmin: Bool?

    /// 工作目录
    let workingDirectory: String?

    /// 前置命令 (用于捕获动态值)
    let preCommands: [PreCommand]?

    /// 超时时间 (秒)
    let timeout: Int?
}

/// 前置命令 (用于捕获动态值)
struct PreCommand: Codable {
    /// 命令
    let command: String

    /// 参数
    let arguments: [String]

    /// 捕获为的变量名
    let captureAs: String

    /// 输出解析器
    let outputParser: String?
}

/// 命令获取配置
struct CommandGetConfiguration: Codable {
    /// 命令
    let command: String

    /// 参数列表
    let arguments: [String]

    /// 输出解析器
    let outputParser: OutputParser

    /// 超时时间 (秒)
    let timeout: Int?
}

/// 输出解析器
enum OutputParser: String, Codable {
    case trim                // 去除首尾空白
    case extractUrl          // 提取 URL
    case extractDomain       // 提取域名
    case firstLine           // 取第一行
    case json                // JSON 解析
    case regex               // 正则提取 (需配合 pattern)
}

// MARK: - XML 策略

/// XML 文件修改策略
struct XMLStrategy: Codable {
    /// 文件路径
    let filePath: String

    /// 设置配置
    let set: XMLSetConfiguration

    /// 获取配置
    let get: XMLGetConfiguration
}

/// XML 设置配置
struct XMLSetConfiguration: Codable {
    /// XPath 表达式
    let xpath: String

    /// 值 (支持模板变量)
    let value: String

    /// 命名空间
    let namespaces: [String: String]?

    /// 确保结构存在
    let ensureStructure: EnsureStructureConfiguration?
}

/// XML 获取配置
struct XMLGetConfiguration: Codable {
    /// XPath 表达式
    let xpath: String

    /// 命名空间
    let namespaces: [String: String]?

    /// 属性名 (如果要获取属性而非元素内容)
    let attribute: String?
}

// MARK: - JSONPath 策略

/// JSONPath 文件修改策略
struct JSONPathStrategy: Codable {
    /// 文件路径
    let filePath: String

    /// 设置配置
    let set: JSONPathSetConfiguration

    /// 获取配置
    let get: JSONPathGetConfiguration
}

/// JSONPath 设置配置
struct JSONPathSetConfiguration: Codable {
    /// JSONPath 表达式
    let jsonpath: String

    /// 值 (支持 JSON 数据类型)
    let value: JSONValue

    /// 合并策略
    let mergeStrategy: MergeStrategy?

    /// 确保结构存在
    let ensureStructure: EnsureStructureConfiguration?
}

/// JSON 获取配置
struct JSONPathGetConfiguration: Codable {
    /// JSONPath 表达式
    let jsonpath: String
}

/// JSON 值包装器
enum JSONValue: Codable {
    case string(String)
    case number(Double)
    case boolean(Bool)
    case array([JSONValue])
    case object([String: JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let number = try? container.decode(Double.self) {
            self = .number(number)
        } else if let bool = try? container.decode(Bool.self) {
            self = .boolean(bool)
        } else if let array = try? container.decode([JSONValue].self) {
            self = .array(array)
        } else if let object = try? container.decode([String: JSONValue].self) {
            self = .object(object)
        } else if container.decodeNil() {
            self = .null
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "JSONValue cannot be decoded"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .boolean(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }
}

/// 合并策略
enum MergeStrategy: String, Codable {
    case replace   // 替换整个值
    case merge     // 合并对象
    case append    // 追加到数组
    case prepend   // 前置到数组
}

// MARK: - Regex 策略

/// 正则替换策略
struct RegexStrategy: Codable {
    /// 文件路径
    let filePath: String

    /// 设置配置
    let set: RegexSetConfiguration

    /// 获取配置
    let get: RegexGetConfiguration
}

/// 正则设置配置
struct RegexSetConfiguration: Codable {
    /// 正则模式
    let pattern: String

    /// 替换内容 (支持模板变量和捕获组 $1, $2...)
    let replacement: String

    /// 是否全局替换
    let global: Bool?

    /// 正则选项
    let options: [String]?  // caseInsensitive, multiline, etc.
}

/// 正则获取配置
struct RegexGetConfiguration: Codable {
    /// 正则模式
    let pattern: String

    /// 捕获组索引 (0 表示整个匹配)
    let captureGroup: Int?
}

// MARK: - KeyValue 策略

/// 键值对文件策略
struct KeyValueStrategy: Codable {
    /// 文件路径
    let filePath: String

    /// 设置配置
    let set: KeyValueSetConfiguration

    /// 获取配置
    let get: KeyValueGetConfiguration

    /// 文件格式
    let format: KeyValueFormat?
}

/// 键值对设置配置
struct KeyValueSetConfiguration: Codable {
    /// 键名
    let key: String

    /// 值 (支持模板变量)
    let value: String

    /// 注释
    let comment: String?

    /// 分隔符
    let separator: String?
}

/// 键值对获取配置
struct KeyValueGetConfiguration: Codable {
    /// 键名
    let key: String

    /// 分隔符
    let separator: String?
}

/// 键值对文件格式
enum KeyValueFormat: String, Codable {
    case properties   // Java .properties 文件
    case env          // .env 文件
    case conf         // .conf 文件
    case ini          // .ini 文件
}

// MARK: - 通用配置

/// 确保结构配置
struct EnsureStructureConfiguration: Codable {
    /// 如果缺失是否创建
    let createIfMissing: Bool

    /// 默认结构模板
    let defaultStructure: String

    /// 创建前的父目录
    let createParentDirectories: Bool?
}

// MARK: - 备份配置

/// 备份配置
struct BackupConfiguration: Codable {
    /// 文件路径 (支持模板变量)
    let filePath: String

    /// 备份文件名
    let backupFileName: String

    /// 是否备份原始配置
    let backupOriginal: Bool?

    /// 原始备份文件名后缀
    let originalBackupSuffix: String?
}

// MARK: - 模板变量解析器

/// 模板变量解析器
struct TemplateVariableParser {
    /// 解析模板字符串
    static func parse(_ template: String, variables: [String: String]) throws -> String {
        var result = template

        // 支持 {{variable}} 语法
        let pattern = #"\{\{([^}]+)\}\}"#
        let regex = try NSRegularExpression(pattern: pattern)

        let matches = regex.matches(in: template, range: NSRange(template.startIndex..., in: template))

        for match in matches.reversed() {
            guard let range = Range(match.range(at: 1), in: template) else { continue }
            let variableName = String(template[range])

            if let value = variables[variableName] {
                let replaceRange = Range(match.range, in: template)!
                result.replaceSubrange(replaceRange, with: value)
            } else {
                throw ConfigurationError.variableNotFound(variableName)
            }
        }

        return result
    }

    /// 从镜像源和上下文中提取变量
    static func extractVariables(from source: SourceConfiguration, context: [String: Any]) -> [String: String] {
        var variables: [String: String] = [:]

        // 基本变量
        variables["url"] = source.url
        variables["id"] = source.id
        variables["name"] = source.name

        // 添加上下文变量
        for (key, value) in context {
            if let stringValue = value as? String {
                variables[key] = stringValue
            }
        }

        return variables
    }
}

// MARK: - 后置动作配置

/// 后置动作配置容器
struct PostActions: Codable {
    /// 切换镜像源后的后置动作
    let onSourceChanged: PostAction?

    /// 重置为默认配置后的后置动作
    let onReset: PostAction?
}

/// 后置动作配置
struct PostAction: Codable {
    /// 动作类型
    let type: PostActionType

    /// 标题
    let title: String

    /// 消息内容
    let message: String

    /// 确认按钮文本
    let confirmButton: String?

    /// 取消按钮文本
    let cancelButton: String?

    /// 确认后执行的命令
    let confirmCommand: CommandConfig?

    /// 取消后执行的命令
    let cancelCommand: CommandConfig?
}

/// 后置动作类型
enum PostActionType: String, Codable {
    case showConfirmationDialog = "showConfirmationDialog"  // 显示确认对话框
    case executeCommand = "executeCommand"                  // 执行命令
    case notification = "notification"                      // 显示通知
}

/// 命令配置
struct CommandConfig: Codable {
    /// 命令路径
    let command: String

    /// 参数列表
    let arguments: [String]?

    /// 工作目录
    let workingDirectory: String?
}

// MARK: - 配置错误

/// 配置错误
enum ConfigurationError: Error, LocalizedError {
    case fileNotFound(String)
    case parseFailed(String)
    case validationFailed([String])
    case versionMismatch(String)
    case variableNotFound(String)
    case invalidSyntax(String)
    case networkError(Error)
    case cacheError(String)

    var errorDescription: String? {
        switch self {
        case .fileNotFound(let path):
            return "配置文件未找到: \(path)"
        case .parseFailed(let reason):
            return "配置解析失败: \(reason)"
        case .validationFailed(let errors):
            return "配置验证失败:\n" + errors.joined(separator: "\n")
        case .versionMismatch(let version):
            return "配置版本不匹配: \(version)"
        case .variableNotFound(let variable):
            return "模板变量未找到: {{\(variable)}}"
        case .invalidSyntax(let error):
            return "配置语法错误: \(error)"
        case .networkError(let error):
            return "网络请求失败: \(error.localizedDescription)"
        case .cacheError(let message):
            return "缓存错误: \(message)"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .fileNotFound:
            return "请检查配置文件路径，或运行初始化命令创建默认配置"
        case .parseFailed:
            return "请检查配置文件格式是否符合 JSON 规范"
        case .validationFailed:
            return "请根据错误提示修正配置文件"
        case .networkError:
            return "请检查网络连接，或使用本地缓存配置"
        default:
            return nil
        }
    }
}
