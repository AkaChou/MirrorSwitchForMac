//
//  ToolHandlerProtocol.swift
//  MirrorSwitch
//
//  工具处理器协议定义
//

import Foundation

/// 工具处理器协议
/// 定义了所有工具处理器必须实现的基本方法
protocol ToolHandlerProtocol {
    /// 切换到指定镜像源
    /// - Parameter source: 目标镜像源
    /// - Throws: 切换失败时抛出错误
    func switchTo(_ source: MirrorSource) async throws

    /// 获取当前配置
    /// - Returns: 当前配置的字符串表示
    /// - Throws: 获取失败时抛出错误
    func getCurrentConfig() async throws -> String

    /// 备份当前配置
    /// - Throws: 备份失败时抛出错误
    func backupConfig() async throws

    /// 恢复备份配置
    /// - Throws: 恢复失败时抛出错误
    func restoreBackup() async throws
}

/// 工具处理器错误类型
enum ToolHandlerError: Error {
    /// 可执行文件未找到
    case executableNotFound

    /// 配置文件未找到
    case configNotFound

    /// 切换失败
    case switchFailed(String)

    /// 备份文件未找到
    case backupNotFound

    /// 命令执行失败
    case commandExecutionFailed(String)

    /// 解析失败
    case parseFailed(String)

    var localizedDescription: String {
        switch self {
        case .executableNotFound:
            return "找不到可执行文件"
        case .configNotFound:
            return "配置文件不存在"
        case .switchFailed(let message):
            return "切换失败: \(message)"
        case .backupNotFound:
            return "备份文件不存在"
        case .commandExecutionFailed(let message):
            return "命令执行失败: \(message)"
        case .parseFailed(let message):
            return "解析失败: \(message)"
        }
    }
}
