//
//  MavenHandler.swift
//  MirrorSwitch
//
//  Maven 镜像源处理器（含 XML 解析）
//

import Foundation

/// Maven 镜像源处理器
class MavenHandler: ToolHandlerProtocol {
    /// Maven settings.xml 路径
    private var mavenSettingsPath: URL

    /// 原始配置文件备份标记
    private static let originalBackupFlag = "original_settings_backipped"

    /// 初始化
    init() {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        mavenSettingsPath = homeDir
            .appendingPathComponent(".m2")
            .appendingPathComponent("settings.xml")
    }

    /// 获取实际的配置文件路径
    /// 优先级：用户自定义路径下的 conf/settings.xml > ~/.m2/settings.xml
    private func getConfigPath() -> URL {
        // 检查是否有用户自定义的 Maven 路径
        if let customPath = ConfigManager.shared.getCustomPath(for: .maven) {
            let customSettingsPath = URL(fileURLWithPath: customPath)
                .appendingPathComponent("conf")
                .appendingPathComponent("settings.xml")

            // 如果自定义路径下的配置文件存在，使用它
            if FileManager.default.fileExists(atPath: customSettingsPath.path) {
                debugLog("✅ 使用自定义路径的配置文件: \(customSettingsPath.path)")
                return customSettingsPath
            }
        }

        // 否则使用默认的 ~/.m2/settings.xml
        return mavenSettingsPath
    }

    /// 获取原始配置备份路径
    private func getOriginalBackupPath() -> URL {
        let backupDir = BackupManager.shared.backupDirectory(for: .maven)
        return backupDir.appendingPathComponent("settings.xml.original")
    }

    /// 检查是否已备份原始配置
    private func hasOriginalBackup() -> Bool {
        let flagPath = getOriginalBackupPath().deletingLastPathComponent()
            .appendingPathComponent(Self.originalBackupFlag)
        return FileManager.default.fileExists(atPath: flagPath.path)
    }

    /// 标记原始配置已备份
    private func markOriginalBackup() {
        let flagPath = getOriginalBackupPath().deletingLastPathComponent()
            .appendingPathComponent(Self.originalBackupFlag)
        FileManager.default.createFile(atPath: flagPath.path, contents: Data())
    }

    /// 备份原始配置文件（仅在用户首次指定路径时调用）
    func backupOriginalSettings() async throws {
        // 如果已经备份过，跳过
        if hasOriginalBackup() {
            debugLog("ℹ️ 原始配置已备份，跳过")
            return
        }

        let configPath = getConfigPath()

        // 检查配置文件是否存在
        guard FileManager.default.fileExists(atPath: configPath.path) else {
            debugLog("⚠️ 配置文件不存在，无需备份: \(configPath.path)")
            return
        }

        // 确保备份目录存在
        let backupPath = getOriginalBackupPath()
        let backupDir = backupPath.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: backupDir,
                                                withIntermediateDirectories: true)

        // 删除旧备份（如果存在）
        if FileManager.default.fileExists(atPath: backupPath.path) {
            try FileManager.default.removeItem(at: backupPath)
        }

        // 备份原始配置
        try FileManager.default.copyItem(at: configPath, to: backupPath)
        markOriginalBackup()

        debugLog("✅ 已备份原始配置: \(backupPath.path)")
    }

    // MARK: - ToolHandlerProtocol

    /// 切换到指定镜像源
    func switchTo(_ source: MirrorSource) async throws {
        print("🔄 切换 Maven 镜像源: \(source.name)")

        // 获取实际配置文件路径
        let configPath = getConfigPath()
        print("📁 使用配置文件: \(configPath.path)")

        // 1. 检查文件是否存在
        guard FileManager.default.fileExists(atPath: configPath.path) else {
            throw ToolHandlerError.configNotFound
        }

        // 2. 读取文件内容
        let content = try String(contentsOfFile: configPath.path, encoding: .utf8)

        // 3. 解析 XML
        let parser = MavenSettingsParser()
        try parser.parse(content: content)

        // 4. 更新镜像 URL
        parser.updateMirror(url: source.url)

        // 5. 生成新的 XML
        let newContent = parser.generateXML()

        // 6. 写回文件
        try newContent.write(to: configPath, atomically: true, encoding: .utf8)

        print("✓ Maven 镜像源已切换到: \(source.url)")
    }

    /// 获取当前配置
    func getCurrentConfig() async throws -> String {
        let configPath = getConfigPath()

        guard FileManager.default.fileExists(atPath: configPath.path) else {
            throw ToolHandlerError.configNotFound
        }

        let content = try String(contentsOfFile: configPath.path, encoding: .utf8)

        // 尝试解析 XML 获取当前镜像 URL
        let parser = MavenSettingsParser()
        try? parser.parse(content: content)

        if let currentMirror = parser.getCurrentMirror() {
            return currentMirror
        }

        return content
    }

    /// 备份当前配置
    func backupConfig() async throws {
        let configPath = getConfigPath()

        guard FileManager.default.fileExists(atPath: configPath.path) else {
            print("⚠️ settings.xml 文件不存在，跳过备份")
            return
        }

        let backupDir = BackupManager.shared.backupDirectory(for: .maven)
        try FileManager.default.createDirectory(at: backupDir,
                                                withIntermediateDirectories: true)

        let backupPath = backupDir.appendingPathComponent("settings.xml.backup")

        if FileManager.default.fileExists(atPath: backupPath.path) {
            try FileManager.default.removeItem(at: backupPath)
        }

        try FileManager.default.copyItem(at: configPath, to: backupPath)
        print("✓ Maven 配置已备份")
    }

    /// 恢复备份配置
    /// 优先恢复原始配置备份（settings.xml.original）
    /// 如果没有原始备份，则使用普通备份（settings.xml.backup）
    func restoreBackup() async throws {
        let configPath = getConfigPath()
        let originalBackupPath = getOriginalBackupPath()
        let normalBackupPath = BackupManager.shared.backupDirectory(for: .maven)
            .appendingPathComponent("settings.xml.backup")

        // 优先尝试恢复原始配置
        if FileManager.default.fileExists(atPath: originalBackupPath.path) {
            if FileManager.default.fileExists(atPath: configPath.path) {
                try FileManager.default.removeItem(at: configPath)
            }
            try FileManager.default.copyItem(at: originalBackupPath, to: configPath)
            print("✓ Maven 配置已恢复（原始备份）")
            return
        }

        // 如果没有原始备份，尝试普通备份
        guard FileManager.default.fileExists(atPath: normalBackupPath.path) else {
            throw ToolHandlerError.backupNotFound
        }

        if FileManager.default.fileExists(atPath: configPath.path) {
            try FileManager.default.removeItem(at: configPath)
        }

        try FileManager.default.copyItem(at: normalBackupPath, to: configPath)
        print("✓ Maven 配置已恢复（普通备份）")
    }

    /// 获取配置文件目录
    func getConfigDirectory() -> URL? {
        let configPath = getConfigPath()
        let configDir = configPath.deletingLastPathComponent()
        return FileManager.default.fileExists(atPath: configDir.path) ? configDir : nil
    }
}

// MARK: - Maven XML Parser

/// Maven settings.xml 解析器
class MavenSettingsParser: NSObject, XMLParserDelegate {
    /// 镜像列表
    private var mirrors: [MavenMirror] = []

    /// 当前解析的元素名
    private var currentElement: String?

    /// 当前解析的镜像
    private var currentMirror: MavenMirror?

    /// 解析错误
    private var parsingError: String?

    /// 解析 XML 内容
    func parse(content: String) throws {
        guard let data = content.data(using: .utf8) else {
            throw ToolHandlerError.parseFailed("无法转换数据")
        }

        let parser = XMLParser(data: data)
        parser.delegate = self

        if !parser.parse() {
            throw ToolHandlerError.parseFailed(parser.parserError?.localizedDescription ?? "未知错误")
        }
    }

    /// 更新镜像 URL
    func updateMirror(url: String) {
        if !mirrors.isEmpty {
            mirrors[0].url = url
        } else {
            // 如果没有 mirror，创建一个新的
            var newMirror = MavenMirror()
            newMirror.id = "mirror1"
            newMirror.url = url
            mirrors.append(newMirror)
        }
    }

    /// 获取当前镜像 URL
    func getCurrentMirror() -> String? {
        return mirrors.first?.url
    }

    /// 生成 XML 内容
    func generateXML() -> String {
        var xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        xml += "<settings xmlns=\"http://maven.apache.org/SETTINGS/1.0.0\"\n"
        xml += "          xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\"\n"
        xml += "          xsi:schemaLocation=\"http://maven.apache.org/SETTINGS/1.0.0\n"
        xml += "          http://maven.apache.org/xsd/settings-1.0.0.xsd\">\n"
        xml += "  <mirrors>\n"

        for mirror in mirrors {
            xml += "    <mirror>\n"
            xml += "      <id>\(mirror.id)</id>\n"
            xml += "      <url>\(mirror.url)</url>\n"
            xml += "      <mirrorOf>*</mirrorOf>\n"
            xml += "    </mirror>\n"
        }

        xml += "  </mirrors>\n"
        xml += "</settings>\n"
        return xml
    }

    // MARK: - XMLParserDelegate

    func parser(_ parser: XMLParser,
                didStartElement elementName: String,
                namespaceURI: String?,
                qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        currentElement = elementName
        if elementName == "mirror" {
            currentMirror = MavenMirror()
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard let element = currentElement,
              var mirror = currentMirror else { return }

        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            switch element {
            case "id":
                mirror.id = trimmed
            case "url":
                mirror.url = trimmed
            default:
                break
            }
            currentMirror = mirror
        }
    }

    func parser(_ parser: XMLParser,
                didEndElement elementName: String,
                namespaceURI: String?,
                qualifiedName qName: String?) {
        if elementName == "mirror", let mirror = currentMirror {
            mirrors.append(mirror)
            currentMirror = nil
        }
        currentElement = nil
    }
}

/// Maven 镜像结构体
struct MavenMirror {
    /// 镜像 ID
    var id: String = "mirror1"

    /// 镜像 URL
    var url: String = ""
}
