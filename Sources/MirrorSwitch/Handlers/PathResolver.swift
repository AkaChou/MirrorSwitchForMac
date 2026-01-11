//
//  PathResolver.swift
//  MirrorSwitch
//
//  路径解析器，用于查找可执行文件路径
//

import Foundation

/// 路径解析器
class PathResolver {
    /// 查找可执行文件路径
    /// - Parameter name: 可执行文件名称
    /// - Returns: 可执行文件的完整路径，如果未找到则返回 nil
    func findExecutable(_ name: String) -> String? {
        // 1. 检查常见路径
        let commonPaths = [
            "/usr/local/bin/\(name)",
            "/opt/homebrew/bin/\(name)",
            "/usr/bin/\(name)",
            "/opt/homebrew/opt/\(name)/bin/\(name)",
            "~/.nvm/versions/node/*/bin/\(name)",
        ]

        for path in commonPaths {
            let expandedPath = (path as NSString).expandingTildeInPath
            if FileManager.default.fileExists(atPath: expandedPath) {
                return expandedPath
            }
        }

        // 2. 使用 which 命令查找
        if let whichPath = findUsingWhich(name) {
            return whichPath
        }

        return nil
    }

    /// 使用 which 命令查找可执行文件
    private func findUsingWhich(_ name: String) -> String? {
        do {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
            process.arguments = [name]

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()

            try process.run()
            process.waitUntilExit()

            if process.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let path = String(decoding: data, as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                return path.isEmpty ? nil : path
            }
        } catch {
            // which 命令执行失败，返回 nil
        }

        return nil
    }
}
