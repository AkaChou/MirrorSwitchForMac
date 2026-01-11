//
//  PostActionExecutor.swift
//  MirrorSwitch
//
//  后置动作执行器
//  根据配置文件中定义的后置动作执行相应的操作
//

import Foundation
import AppKit

/// 后置动作执行器
@MainActor
class PostActionExecutor {
    /// 单例
    static let shared = PostActionExecutor()

    private init() {}

    // MARK: - 公共方法

    /// 执行后置动作
    /// - Parameters:
    ///   - postAction: 后置动作配置
    ///   - completion: 完成回调，返回是否成功执行
    func execute(_ postAction: PostAction, completion: @escaping (Bool) -> Void) {
        switch postAction.type {
        case .showConfirmationDialog:
            executeShowConfirmationDialog(postAction, completion: completion)
        case .executeCommand:
            executeCommand(postAction.confirmCommand, completion: completion)
        case .notification:
            executeNotification(postAction, completion: completion)
        }
    }

    // MARK: - 私有方法

    /// 显示确认对话框
    private func executeShowConfirmationDialog(
        _ postAction: PostAction,
        completion: @escaping (Bool) -> Void
    ) {
        let alert = NSAlert()
        alert.messageText = postAction.title
        alert.informativeText = postAction.message
        alert.alertStyle = .informational

        // 添加按钮（注意顺序：第一个是取消，第二个是确认）
        let cancelText = postAction.cancelButton ?? "稍后"
        let confirmText = postAction.confirmButton ?? "确定"
        alert.addButton(withTitle: cancelText)
        alert.addButton(withTitle: confirmText)

        // 显示对话框
        let response = alert.runModal()

        if response == .alertSecondButtonReturn {
            // 用户点击了确认按钮（第二个按钮）
            if let command = postAction.confirmCommand {
                debugLog("✅ 用户确认，执行命令: \(command.command)")
                executeCommand(command, completion: completion)
            } else {
                completion(true)
            }
        } else {
            // 用户点击了取消按钮（第一个按钮）
            if let command = postAction.cancelCommand {
                debugLog("⚠️ 用户取消，执行取消命令: \(command.command)")
                executeCommand(command, completion: completion)
            } else {
                completion(false)
            }
        }
    }

    /// 执行命令
    private func executeCommand(_ command: CommandConfig?, completion: @escaping (Bool) -> Void) {
        guard let command = command else {
            completion(true)
            return
        }

        Task {
            do {
                let result = try await ShellExecutor.execute(
                    command.command,
                    arguments: command.arguments ?? []
                )
                await MainActor.run {
                    if result.exitCode == 0 {
                        debugLog("✅ 命令执行成功")
                        completion(true)
                    } else {
                        let error = result.standardError.isEmpty ? result.standardOutput : result.standardError
                        debugLog("⚠️ 命令执行失败: \(error)")
                        completion(false)
                    }
                }
            } catch {
                await MainActor.run {
                    debugLog("❌ 命令执行错误: \(error.localizedDescription)")
                    completion(false)
                }
            }
        }
    }

    /// 显示通知
    private func executeNotification(_ postAction: PostAction, completion: @escaping (Bool) -> Void) {
        let notification = NSUserNotification()
        notification.title = postAction.title
        notification.informativeText = postAction.message
        notification.soundName = NSUserNotificationDefaultSoundName
        NSUserNotificationCenter.default.deliver(notification)
        completion(true)
    }
}
