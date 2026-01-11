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
    private let mavenSettingsPath: URL

    /// 初始化
    init() {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        mavenSettingsPath = homeDir
            .appendingPathComponent(".m2")
            .appendingPathComponent("settings.xml")
    }

    // MARK: - ToolHandlerProtocol

    /// 切换到指定镜像源
    func switchTo(_ source: MirrorSource) async throws {
        print("🔄 切换 Maven 镜像源: \(source.name)")

        // 1. 检查文件是否存在
        guard FileManager.default.fileExists(atPath: mavenSettingsPath.path) else {
            throw ToolHandlerError.configNotFound
        }

        // 2. 读取文件内容
        let content = try String(contentsOfFile: mavenSettingsPath.path, encoding: .utf8)

        // 3. 解析 XML
        let parser = MavenSettingsParser()
        try parser.parse(content: content)

        // 4. 更新镜像 URL
        parser.updateMirror(url: source.url)

        // 5. 生成新的 XML
        let newContent = parser.generateXML()

        // 6. 写回文件
        try newContent.write(to: mavenSettingsPath, atomically: true, encoding: .utf8)

        print("✓ Maven 镜像源已切换到: \(source.url)")
    }

    /// 获取当前配置
    func getCurrentConfig() async throws -> String {
        guard FileManager.default.fileExists(atPath: mavenSettingsPath.path) else {
            throw ToolHandlerError.configNotFound
        }

        let content = try String(contentsOfFile: mavenSettingsPath.path, encoding: .utf8)

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
        guard FileManager.default.fileExists(atPath: mavenSettingsPath.path) else {
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

        try FileManager.default.copyItem(at: mavenSettingsPath, to: backupPath)
        print("✓ Maven 配置已备份")
    }

    /// 恢复备份配置
    func restoreBackup() async throws {
        let backupPath = BackupManager.shared.backupDirectory(for: .maven)
            .appendingPathComponent("settings.xml.backup")

        guard FileManager.default.fileExists(atPath: backupPath.path) else {
            throw ToolHandlerError.backupNotFound
        }

        if FileManager.default.fileExists(atPath: mavenSettingsPath.path) {
            try FileManager.default.removeItem(at: mavenSettingsPath)
        }

        try FileManager.default.copyItem(at: backupPath, to: mavenSettingsPath)
        print("✓ Maven 配置已恢复")
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
