//
//  SchemaValidator.swift
//  MirrorSwitch
//
//  JSON Schema 验证器
//  用于验证镜像配置文件格式是否符合 ToolsConfiguration.schema.json 规范
//

import Foundation

/// Schema 验证器
@MainActor
class SchemaValidator {
    /// 单例
    static let shared = SchemaValidator()

    private init() {}

    // MARK: - 验证方法

    /// 验证 JSON 数据
    func validate(_ data: Data) -> ValidationResult {
        do {
            let json = try JSONSerialization.jsonObject(with: data, options: [])

            // 验证根对象结构
            guard let rootDict = json as? [String: Any] else {
                return .failure("根元素必须是对象")
            }

            // 验证必需字段: version 和 tools
            guard rootDict["version"] != nil else {
                return .failure("缺少必需字段: version")
            }

            guard let tools = rootDict["tools"] as? [[String: Any]] else {
                return .failure("缺少必需字段: tools (必须是数组)")
            }

            // 验证 tools 数组不为空
            if tools.isEmpty {
                return .failure("tools 数组不能为空")
            }

            // 验证每个工具配置
            for (index, tool) in tools.enumerated() {
                let result = validateTool(tool, index: index)
                if case .failure(let message) = result {
                    return .failure("工具[\(index)] 验证失败: \(message)")
                }
            }

            return .success

        } catch {
            return .failure("JSON 解析失败: \(error.localizedDescription)")
        }
    }

    /// 验证 JSON 文件
    func validate(fileURL: URL) -> ValidationResult {
        do {
            let data = try Data(contentsOf: fileURL)
            return validate(data)
        } catch {
            return .failure("文件读取失败: \(error.localizedDescription)")
        }
    }

    // MARK: - 私有验证方法

    /// 验证单个工具配置
    private func validateTool(_ tool: [String: Any], index: Int) -> ValidationResult {
        // 验证必需字段: id, name, sources, strategy
        guard let id = tool["id"] as? String, !id.isEmpty else {
            return .failure("缺少必需字段或为空: id")
        }

        guard let name = tool["name"] as? String, !name.isEmpty else {
            return .failure("缺少必需字段或为空: name")
        }

        guard let sources = tool["sources"] as? [[String: Any]] else {
            return .failure("缺少必需字段: sources (必须是数组)")
        }

        guard let strategy = tool["strategy"] as? [String: Any] else {
            return .failure("缺少必需字段: strategy (必须是对象)")
        }

        // 验证 sources 数组不为空
        if sources.isEmpty {
            return .failure("sources 数组不能为空")
        }

        // 验证每个镜像源
        for (sourceIndex, source) in sources.enumerated() {
            let result = validateSource(source, index: sourceIndex)
            if case .failure(let message) = result {
                return .failure("sources[\(sourceIndex)] 验证失败: \(message)")
            }
        }

        // 验证 strategy 必需字段: type
        guard let type = strategy["type"] as? String, !type.isEmpty else {
            return .failure("strategy 缺少必需字段或为空: type")
        }

        // 验证 type 值是否有效
        let validTypes = ["command", "xml", "jsonpath", "regex", "keyvalue"]
        guard validTypes.contains(type) else {
            return .failure("strategy.type 必须是以下之一: \(validTypes.joined(separator: ", "))")
        }

        return .success
    }

    /// 验证单个镜像源配置
    private func validateSource(_ source: [String: Any], index: Int) -> ValidationResult {
        // 验证必需字段: id, name, url
        guard let id = source["id"] as? String, !id.isEmpty else {
            return .failure("缺少必需字段或为空: id")
        }

        guard let name = source["name"] as? String, !name.isEmpty else {
            return .failure("缺少必需字段或为空: name")
        }

        guard let url = source["url"] as? String, !url.isEmpty else {
            return .failure("缺少必需字段或为空: url")
        }

        // 验证 URL 格式
        if let urlObj = URL(string: url) {
            // 检查是否是有效的 URL
            if urlObj.scheme == nil || urlObj.host == nil {
                return .failure("url 格式无效: \(url)")
            }
        } else {
            return .failure("url 格式无效: \(url)")
        }

        return .success
    }
}

/// 验证结果
enum ValidationResult {
    case success
    case failure(String)

    var isValid: Bool {
        if case .success = self { return true }
        return false
    }

    var errorMessage: String? {
        if case .failure(let message) = self { return message }
        return nil
    }
}
