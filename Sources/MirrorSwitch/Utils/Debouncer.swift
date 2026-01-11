//
//  Debouncer.swift
//  MirrorSwitch
//
//  防抖器工具类
//  用于避免短时间内多次执行同一个操作
//

import Foundation

/// 防抖器 - 避免短时间内多次执行
final class Debouncer: @unchecked Sendable {
    private var workItem: DispatchWorkItem?
    private let delay: TimeInterval

    /// 初始化防抖器
    /// - Parameter delay: 延迟时间（秒），默认 0.5 秒
    init(delay: TimeInterval = 0.5) {
        self.delay = delay
    }

    /// 防抖执行
    /// - Parameter action: 要执行的操作
    func debounce(_ action: @escaping () -> Void) {
        // 取消之前的任务
        workItem?.cancel()

        // 创建新任务
        workItem = DispatchWorkItem(block: action)

        // 延迟执行
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem!)
    }

    /// 取消待执行的任务
    func cancel() {
        workItem?.cancel()
        workItem = nil
    }
}
