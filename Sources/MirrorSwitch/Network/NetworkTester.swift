//
//  NetworkTester.swift
//  MirrorSwitch
//
//  网络测速器
//

import Foundation

/// 网络测速器
final class NetworkTester: @unchecked Sendable {
    /// URLSession 配置
    private let session: URLSession

    /// 超时时间（秒）
    private let timeout: TimeInterval = 3.0

    /// 初始化
    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout
        self.session = URLSession(configuration: config)
    }

    /// 测试指定镜像源的延迟
    /// - Parameter source: 要测试的镜像源
    /// - Returns: 延迟时间（毫秒），如果测试失败则返回 nil
    func testSource(_ source: MirrorSource) async -> (String, Int?) {
        // 优先使用 HTTP HEAD 请求
        if let time = await testHTTP(source.url) {
            return (source.id, time)
        }

        // 失败则降级到 ICMP Ping
        let time = await testICMP(source.url)
        return (source.id, time)
    }

    /// 使用 HTTP HEAD 请求测试延迟
    /// - Parameter urlString: URL 字符串
    /// - Returns: 延迟时间（毫秒），如果测试失败则返回 nil
    private func testHTTP(_ urlString: String) async -> Int? {
        guard let url = URL(string: urlString) else { return nil }

        let start = Date()

        do {
            var request = URLRequest(url: url)
            request.httpMethod = "HEAD"
            request.timeoutInterval = timeout

            let (_, response) = try await session.data(for: request)

            if let httpResponse = response as? HTTPURLResponse,
               httpResponse.statusCode == 200 || httpResponse.statusCode == 301 || httpResponse.statusCode == 302 {
                let elapsed = Date().timeIntervalSince(start) * 1000
                return Int(elapsed)
            }
        } catch {
            // 测试失败，返回 nil 尝试 ICMP
        }

        return nil
    }

    /// 使用 ICMP Ping 测试延迟
    /// - Parameter urlString: URL 字符串
    /// - Returns: 延迟时间（毫秒），如果测试失败则返回 nil
    private func testICMP(_ urlString: String) async -> Int? {
        // 从 URL 中提取主机名
        guard let url = URL(string: urlString),
              let host = url.host else { return nil }

        return await withCheckedContinuation { continuation in
            let pingTask = Process()
            pingTask.executableURL = URL(fileURLWithPath: "/sbin/ping")
            pingTask.arguments = ["-c", "1", "-W", "3000", host]

            let outputPipe = Pipe()
            pingTask.standardOutput = outputPipe
            pingTask.standardError = outputPipe

            do {
                try pingTask.run()
                pingTask.waitUntilExit()

                let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(decoding: outputData, as: UTF8.self)

                // 解析 ping 输出获取时间
                let pingTime = parsePingOutput(output)
                continuation.resume(returning: pingTime)
            } catch {
                continuation.resume(returning: nil)
            }
        }
    }

    /// 解析 ping 命令输出，提取延迟时间
    ///
    /// macOS ping 输出示例：
    /// ```
    /// 64 bytes from 192.168.1.1: icmp_seq=0 ttl=64 time=0.123 ms
    /// ```
    ///
    /// 使用正则表达式 `time=([0-9.]+) ms` 提取时间部分
    ///
    /// - Parameter output: ping 命令输出
    /// - Returns: 延迟时间（毫秒），解析失败返回 nil
    private func parsePingOutput(_ output: String) -> Int? {
        // macOS ping 输出格式: "time=0.123 ms"
        let pattern = "time=([0-9.]+) ms"

        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)),
              let range = Range(match.range(at: 1), in: output) else {
            return nil
        }

        let timeString = String(output[range])
        let timeInSeconds = Double(timeString) ?? 0
        return Int(timeInSeconds * 1000) // 转换为毫秒
    }
}
