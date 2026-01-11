//
//  ShellExecutor.swift
//  MirrorSwitch
//
//  Shell 命令执行器
//

import Foundation

/// Shell 命令执行结果
struct ShellExecutionResult {
    /// 退出码
    let exitCode: Int32

    /// 标准输出
    let standardOutput: String

    /// 标准错误输出
    let standardError: String
}

/// Shell 命令执行器（静态方法类）
class ShellExecutor {
    /// 执行 Shell 命令
    /// - Parameters:
    ///   - command: 命令路径
    ///   - arguments: 命令参数
    /// - Returns: 命令执行结果
    /// - Throws: 执行失败时抛出错误
    static func execute(_ command: String, arguments: [String]) async throws -> ShellExecutionResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = arguments

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()

            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

            let output = String(decoding: outputData, as: UTF8.self)
            let error = String(decoding: errorData, as: UTF8.self)

            return ShellExecutionResult(
                exitCode: process.terminationStatus,
                standardOutput: output,
                standardError: error
            )
        } catch {
            throw ToolHandlerError.commandExecutionFailed(error.localizedDescription)
        }
    }

    /// 执行 Shell 命令（同步版本）
    /// - Parameters:
    ///   - command: 命令路径
    ///   - arguments: 命令参数
    /// - Returns: 命令执行结果
    /// - Throws: 执行失败时抛出错误
    static func executeSync(_ command: String, arguments: [String]) throws -> ShellExecutionResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = arguments

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

        let output = String(decoding: outputData, as: UTF8.self)
        let error = String(decoding: errorData, as: UTF8.self)

        return ShellExecutionResult(
            exitCode: process.terminationStatus,
            standardOutput: output,
            standardError: error
        )
    }
}
