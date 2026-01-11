//
//  StrategyExecutor.swift
//  MirrorSwitch
//
//  策略执行器 - 根据不同的策略类型执行对应的切换逻辑
//  支持 command、xml、jsonpath、regex、keyvalue 五种策略
//

import Foundation
import AEXML

/// 策略执行器
actor StrategyExecutor {
    // MARK: - 执行策略

    /// 执行策略设置
    func execute(
        strategy: StrategyConfiguration,
        source: SourceConfiguration,
        tool: ToolConfiguration
    ) async throws {
        switch strategy {
        case .command(let commandStrategy):
            try await executeCommandStrategy(
                commandStrategy,
                source: source,
                tool: tool
            )

        case .xml(let xmlStrategy):
            try await executeXMLStrategy(
                xmlStrategy,
                source: source,
                tool: tool
            )

        case .jsonpath(let jsonpathStrategy):
            try await executeJSONPathStrategy(
                jsonpathStrategy,
                source: source,
                tool: tool
            )

        case .regex(let regexStrategy):
            try await executeRegexStrategy(
                regexStrategy,
                source: source,
                tool: tool
            )

        case .keyvalue(let keyvalueStrategy):
            try await executeKeyValueStrategy(
                keyvalueStrategy,
                source: source,
                tool: tool
            )
        }
    }

    /// 获取当前配置
    func getCurrentConfig(
        strategy: StrategyConfiguration,
        tool: ToolConfiguration
    ) async throws -> String {
        switch strategy {
        case .command(let commandStrategy):
            return try await getCommandConfig(commandStrategy, tool: tool)

        case .xml(let xmlStrategy):
            return try await getXMLConfig(xmlStrategy, tool: tool)

        case .jsonpath(let jsonpathStrategy):
            return try await getJSONPathConfig(jsonpathStrategy, tool: tool)

        case .regex(let regexStrategy):
            return try await getRegexConfig(regexStrategy, tool: tool)

        case .keyvalue(let keyvalueStrategy):
            return try await getKeyValueConfig(keyvalueStrategy, tool: tool)
        }
    }

    // MARK: - Command 策略

    private func executeCommandStrategy(
        _ strategy: CommandStrategy,
        source: SourceConfiguration,
        tool: ToolConfiguration
    ) async throws {
        // 构建变量上下文
        var context: [String: Any] = [:]

        // 执行前置命令
        if let preCommands = strategy.set.preCommands {
            for preCommand in preCommands {
                let result = try await executeCommand(
                    preCommand.command,
                    arguments: preCommand.arguments
                )

                // 解析输出
                let output = parseOutput(
                    result.standardOutput,
                    parser: OutputParser(rawValue: preCommand.outputParser ?? "trim") ?? .trim
                )

                context[preCommand.captureAs] = output
            }
        }

        // 解析模板变量
        let variables = TemplateVariableParser.extractVariables(
            from: source,
            context: context
        )

        // 构建参数
        let arguments = try strategy.set.arguments.map { arg in
            try TemplateVariableParser.parse(arg, variables: variables)
        }

        // 执行命令
        let result = try await executeCommand(
            strategy.set.command,
            arguments: arguments
        )

        if result.exitCode != 0 {
            throw SourceManagerError.commandExecutionFailed(result.standardError)
        }
    }

    private func getCommandConfig(
        _ strategy: CommandStrategy,
        tool: ToolConfiguration
    ) async throws -> String {
        let result = try await executeCommand(
            strategy.get.command,
            arguments: strategy.get.arguments
        )

        if result.exitCode != 0 {
            throw SourceManagerError.commandExecutionFailed(result.standardError)
        }

        return parseOutput(result.standardOutput, parser: strategy.get.outputParser)
    }

    // MARK: - XML 策略

    private func executeXMLStrategy(
        _ strategy: XMLStrategy,
        source: SourceConfiguration,
        tool: ToolConfiguration
    ) async throws {
        let filePath = try expandPath(strategy.filePath, tool: tool)

        // 检查文件是否存在
        if !FileManager.default.fileExists(atPath: filePath) {
            if let ensure = strategy.set.ensureStructure, ensure.createIfMissing {
                try await createDefaultFile(
                    path: filePath,
                    content: ensure.defaultStructure,
                    source: source,
                    tool: tool,
                    createParentDirs: ensure.createParentDirectories ?? true
                )
            } else {
                throw SourceManagerError.configNotFound
            }
        }

        // 读取文件
        let content = try String(contentsOfFile: filePath, encoding: .utf8)

        // 使用 AEXML 解析
        let document = try AEXMLDocument(xml: content)

        // 解析值
        let value = try TemplateVariableParser.parse(
            strategy.set.value,
            variables: TemplateVariableParser.extractVariables(from: source, context: [:])
        )

        // 使用 XPath 更新值
        try updateXMLPath(document: document, xpath: strategy.set.xpath, value: value)

        // 写回文件
        try document.xml.write(toFile: filePath, atomically: true, encoding: .utf8)
    }

    private func getXMLConfig(
        _ strategy: XMLStrategy,
        tool: ToolConfiguration
    ) async throws -> String {
        let filePath = try expandPath(strategy.filePath, tool: tool)

        guard FileManager.default.fileExists(atPath: filePath) else {
            throw SourceManagerError.configNotFound
        }

        let content = try String(contentsOfFile: filePath, encoding: .utf8)
        let document = try AEXMLDocument(xml: content)

        return try queryXMLPath(document: document, xpath: strategy.get.xpath)
    }

    // MARK: - JSONPath 策略

    private func executeJSONPathStrategy(
        _ strategy: JSONPathStrategy,
        source: SourceConfiguration,
        tool: ToolConfiguration
    ) async throws {
        let filePath = try expandPath(strategy.filePath, tool: tool)

        // 检查文件是否存在
        if !FileManager.default.fileExists(atPath: filePath) {
            if let ensure = strategy.set.ensureStructure, ensure.createIfMissing {
                try await createDefaultFile(
                    path: filePath,
                    content: ensure.defaultStructure,
                    source: source,
                    tool: tool,
                    createParentDirs: ensure.createParentDirectories ?? true
                )
            } else {
                throw SourceManagerError.configNotFound
            }
        }

        // 读取文件
        let data = try Data(contentsOf: URL(fileURLWithPath: filePath))
        var json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]

        // 解析值
        let parsedValue = try parseJSONValue(
            strategy.set.value,
            source: source,
            tool: tool
        )

        // 使用 JSONPath 更新
        json = updateJSONPath(json, path: strategy.set.jsonpath, value: parsedValue)

        // 写回文件
        let newData = try JSONSerialization.data(withJSONObject: json, options: .prettyPrinted)
        try newData.write(to: URL(fileURLWithPath: filePath))
    }

    private func getJSONPathConfig(
        _ strategy: JSONPathStrategy,
        tool: ToolConfiguration
    ) async throws -> String {
        let filePath = try expandPath(strategy.filePath, tool: tool)

        guard FileManager.default.fileExists(atPath: filePath) else {
            throw SourceManagerError.configNotFound
        }

        let data = try Data(contentsOf: URL(fileURLWithPath: filePath))
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SourceManagerError.parseFailed("无效的 JSON 格式")
        }

        let result = try queryJSONPath(json, path: strategy.get.jsonpath)

        if let stringValue = result as? String {
            return stringValue
        } else {
            return String(describing: result)
        }
    }

    // MARK: - Regex 策略

    private func executeRegexStrategy(
        _ strategy: RegexStrategy,
        source: SourceConfiguration,
        tool: ToolConfiguration
    ) async throws {
        let filePath = try expandPath(strategy.filePath, tool: tool)

        guard FileManager.default.fileExists(atPath: filePath) else {
            throw SourceManagerError.configNotFound
        }

        // 读取文件
        var content = try String(contentsOfFile: filePath, encoding: .utf8)

        // 解析替换内容
        let replacement = try TemplateVariableParser.parse(
            strategy.set.replacement,
            variables: TemplateVariableParser.extractVariables(from: source, context: [:])
        )

        // 执行替换
        let regex = try NSRegularExpression(pattern: strategy.set.pattern)
        let range = NSRange(content.startIndex..., in: content)

        content = regex.stringByReplacingMatches(
            in: content,
            options: strategy.set.global == true ? [] : .anchored,
            range: range,
            withTemplate: replacement
        )

        // 写回文件
        try content.write(toFile: filePath, atomically: true, encoding: .utf8)
    }

    private func getRegexConfig(
        _ strategy: RegexStrategy,
        tool: ToolConfiguration
    ) async throws -> String {
        let filePath = try expandPath(strategy.filePath, tool: tool)

        guard FileManager.default.fileExists(atPath: filePath) else {
            throw SourceManagerError.configNotFound
        }

        let content = try String(contentsOfFile: filePath, encoding: .utf8)
        let regex = try NSRegularExpression(pattern: strategy.get.pattern)

        let range = NSRange(content.startIndex..., in: content)
        guard let match = regex.firstMatch(in: content, range: range) else {
            return ""
        }

        let groupIndex = strategy.get.captureGroup ?? 0
        guard groupIndex < match.numberOfRanges else {
            return ""
        }

        let captureRange = match.range(at: groupIndex)
        guard let range = Range(captureRange, in: content) else {
            return ""
        }

        return String(content[range])
    }

    // MARK: - KeyValue 策略

    private func executeKeyValueStrategy(
        _ strategy: KeyValueStrategy,
        source: SourceConfiguration,
        tool: ToolConfiguration
    ) async throws {
        let filePath = try expandPath(strategy.filePath, tool: tool)

        // 解析值
        let value = try TemplateVariableParser.parse(
            strategy.set.value,
            variables: TemplateVariableParser.extractVariables(from: source, context: [:])
        )

        // 读取或创建文件
        var lines: [String] = []
        if FileManager.default.fileExists(atPath: filePath) {
            let content = try String(contentsOfFile: filePath, encoding: .utf8)
            lines = content.components(separatedBy: .newlines)
        }

        // 查找并替换键
        let separator = strategy.set.separator ?? "="
        var found = false
        for i in 0..<lines.count {
            let line = lines[i]
            if line.hasPrefix(strategy.set.key + separator) || line.hasPrefix(strategy.set.key + " ") {
                lines[i] = "\(strategy.set.key)\(separator)\(value)"
                if let comment = strategy.set.comment {
                    lines[i] = "\(comment)\n\(lines[i])"
                }
                found = true
                break
            }
        }

        // 如果没找到，追加新行
        if !found {
            var newLine = "\(strategy.set.key)\(separator)\(value)"
            if let comment = strategy.set.comment {
                newLine = "\(comment)\n\(newLine)"
            }
            lines.append(newLine)
        }

        // 写回文件
        let content = lines.joined(separator: "\n")
        try content.write(toFile: filePath, atomically: true, encoding: .utf8)
    }

    private func getKeyValueConfig(
        _ strategy: KeyValueStrategy,
        tool: ToolConfiguration
    ) async throws -> String {
        let filePath = try expandPath(strategy.filePath, tool: tool)

        guard FileManager.default.fileExists(atPath: filePath) else {
            throw SourceManagerError.configNotFound
        }

        let content = try String(contentsOfFile: filePath, encoding: .utf8)
        let lines = content.components(separatedBy: .newlines)

        let separator = strategy.get.separator ?? "="
        for line in lines {
            if line.hasPrefix(strategy.get.key + separator) || line.hasPrefix(strategy.get.key + " ") {
                if let range = line.range(of: separator) {
                    let value = String(line[range.upperBound...]).trimmingCharacters(in: CharacterSet.whitespaces)
                    return value
                }
            }
        }

        return ""
    }

    // MARK: - 辅助方法

    /// 执行 Shell 命令
    private func executeCommand(
        _ command: String,
        arguments: [String]
    ) async throws -> ShellExecutionResult {
        // 查找可执行文件路径
        let pathResolver = PathResolver()
        let executablePath = pathResolver.findExecutable(command) ?? command

        return try await ShellExecutor.execute(executablePath, arguments: arguments)
    }

    /// 解析命令输出
    private func parseOutput(_ output: String, parser: OutputParser) -> String {
        var result = output

        switch parser {
        case .trim:
            result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        case .extractUrl:
            if let urlRange = result.range(of: "https?://[^\\s]+", options: .regularExpression) {
                result = String(result[urlRange])
            }
        case .extractDomain:
            if let url = URL(string: result.trimmingCharacters(in: .whitespaces)), let host = url.host {
                result = host
            }
        case .firstLine:
            result = result.components(separatedBy: .newlines).first ?? result
        case .json, .regex:
            break
        }

        return result
    }

    /// 展开路径（支持 ~）
    private func expandPath(_ path: String, tool: ToolConfiguration) throws -> String {
        let expandedPath = (path as NSString).expandingTildeInPath
        return expandedPath
    }

    /// 创建默认文件
    private func createDefaultFile(
        path: String,
        content: String,
        source: SourceConfiguration,
        tool: ToolConfiguration,
        createParentDirs: Bool
    ) async throws {
        let parsedContent = try TemplateVariableParser.parse(
            content,
            variables: TemplateVariableParser.extractVariables(from: source, context: [:])
        )

        if createParentDirs {
            let directory = (path as NSString).deletingLastPathComponent
            try FileManager.default.createDirectory(
                atPath: directory,
                withIntermediateDirectories: true
            )
        }

        try parsedContent.write(toFile: path, atomically: true, encoding: .utf8)
    }

    // MARK: - XML 辅助方法

    /// 更新 XML 路径
    private func updateXMLPath(document: AEXMLDocument, xpath: String, value: String) throws {
        // 解析 XPath，如 //mirrors/mirror[1]/url
        let parts = xpath.components(separatedBy: "/").filter { !$0.isEmpty }

        var element = document.root

        // 遍历路径
        for part in parts.dropFirst() { // 跳过根节点的 //
            let cleanPart = part.components(separatedBy: "[").first ?? part

            // 查找子元素
            if let found = element.firstDescendant(where: { $0.name == cleanPart }) {
                element = found
            } else {
                throw SourceManagerError.parseFailed("未找到元素: \(cleanPart)")
            }
        }

        element.value = value
    }

    /// 查询 XML 路径
    private func queryXMLPath(document: AEXMLDocument, xpath: String) throws -> String {
        // 解析 XPath
        let parts = xpath.components(separatedBy: "/").filter { !$0.isEmpty }

        var element = document.root

        // 遍历路径
        for part in parts.dropFirst() {
            let cleanPart = part.components(separatedBy: "[").first ?? part

            if let found = element.firstDescendant(where: { $0.name == cleanPart }) {
                element = found
            } else {
                throw SourceManagerError.parseFailed("未找到元素: \(cleanPart)")
            }
        }

        return element.value ?? ""
    }

    /// 简化的 XPath 匹配（不再使用）
    private func matchXPath(_ element: AEXMLElement, xpath: String) -> Bool {
        let parts = xpath.components(separatedBy: "/").filter { !$0.isEmpty }
        guard let lastPart = parts.last else { return false }
        let elementName = lastPart.components(separatedBy: "[").first ?? lastPart
        return element.name == elementName
    }

    // MARK: - JSONPath 辅助方法

    /// 解析 JSON 值
    private func parseJSONValue(
        _ value: JSONValue,
        source: SourceConfiguration,
        tool: ToolConfiguration
    ) throws -> Any {
        switch value {
        case .string(let str):
            return try TemplateVariableParser.parse(
                str,
                variables: TemplateVariableParser.extractVariables(from: source, context: [:])
            )
        case .number(let num):
            return num
        case .boolean(let bool):
            return bool
        case .array(let arr):
            return try arr.map { try parseJSONValue($0, source: source, tool: tool) }
        case .object(let obj):
            var result: [String: Any] = [:]
            for (key, val) in obj {
                result[key] = try parseJSONValue(val, source: source, tool: tool)
            }
            return result
        case .null:
            return NSNull()
        }
    }

    /// 更新 JSONPath（返回修改后的 JSON）
    private func updateJSONPath(_ json: [String: Any], path: String, value: Any) -> [String: Any] {
        var result = json
        let keys = path.components(separatedBy: ".").filter { !$0.isEmpty }

        if keys.count == 1 {
            result[keys[0]] = value
            return result
        }

        // 递归更新嵌套结构
        if let firstKey = keys.first {
            let remainingPath = keys.dropFirst().joined(separator: ".")
            if let nested = result[firstKey] as? [String: Any] {
                result[firstKey] = updateJSONPath(nested, path: remainingPath, value: value)
            } else {
                // 创建嵌套结构
                result[firstKey] = updateJSONPath([:], path: remainingPath, value: value)
            }
        }

        return result
    }

    /// 查询 JSONPath
    private func queryJSONPath(_ json: [String: Any], path: String) throws -> Any {
        let keys = path.components(separatedBy: ".").filter { !$0.isEmpty }

        var current: Any? = json
        for key in keys {
            if let dict = current as? [String: Any] {
                current = dict[key]
            } else {
                throw SourceManagerError.parseFailed("JSONPath 查询失败: \(path)")
            }
        }

        return current ?? NSNull()
    }
}
