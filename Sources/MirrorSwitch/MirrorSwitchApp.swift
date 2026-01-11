//
//  MirrorSwitchApp.swift
//  MirrorSwitch
//
//  主应用程序文件，包含菜单栏应用的核心实现
//  包括自定义视图类、菜单构建逻辑和用户交互处理
//

import AppKit
import Foundation

// 调试日志辅助函数 - 确保日志立即输出
func debugLog(_ message: String) {
    print(message)
    fflush(stdout)
}

// MARK: - 布局常量

/// 视图布局相关常量
private enum LayoutConstants {
    // MARK: - 一级菜单常量

    /// 一级菜单视图宽度
    static let primaryMenuWidth: CGFloat = 220.0

    /// 一级菜单高度
    static let primaryMenuHeight: CGFloat = 24.0

    /// 工具名左边距
    static let toolNameLeading: CGFloat = 16.0

    /// 版本号与工具名的间距
    static let versionSpacing: CGFloat = 6.0

    /// 版本号最大宽度
    static let versionMaxWidth: CGFloat = 80.0

    /// 源名称与箭头的间距
    static let sourceArrowSpacing: CGFloat = 0.0

    /// 源名称与版本号的间距
    static let sourceVersionSpacing: CGFloat = 8.0

    /// 源名称最大宽度
    static let sourceMaxWidth: CGFloat = 120.0

    /// 箭头右边距
    static let arrowTrailing: CGFloat = -16.0

    /// 箭头宽度
    static let arrowWidth: CGFloat = 12.0

    // MARK: - 二级菜单常量

    /// 二级菜单视图宽度
    static let viewWidth: CGFloat = 220.0

    /// 第一列（对勾）：左边距和宽度
    static let firstColumnLeading: CGFloat = 10.0
    static let firstColumnWidth: CGFloat = 20.0

    /// 第二列（文本）：左边距和宽度
    static let secondColumnLeading: CGFloat = 30.0
    static let secondColumnWidth: CGFloat = 100.0

    /// 第三列（速度/指示器）：右边距和宽度
    /// 速度文字右对齐，距离视图右边缘 4px（与菜单分割线右边缘对齐）
    static let thirdColumnTrailing: CGFloat = -16.0
    static let thirdColumnWidth: CGFloat = 50.0

    /// SpeedTestView 高度
    static let speedTestViewHeight: CGFloat = 28.0

    /// MirrorSourceItemView 高度
    static let sourceItemViewHeight: CGFloat = 24.0
}

/// 颜色阈值常量（毫秒）
private enum SpeedThresholds {
    /// 快速阈值（<100ms 显示绿色）
    static let fast: Int = 100

    /// 中速阈值（100-300ms 显示黄色）
    static let medium: Int = 300
}

// MARK: - AppDelegate

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var menuUpdateHelper: MenuUpdateHelper?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 设置应用为代理应用（不显示 Dock 图标）
        NSApp.setActivationPolicy(.accessory)

        // 检测工具、初始化 SourceManager 和创建菜单
        Task {
            // 0. 加载应用配置
            debugLog("⚙️ 开始加载应用配置...")
            do {
                try await AppConfigManager.shared.loadConfig()
                debugLog("✅ 应用配置加载完成")
            } catch {
                debugLog("⚠️ 应用配置加载失败: \(error.localizedDescription)")
            }

            // 1. 检测已安装的工具并获取版本
            debugLog("🔍 开始检测已安装的工具...")
            var toolVersions: [ToolType: String] = [:]

            for tool in ToolType.allCases {
                if let version = await ToolDetector.shared.getToolVersion(tool) {
                    toolVersions[tool] = version
                    debugLog("✅ 检测到 \(tool.displayName): \(version)")
                } else {
                    debugLog("⚠️ 未检测到 \(tool.displayName)")
                }
            }

            debugLog("✅ 检测完成，发现 \(toolVersions.count) 个工具")

            // 2. 初始化配置驱动管理器（包含备份机制）
            await ConfigurationDrivenSourceManager.shared.initialize()
            await MainActor.run {
                setupStatusBarMenu(with: toolVersions)
            }

            // 5. 为所有检测到的工具自动测速
            debugLog("⚡️ 开始自动测速...")
            for tool in toolVersions.keys {
                // 延迟一点避免同时发起太多请求
                try? await Task.sleep(nanoseconds: UInt64(100_000_000)) // 0.1 秒
                menuUpdateHelper?.startSpeedTest(for: tool)
            }
        }

        // 首次运行时备份配置
        Task {
            await BackupManager.shared.backupIfNeeded()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    @MainActor
    private func setupStatusBarMenu(with toolVersions: [ToolType: String]) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            // 从配置获取菜单图标
            let iconConfig = AppConfigManager.shared.menuBarIcon
            if let image = NSImage(systemSymbolName: iconConfig.systemSymbolName,
                                   accessibilityDescription: AppConfigManager.shared.appDisplayName) {
                button.image = image
            } else {
                button.title = "⚡️"
            }
        }

        // 创建菜单更新助手
        menuUpdateHelper = MenuUpdateHelper(statusItem: statusItem)
        menuUpdateHelper?.setToolVersions(toolVersions)
        menuUpdateHelper?.buildMenu()
    }
}

// MARK: - Menu Update Helper

/// 菜单更新助手
///
/// 负责构建和管理菜单栏应用的菜单结构，包括：
/// - 为每个工具创建子菜单
/// - 管理测速视图的状态更新
/// - 处理镜像源选择事件
/// - 处理重置按钮事件
/// - 在菜单项中显示工具版本信息和当前源
@MainActor
class MenuUpdateHelper: NSObject {
    private weak var statusItem: NSStatusItem?
    private var testingTools: Set<ToolType> = []
    private var speedTestViews: [Int: SpeedTestView] = [:]  // 保存测速按钮 view 引用
    private var sourceItemViews: [Int: [MirrorSourceItemView]] = [:]  // 保存镜像源列表 view 引用
    private var menuItemViews: [ToolType: MenuItemView] = [:]  // 保存一级菜单 view 引用
    private var toolVersions: [ToolType: String] = [:]  // 工具版本信息
    private var toolCurrentSources: [ToolType: MirrorSource] = [:]  // 工具当前选中的源
    private var configManagementWindow: ConfigManagementWindow?  // 配置管理窗口

    init(statusItem: NSStatusItem?) {
        self.statusItem = statusItem
        super.init()
    }

    /// 设置工具版本信息
    func setToolVersions(_ versions: [ToolType: String]) {
        self.toolVersions = versions
        let detectedCount = versions.count
        debugLog("🔍 已检测到 \(detectedCount) 个工具: \(versions.values.joined(separator: ", "))")
    }

    /// 格式化版本号，只保留主要版本号
    private func formatVersion(_ version: String) -> String {
        // 提取版本号（通常是数字开头的部分）
        // 例如: "npm 10.5.0" -> "10.5.0"
        //      "Homebrew 4.1.0" -> "4.1.0"
        //      "Apache Maven 3.9.5" -> "3.9.5"

        // 按空格分割，找第一个像版本号的部分
        let components = version.components(separatedBy: .whitespaces)
        for component in components {
            // 检查是否包含数字和点号（版本号特征）
            if component.contains(where: { $0.isNumber }) {
                // 进一步清理：只保留数字、点和字母（v前缀等）
                let cleaned = component.filter { $0.isNumber || $0 == "." || $0.isLetter }
                if cleaned.count > 2 && cleaned.contains(where: { $0.isNumber }) {
                    return cleaned
                }
            }
        }

        return version
    }

    func buildMenu() {
        guard let statusItem = statusItem else { return }

        let menu = NSMenu()
        menu.delegate = self

        // 为每个工具创建子菜单（包含版本信息和当前源）
        for tool in ToolType.allCases {
            // 获取当前选中的源
            let sources = ConfigurationDrivenSourceManager.shared.getSources(for: tool)
            let currentSource = sources.first(where: { $0.isSelected })
            if let currentSource = currentSource {
                toolCurrentSources[tool] = currentSource
            }

            // 构建标题：工具名 + 版本号（如果有）
            let displayName = tool.displayName
            let formattedVersion = toolVersions[tool].flatMap { formatVersion($0) }

            // 创建自定义视图菜单项
            let menuItemView = MenuItemView(
                frame: NSRect(x: 0, y: 0, width: LayoutConstants.primaryMenuWidth, height: LayoutConstants.primaryMenuHeight),
                toolName: displayName,
                version: formattedVersion,
                sourceName: currentSource?.name ?? "未选择"
            )

            // 保存 MenuItemView 引用
            menuItemViews[tool] = menuItemView

            let menuItem = NSMenuItem()
            menuItem.view = menuItemView
            menu.addItem(menuItem)

            // 创建子菜单
            let submenu = buildSubMenu(for: tool)
            menuItem.submenu = submenu
        }

        // 配置菜单项
        let configMenuItem = createConfigMenuItem()
        menu.addItem(configMenuItem)

        menu.addItem(NSMenuItem.separator())

        // 退出按钮
        let quitItem = NSMenuItem(title: "退出", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    /// 构建指定工具的子菜单
    ///
    /// 子菜单结构：
    /// 1. 测速按钮（SpeedTestView）
    /// 2. 分隔线
    /// 3. 镜像源列表（MirrorSourceItemView）
    /// 4. 分隔线
    /// 5. [可选] 手动选择目录（当无法检测到版本号时显示）
    /// 6. 打开配置文件目录
    /// 7. 重置按钮（ResetButtonView）
    ///
    /// - Parameter tool: 要构建的工具类型
    /// - Returns: 构建好的子菜单
    private func buildSubMenu(for tool: ToolType) -> NSMenu {
        let menu = NSMenu(title: tool.displayName)

        // 测速按钮 - 作为镜像源列表的第一项
        let toolHash = tool.hashValue
        debugLog("🏗️ 创建 SpeedTestView: tool=\(tool.displayName), hash=\(toolHash)")

        let testSpeedView = SpeedTestView(
            frame: NSRect(x: 0, y: 0, width: LayoutConstants.viewWidth, height: LayoutConstants.speedTestViewHeight),
            toolName: tool.displayName,
            toolHash: toolHash,
            isTesting: testingTools.contains(tool)
        )

        // 保存 view 引用
        speedTestViews[toolHash] = testSpeedView
        debugLog("💾 已保存 view 引用，当前 keys: \(speedTestViews.keys)")

        testSpeedView.onAction = { [weak self] toolHash in
            guard let self = self,
                  let tool = ToolType.allCases.first(where: { $0.hashValue == toolHash }) else {
                return
            }
            self.startSpeedTest(for: tool)
        }

        let testSpeedItem = NSMenuItem()
        testSpeedItem.view = testSpeedView
        menu.addItem(testSpeedItem)

        menu.addItem(NSMenuItem.separator())

        // 镜像源列表 - 紧跟在测速按钮后面
        let sources = ConfigurationDrivenSourceManager.shared.getSources(for: tool)
        var views: [MirrorSourceItemView] = []

        for source in sources {
            let sourceItemView = MirrorSourceItemView(
                frame: NSRect(x: 0, y: 0, width: LayoutConstants.viewWidth, height: LayoutConstants.sourceItemViewHeight),
                source: source,
                tool: tool
            )

            sourceItemView.onAction = { [weak self] (source, tool) in
                self?.selectSource(source: source, tool: tool)
            }

            views.append(sourceItemView)

            let sourceItem = NSMenuItem()
            sourceItem.view = sourceItemView
            menu.addItem(sourceItem)
        }

        // 保存 view 引用
        sourceItemViews[tool.hashValue] = views
        debugLog("💾 已保存 \(views.count) 个镜像源 view，tool=\(tool.displayName)")

        menu.addItem(NSMenuItem.separator())

        // 检查是否检测到版本号，如果没有则显示"手动选择目录"选项
        let hasVersion = toolVersions[tool] != nil
        let customPath = ConfigManager.shared.getCustomPath(for: tool)

        if !hasVersion || customPath != nil {
            let customPathView = CustomPathView(
                frame: NSRect(x: 0, y: 0, width: LayoutConstants.viewWidth, height: LayoutConstants.speedTestViewHeight),
                tool: tool,
                currentPath: customPath
            )

            customPathView.onAction = { [weak self] path in
                self?.handleCustomPathSelection(path: path, tool: tool)
            }

            let customPathItem = NSMenuItem()
            customPathItem.view = customPathView
            menu.addItem(customPathItem)
        }

        // 打开配置文件目录
        let openConfigDirView = OpenConfigDirView(
            frame: NSRect(x: 0, y: 0, width: LayoutConstants.viewWidth, height: LayoutConstants.speedTestViewHeight),
            tool: tool
        )
        openConfigDirView.onAction = { [weak self] tool in
            self?.openConfigDirectory(for: tool)
        }

        let openConfigDirItem = NSMenuItem()
        openConfigDirItem.view = openConfigDirView
        menu.addItem(openConfigDirItem)

        // 重置按钮
        let resetButtonView = ResetButtonView(frame: NSRect(x: 0, y: 0, width: LayoutConstants.viewWidth, height: LayoutConstants.speedTestViewHeight))
        resetButtonView.onAction = { [weak self] in
            self?.resetToDefault(for: tool)
        }

        let resetButtonItem = NSMenuItem()
        resetButtonItem.view = resetButtonView
        menu.addItem(resetButtonItem)

        return menu
    }

    private func formatMenuItemTitle(_ source: MirrorSource) -> String {
        var title = source.name

        if source.isSelected {
            title = "✓ " + title
        }

        if let ping = source.pingTime {
            title += " (\(ping)ms)"
        }

        return title
    }

    private func refreshMenu() {
        guard let statusItem = statusItem,
              let menu = statusItem.menu else { return }

        debugLog("🔄 refreshMenu 被调用，准备重建菜单")
        debugLog("🔄 重建前 speedTestViews keys: \(speedTestViews.keys)")

        // 重建整个菜单（最可靠的方式）
        _ = menu  // 保留旧的菜单引用

        // 创建新菜单
        let newMenu = NSMenu()
        newMenu.delegate = self

        // 为每个工具创建子菜单（包含版本信息和当前源）
        for tool in ToolType.allCases {
            // 获取当前选中的源
            let sources = ConfigurationDrivenSourceManager.shared.getSources(for: tool)
            let currentSource = sources.first(where: { $0.isSelected })
            if let currentSource = currentSource {
                toolCurrentSources[tool] = currentSource
            }

            // 构建标题：工具名 + 版本号（如果有）
            let displayName = tool.displayName
            let formattedVersion = toolVersions[tool].flatMap { formatVersion($0) }

            // 创建自定义视图菜单项
            let menuItemView = MenuItemView(
                frame: NSRect(x: 0, y: 0, width: LayoutConstants.primaryMenuWidth, height: LayoutConstants.primaryMenuHeight),
                toolName: displayName,
                version: formattedVersion,
                sourceName: currentSource?.name ?? "未选择"
            )

            let menuItem = NSMenuItem()
            menuItem.view = menuItemView
            newMenu.addItem(menuItem)

            // 创建子菜单
            let submenu = buildSubMenu(for: tool)
            menuItem.submenu = submenu
        }

        // 配置菜单项
        let configMenuItem = createConfigMenuItem()
        newMenu.addItem(configMenuItem)

        newMenu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "退出", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        newMenu.addItem(quitItem)

        statusItem.menu = newMenu

        debugLog("🔄 重建后 speedTestViews keys: \(speedTestViews.keys)")
        print("🔄 refreshMenu 完成")
    }

    /// 开始测速
    ///
    /// 流程：
    /// 1. 将工具添加到测速集合
    /// 2. 更新测速按钮为"测速中..."状态
    /// 3. 并发测试所有镜像源
    /// 4. 更新所有视图的延迟显示
    /// 5. 恢复测速按钮状态
    ///
    /// - Parameter tool: 要测速的工具类型
    func startSpeedTest(for tool: ToolType) {
        let toolHash = tool.hashValue
        debugLog("⚡️ ===== 开始测速 \(tool.displayName) (hash: \(toolHash)) =====")
        debugLog("⚡️ 当前 speedTestViews keys: \(speedTestViews.keys)")
        debugLog("⚡️ 检查 view 是否存在: \(speedTestViews[toolHash] != nil ? "✅ 存在" : "❌ 不存在")")

        testingTools.insert(tool)

        // 直接更新 view 状态为"测速中..."
        debugLog("⚡️ 准备调用 updateSpeedTestView(isTesting: true)")
        updateSpeedTestView(for: tool, isTesting: true)

        // 在后台执行测速
        Task {
            debugLog("⚡️ 后台测速任务开始")
            let sources = ConfigurationDrivenSourceManager.shared.getSources(for: tool)
            await ConfigurationDrivenSourceManager.shared.testSpeed(sources: sources)
            debugLog("⚡️ 后台测速任务完成")

            await MainActor.run {
                debugLog("⚡️ 测速完成，准备移除 \(tool.displayName)")
                self.testingTools.remove(tool)
                debugLog("📝 移除后 testingTools 状态: \(self.testingTools)")

                // 直接更新 view 状态为"测速"
                debugLog("⚡️ 准备调用 updateSpeedTestView(isTesting: false)")
                self.updateSpeedTestView(for: tool, isTesting: false)

                // 更新镜像源列表的延迟显示
                debugLog("⚡️ 准备调用 updateSourceList")
                self.updateSourceList(for: tool)

                debugLog("✓ 菜单已刷新")
                debugLog("⚡️ ===== 测速流程结束 =====")
            }
        }
    }

    private func updateSpeedTestView(for tool: ToolType, isTesting: Bool) {
        let toolHash = tool.hashValue
        debugLog("🔍 updateSpeedTestView 被调用: tool=\(tool.displayName), isTesting=\(isTesting)")
        debugLog("🔍 speedTestViews keys: \(speedTestViews.keys)")
        debugLog("🔍 查找 hash: \(toolHash)")

        guard let view = speedTestViews[toolHash] else {
            debugLog("❌ 找不到对应的 view!")
            return
        }

        debugLog("✅ 找到 view，准备更新状态")
        if isTesting {
            view.setTestingState()
        } else {
            view.setNormalState()
        }
    }

    /// 更新镜像源列表的延迟显示
    ///
    /// 从 SourceManager 获取最新的镜像源数据（包括测速结果），
    /// 并更新所有 MirrorSourceItemView 的显示内容。
    ///
    /// - Parameter tool: 要更新的工具类型
    private func updateSourceList(for tool: ToolType) {
        let toolHash = tool.hashValue
        guard let views = sourceItemViews[toolHash] else {
            debugLog("❌ 找不到 tool=\(tool.displayName) 的镜像源 view")
            return
        }

        debugLog("🔄 更新 \(tool.displayName) 的镜像源列表，共 \(views.count) 个 view")

        // 获取最新的镜像源数据
        let sources = ConfigurationDrivenSourceManager.shared.getSources(for: tool)

        // 更新每个 view 的数据
        for (index, view) in views.enumerated() {
            if index < sources.count {
                let source = sources[index]
                view.updateSource(source)
            }
        }

        debugLog("✅ 镜像源列表更新完成")
    }

    /// 更新一级菜单的当前源显示
    ///
    /// 直接更新 MenuItemView 的源名称文本，而不重建整个菜单。
    /// 这样可以在菜单打开时实时更新显示。
    ///
    /// - Parameter tool: 要更新的工具类型
    func updatePrimaryMenuItem(for tool: ToolType) {
        guard let menuItemView = menuItemViews[tool] else {
            debugLog("❌ 找不到 tool=\(tool.displayName) 的一级菜单 view")
            return
        }

        // 从 toolCurrentSources 获取当前选中的源
        guard let currentSource = toolCurrentSources[tool] else {
            // 没有选中的源，显示"未选择"
            menuItemView.updateSourceName("")
            debugLog("✅ 一级菜单已更新: \(tool.displayName) -> 未选择")
            return
        }

        // 更新显示的源名称
        menuItemView.updateSourceName(currentSource.name)
        debugLog("✅ 一级菜单已更新: \(tool.displayName) -> \(currentSource.name)")
    }

    @objc private func selectSource(_ sender: NSMenuItem) {
        guard let source = sender.representedObject as? MirrorSource,
              let tool = ToolType.allCases.first(where: { $0.hashValue == sender.tag }) else {
            return
        }

        print("🔄 选择 \(tool.displayName) 镜像源: \(source.name)")

        Task {
            do {
                try await ConfigurationDrivenSourceManager.shared.switchSource(tool: tool, source: source)
                await MainActor.run {
                    self.refreshMenu()
                }
            } catch {
                print("❌ 切换失败: \(error.localizedDescription)")
            }
        }
    }

    // 新的选择方法，用于 MirrorSourceItemView
    /// 选择镜像源
    ///
    /// 流程：
    /// 1. 更新内存中的选中状态
    /// 2. 调用 SourceManager 执行切换
    /// 3. 保存选中状态到文件
    /// 4. 更新所有视图的对勾显示
    /// 5. 更新一级菜单显示当前源名称
    /// 6. 如果是 OrbStack，显示重启提示对话框
    ///
    /// - Parameters:
    ///   - source: 要切换到的镜像源
    ///   - tool: 工具类型
    func selectSource(source: MirrorSource, tool: ToolType) {
        debugLog("🔄 选择 \(tool.displayName) 镜像源: \(source.name)")

        Task {
            do {
                try await ConfigurationDrivenSourceManager.shared.switchSource(tool: tool, source: source)
                await MainActor.run {
                    // 更新 toolCurrentSources 字典
                    self.toolCurrentSources[tool] = source

                    // 直接更新镜像源列表的对勾状态
                    self.updateSourceList(for: tool)

                    // 更新一级菜单的显示（不关闭菜单）
                    self.updatePrimaryMenuItem(for: tool)

                    // 如果是 OrbStack，显示重启提示对话框
                    if tool.rawValue == "orbstack" {
                        // 关闭当前打开的菜单（内部会处理恢复和刷新）
                        self.closeMenu()
                        // 延迟显示弹窗，确保菜单已完全关闭
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            self.showOrbStackRestartAlert()
                        }
                    }
                }
            } catch {
                debugLog("❌ 切换失败: \(error.localizedDescription)")
            }
        }
    }

    /// 关闭当前打开的菜单
    private func closeMenu() {
        guard let statusItem = statusItem,
              let menu = statusItem.menu else {
            return
        }
        // 取消所有菜单追踪，关闭打开的菜单
        menu.cancelTracking()

        // 额外确保：临时移除菜单，强制关闭任何打开的子菜单
        let oldMenu = statusItem.menu
        statusItem.menu = nil
        // 短暂延迟后恢复菜单
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) { [weak self] in
            statusItem.menu = oldMenu
            // 重新构建菜单以确保数据是最新的
            self?.refreshMenu()
        }
    }

    /// 显示 OrbStack 重启提示对话框
    private func showOrbStackRestartAlert() {
        let alert = NSAlert()
        alert.messageText = "OrbStack 配置已更新"
        alert.informativeText = """
        镜像源配置已成功修改。

        要使配置生效，需要重启 OrbStack Docker 引擎。

        是否立即重启？
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "稍后重启")
        alert.addButton(withTitle: "立即重启")

        // 菜单栏应用直接使用 runModal，对话框会居中显示
        let response = alert.runModal()
        if response == .alertSecondButtonReturn {
            restartOrbStackDocker()
        }
    }

    /// 重启 OrbStack Docker 引擎
    private func restartOrbStackDocker() {
        debugLog("🔄 重启 OrbStack Docker 引擎...")

        Task {
            do {
                let result = try await ShellExecutor.execute(
                    "/usr/local/bin/orb",
                    arguments: ["restart", "docker"]
                )

                if result.exitCode == 0 {
                    await MainActor.run {
                        debugLog("✅ OrbStack Docker 引擎已重启")
                        self.showRestartSuccessAlert()
                    }
                } else {
                    let error = result.standardError.isEmpty ? result.standardOutput : result.standardError
                    await MainActor.run {
                        debugLog("❌ 重启失败: \(error)")
                        self.showRestartFailedAlert(error: error)
                    }
                }
            } catch {
                await MainActor.run {
                    debugLog("❌ 重启失败: \(error.localizedDescription)")
                    self.showRestartFailedAlert(error: error.localizedDescription)
                }
            }
        }
    }

    /// 显示重启成功提示
    private func showRestartSuccessAlert() {
        let alert = NSAlert()
        alert.messageText = "重启成功"
        alert.informativeText = "OrbStack Docker 引擎已成功重启，新配置已生效。"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "确定")

        // 菜单栏应用直接使用 runModal，对话框会居中显示
        alert.runModal()
    }

    /// 显示重启失败提示
    private func showRestartFailedAlert(error: String) {
        let alert = NSAlert()
        alert.messageText = "重启失败"
        alert.informativeText = """
        OrbStack Docker 引擎重启失败。

        错误信息：\(error)

        请手动在终端中运行以下命令：
        orb restart docker
        """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "确定")

        // 菜单栏应用直接使用 runModal，对话框会居中显示
        alert.runModal()
    }

    /// 显示 OrbStack 重启提示对话框（重置后）
    /// 重启完成后会重新检测当前镜像源并更新 UI
    private func showOrbStackRestartAlertAfterReset() {
        let alert = NSAlert()
        alert.messageText = "OrbStack 配置已恢复"
        alert.informativeText = """
        默认配置已成功恢复。

        要使配置生效，需要重启 OrbStack Docker 引擎。

        是否立即重启？
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "稍后重启")
        alert.addButton(withTitle: "立即重启")

        // 菜单栏应用直接使用 runModal，对话框会居中显示
        let response = alert.runModal()
        if response == .alertSecondButtonReturn {
            restartOrbStackDockerAndRedetect()
        }
    }

    /// 重启 OrbStack Docker 引擎并重新检测镜像源
    private func restartOrbStackDockerAndRedetect() {
        debugLog("🔄 重启 OrbStack Docker 引擎...")

        Task {
            do {
                let result = try await ShellExecutor.execute(
                    "/usr/local/bin/orb",
                    arguments: ["restart", "docker"]
                )

                if result.exitCode == 0 {
                    debugLog("✅ OrbStack Docker 引擎已重启")

                    // 重启后重新检测当前镜像源
                    await ConfigurationDrivenSourceManager.shared.initialize()

                    await MainActor.run {
                        debugLog("✅ OrbStack 镜像源已重新检测")
                        self.showRestartSuccessAlert()
                        // 更新 UI 显示
                        if let orbstackTool = ToolType(rawValue: "orbstack") {
                            self.updateSourceList(for: orbstackTool)
                        }
                        // 刷新整个菜单
                        self.refreshMenu()
                    }
                } else {
                    let error = result.standardError.isEmpty ? result.standardOutput : result.standardError
                    await MainActor.run {
                        debugLog("❌ 重启失败: \(error)")
                        self.showRestartFailedAlert(error: error)
                    }
                }
            } catch {
                await MainActor.run {
                    debugLog("❌ 重启失败: \(error.localizedDescription)")
                    self.showRestartFailedAlert(error: error.localizedDescription)
                }
            }
        }
    }

    /// 处理自定义路径选择
    ///
    /// 当用户手动选择工具目录后：
    /// 1. 保存路径到配置文件
    /// 2. 尝试重新检测工具版本
    /// 3. 如果检测成功，刷新菜单显示
    /// 4. 如果是 Maven 或 OrbStack，自动备份原始配置
    ///
    /// - Parameters:
    ///   - path: 用户选择的目录路径
    ///   - tool: 工具类型
    func handleCustomPathSelection(path: String, tool: ToolType) {
        debugLog("💾 保存 \(tool.displayName) 自定义路径: \(path)")

        // 保存路径到配置文件
        ConfigManager.shared.saveCustomPath(tool: tool, path: path)

        // 在后台尝试重新检测版本
        Task {
            debugLog("🔍 使用自定义路径重新检测 \(tool.displayName) 版本...")

            // 尝试从自定义路径检测工具
            let detected = await detectToolWithCustomPath(tool: tool, path: path)

            await MainActor.run {
                if let version = detected {
                    // 检测成功，更新版本信息
                    toolVersions[tool] = version
                    debugLog("✅ 检测成功: \(version)")
                } else {
                    debugLog("⚠️ 仍无法从自定义路径检测版本")
                }

                // 刷新菜单显示
                self.refreshMenu()
            }
        }
    }

    /// 使用自定义路径检测工具版本
    ///
    /// - Parameters:
    ///   - tool: 工具类型
    ///   - path: 自定义路径
    /// - Returns: 版本字符串，检测失败返回 nil
    private func detectToolWithCustomPath(tool: ToolType, path: String) async -> String? {
        // 构建可能的可执行文件路径
        let executableNames = [
            tool.detectionCommand,
            "\(tool.detectionCommand).sh",
            "bin/\(tool.detectionCommand)",
            "bin/\(tool.detectionCommand).sh"
        ]

        for name in executableNames {
            let fullPath = "\(path)/\(name)"

            // 检查文件是否存在且可执行
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: fullPath, isDirectory: &isDir),
                  !isDir.boolValue else {
                continue
            }

            guard FileManager.default.isExecutableFile(atPath: fullPath) else {
                continue
            }

            debugLog("✅ 找到可执行文件: \(fullPath)")

            // 尝试获取版本信息
            let command = "\"\(fullPath)\" \(tool.versionArguments.joined(separator: " "))"
            let result = try? await ShellExecutor.execute(
                "/bin/sh",
                arguments: ["-lc", command]
            )

            if let output = result?.standardOutput, !output.isEmpty {
                let lines = output.components(separatedBy: .newlines)
                let versionLine = lines.first?.trimmingCharacters(in: .whitespaces)

                if let version = versionLine,
                   !version.lowercased().contains("not found") &&
                   !version.lowercased().contains("command not found") &&
                   !version.lowercased().contains("error") {
                    debugLog("✅ 版本信息: \(version)")
                    return version
                }
            }
        }

        return nil
    }

    /// 打开配置文件目录
    ///
    /// 在 Finder 中打开工具的配置文件所在目录
    /// - Parameter tool: 工具类型
    func openConfigDirectory(for tool: ToolType) {
        debugLog("📂 打开 \(tool.displayName) 配置文件目录")

        // 从工具类型获取配置文件目录
        let configDirString = tool.configDirectory
        let configDir = URL(fileURLWithPath: (configDirString as NSString).expandingTildeInPath)

        // 检查目录是否存在
        if !FileManager.default.fileExists(atPath: configDir.path) {
            debugLog("❌ 配置文件目录不存在: \(configDir.path)")
            showConfigDirNotFoundAlert(for: tool)
            return
        }

        // 在 Finder 中打开目录
        NSWorkspace.shared.open(configDir)
        debugLog("✅ 已在 Finder 中打开: \(configDir.path)")
    }

    /// 显示配置文件目录未找到的提示
    private func showConfigDirNotFoundAlert(for tool: ToolType) {
        let alert = NSAlert()
        alert.messageText = "无法找到配置文件目录"
        alert.informativeText = """
        无法找到 \(tool.displayName) 的配置文件目录。

        请确保 \(tool.displayName) 已正确安装。
        """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "确定")

        // 菜单栏应用直接使用 runModal，对话框会居中显示
        alert.runModal()
    }

    // 重置为默认配置
    func resetToDefault(for tool: ToolType) {
        debugLog("🔄 重置 \(tool.displayName) 为默认配置")

        Task {
            do {
                try await ConfigurationDrivenSourceManager.shared.restoreConfig(for: tool)

                // 重新检测当前使用的镜像源
                await ConfigurationDrivenSourceManager.shared.detectCurrentSource(for: tool.rawValue)

                // 同步更新 toolCurrentSources（从 ConfigurationDrivenSourceManager 获取最新状态）
                let sourceId = ConfigurationDrivenSourceManager.shared.getCurrentSelection(toolId: tool.rawValue)
                let sources = ConfigurationDrivenSourceManager.shared.getSources(for: tool)

                if let sourceId = sourceId,
                   let currentSource = sources.first(where: { $0.id == sourceId }) {
                    // 有匹配的镜像源
                    toolCurrentSources[tool] = currentSource
                } else {
                    // 没有匹配的镜像源，清除缓存
                    toolCurrentSources.removeValue(forKey: tool)
                }

                await MainActor.run {
                    // 直接更新镜像源列表的对勾状态
                    self.updateSourceList(for: tool)

                    // 更新一级菜单的显示
                    self.updatePrimaryMenuItem(for: tool)

                    debugLog("✅ \(tool.displayName) 已重置为默认配置")
                }

                // 如果是 OrbStack，需要重启 Docker 引擎使配置生效
                if tool.rawValue == "orbstack" {
                    await MainActor.run {
                        // 关闭当前打开的菜单（内部会处理恢复和刷新）
                        self.closeMenu()
                        // 延迟显示弹窗，确保菜单已完全关闭
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            self.showOrbStackRestartAlertAfterReset()
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    debugLog("❌ 重置失败: \(error.localizedDescription)")
                }
            }
        }
    }

    /// 创建配置菜单项
    private func createConfigMenuItem() -> NSMenuItem {
        // 创建配置菜单项视图
        let configItemView = MenuItemView(
            frame: NSRect(x: 0, y: 0, width: LayoutConstants.primaryMenuWidth, height: LayoutConstants.primaryMenuHeight),
            toolName: "⚙️ 配置...",
            version: nil,
            sourceName: ""
        )

        // 隐藏箭头（配置菜单项不需要箭头）
        if let arrowTextField = configItemView.arrowTextField {
            arrowTextField.isHidden = true
        }

        let menuItem = NSMenuItem()
        menuItem.view = configItemView

        // 设置点击事件
        menuItem.target = self
        menuItem.action = #selector(openConfigWindow)

        return menuItem
    }

    /// 打开配置管理窗口
    @objc private func openConfigWindow() {
        // 延迟执行，确保菜单已关闭
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if self.configManagementWindow == nil {
                self.configManagementWindow = ConfigManagementWindow()
            }
            self.configManagementWindow?.show()
        }
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}

// MARK: - NSMenuDelegate

extension MenuUpdateHelper: NSMenuDelegate {
    func menuDidClose(_ menu: NSMenu) {
        // 菜单关闭时的处理（如果需要）
    }
}

// MARK: - Custom Path View (手动选择目录)

/// 手动选择目录视图
///
/// 使用 Auto Layout 实现三列布局：
/// - 第一列：预留对勾位置（空）
/// - 第二列："手动选择目录"文字
/// - 第三列：已选择的路径（简略显示）
///
/// 功能：
/// - 点击打开 NSOpenPanel 选择工具目录
/// - 保存用户选择的路径到配置文件
/// - 点击不关闭菜单
class CustomPathView: NSView {
    private let tool: ToolType
    private var textField: NSTextField!
    private var pathField: NSTextField?
    var onAction: ((String) -> Void)?

    init(frame frameRect: NSRect, tool: ToolType, currentPath: String?) {
        self.tool = tool
        super.init(frame: frameRect)
        setupView(currentPath: currentPath)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupView(currentPath: String?) {
        wantsLayer = true
        layer?.backgroundColor = .clear

        // 第二列："手动选择目录"文字
        textField = NSTextField(labelWithString: "手动选择目录")
        textField.font = NSFont.systemFont(ofSize: 12)
        textField.textColor = .systemOrange
        textField.isEditable = false
        textField.isSelectable = false
        textField.isBordered = false
        textField.backgroundColor = .clear
        textField.translatesAutoresizingMaskIntoConstraints = false
        addSubview(textField)

        // 如果已有自定义路径，显示简略路径
        if let path = currentPath {
            pathField = NSTextField(labelWithString: abbreviatePath(path))
            pathField?.font = NSFont.systemFont(ofSize: 10)
            pathField?.textColor = .secondaryLabelColor
            pathField?.alignment = .right
            pathField?.isEditable = false
            pathField?.isSelectable = false
            pathField?.isBordered = false
            pathField?.backgroundColor = .clear
            pathField?.translatesAutoresizingMaskIntoConstraints = false
            if let pathField = pathField {
                addSubview(pathField)
            }
        }

        // 使用 Auto Layout 约束
        if let pathField = pathField {
            NSLayoutConstraint.activate([
                textField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: LayoutConstants.secondColumnLeading),
                textField.centerYAnchor.constraint(equalTo: centerYAnchor),
                textField.widthAnchor.constraint(equalToConstant: LayoutConstants.secondColumnWidth),
                pathField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: LayoutConstants.thirdColumnTrailing),
                pathField.centerYAnchor.constraint(equalTo: centerYAnchor),
                pathField.widthAnchor.constraint(equalToConstant: LayoutConstants.thirdColumnWidth + 30)
            ])
        } else {
            NSLayoutConstraint.activate([
                textField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: LayoutConstants.secondColumnLeading),
                textField.centerYAnchor.constraint(equalTo: centerYAnchor)
            ])
        }
    }

    override func mouseDown(with event: NSEvent) {
        debugLog("🖱️ CustomPathView mouseDown 被调用")

        // 打开目录选择对话框
        openDirectoryPicker()

        // 不调用 super.mouseDown，避免菜单关闭
    }

    override func mouseEntered(with event: NSEvent) {
        layer?.backgroundColor = .clear
        textField.textColor = .systemOrange.withAlphaComponent(0.7)
    }

    override func mouseExited(with event: NSEvent) {
        layer?.backgroundColor = .clear
        textField.textColor = .systemOrange
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        trackingAreas.forEach { removeTrackingArea($0) }

        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
    }

    /// 打开目录选择对话框
    private func openDirectoryPicker() {
        let panel = NSOpenPanel()
        panel.title = "选择 \(tool.displayName) 安装目录"
        panel.prompt = "选择"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser

        panel.begin { [weak self] result in
            guard let self = self, result == .OK, let url = panel.url else {
                return
            }

            let selectedPath = url.path
            debugLog("✅ 用户选择了目录: \(selectedPath)")

            // 校验路径是否正确
            if !self.validateToolPath(selectedPath) {
                debugLog("❌ 路径校验失败: \(selectedPath)")
                self.showValidationAlert(selectedPath)
                return
            }

            debugLog("✅ 路径校验通过")

            // 更新显示
            self.updatePathDisplay(selectedPath)

            // 通知外部保存路径
            self.onAction?(selectedPath)
        }
    }

    /// 校验工具路径是否正确
    /// - Parameter path: 用户选择的路径
    /// - Returns: 路径是否有效
    private func validateToolPath(_ path: String) -> Bool {
        // 检查可执行文件是否存在
        let executableNames = [
            tool.detectionCommand,
            "\(tool.detectionCommand).sh",
            "bin/\(tool.detectionCommand)",
            "bin/\(tool.detectionCommand).sh"
        ]

        for name in executableNames {
            let fullPath = "\(path)/\(name)"

            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: fullPath, isDirectory: &isDir),
                  !isDir.boolValue else {
                continue
            }

            guard FileManager.default.isExecutableFile(atPath: fullPath) else {
                continue
            }

            debugLog("✅ 找到可执行文件: \(fullPath)")
            return true
        }

        return false
    }

    /// 显示路径校验失败的警告
    /// - Parameter path: 校验失败的路径
    private func showValidationAlert(_ path: String) {
        let alert = NSAlert()
        alert.messageText = "无效的 \(tool.displayName) 安装目录"
        alert.informativeText = """
        在选定目录中未找到 \(tool.displayName) 可执行文件。

        请确保选择的目录包含以下文件之一：
        • \(tool.detectionCommand)
        • \(tool.detectionCommand).sh
        • bin/\(tool.detectionCommand)
        • bin/\(tool.detectionCommand).sh

        选定路径: \(path)
        """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "重新选择")
        alert.addButton(withTitle: "取消")

        // 菜单栏应用直接使用 runModal，对话框会居中显示
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            // 用户点击"重新选择"，重新打开选择面板
            openDirectoryPicker()
        }
    }

    /// 更新路径显示
    private func updatePathDisplay(_ path: String) {
        // 移除旧的路径显示
        pathField?.removeFromSuperview()

        // 创建新的路径显示
        pathField = NSTextField(labelWithString: abbreviatePath(path))
        pathField?.font = NSFont.systemFont(ofSize: 10)
        pathField?.textColor = .secondaryLabelColor
        pathField?.alignment = .right
        pathField?.isEditable = false
        pathField?.isSelectable = false
        pathField?.isBordered = false
        pathField?.backgroundColor = .clear
        pathField?.translatesAutoresizingMaskIntoConstraints = false

        if let pathField = pathField {
            addSubview(pathField)
            NSLayoutConstraint.activate([
                pathField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: LayoutConstants.thirdColumnTrailing),
                pathField.centerYAnchor.constraint(equalTo: centerYAnchor),
                pathField.widthAnchor.constraint(equalToConstant: LayoutConstants.thirdColumnWidth + 30)
            ])
        }

        setNeedsDisplay(bounds)
    }

    /// 简略显示路径（只显示最后两段）
    private func abbreviatePath(_ path: String) -> String {
        let components = (path as NSString).pathComponents
        if components.count > 3 {
            return ".../" + components.suffix(2).joined(separator: "/")
        }
        return path
    }
}

// MARK: - Open Config Directory View (打开配置文件目录)

/// 打开配置文件目录视图
///
/// 使用 Auto Layout 实现三列布局：
/// - 第一列：预留对勾位置（空）
/// - 第二列："打开配置文件目录"文字
/// - 第三列：空
///
/// 功能：
/// - 点击在 Finder 中打开配置文件所在目录
/// - 点击不关闭菜单
class OpenConfigDirView: NSView {
    private let tool: ToolType
    private var textField: NSTextField!
    var onAction: ((ToolType) -> Void)?

    init(frame frameRect: NSRect, tool: ToolType) {
        self.tool = tool
        super.init(frame: frameRect)
        setupView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupView() {
        wantsLayer = true
        layer?.backgroundColor = .clear

        textField = NSTextField(labelWithString: "打开配置文件目录")
        textField.font = NSFont.systemFont(ofSize: 12)
        textField.textColor = .systemPurple
        textField.isEditable = false
        textField.isSelectable = false
        textField.isBordered = false
        textField.backgroundColor = .clear
        textField.translatesAutoresizingMaskIntoConstraints = false
        addSubview(textField)

        // 第二列："打开配置文件目录"文字（Auto Layout 约束）
        NSLayoutConstraint.activate([
            textField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: LayoutConstants.secondColumnLeading),
            textField.centerYAnchor.constraint(equalTo: centerYAnchor),
            textField.widthAnchor.constraint(equalToConstant: LayoutConstants.secondColumnWidth)
        ])
    }

    override func mouseDown(with event: NSEvent) {
        debugLog("🖱️ OpenConfigDirView mouseDown 被调用")

        // 执行打开目录逻辑
        onAction?(tool)

        // 不调用 super.mouseDown，避免菜单关闭
    }

    override func mouseEntered(with event: NSEvent) {
        layer?.backgroundColor = .clear
        textField.textColor = .systemPurple.withAlphaComponent(0.7)
    }

    override func mouseExited(with event: NSEvent) {
        layer?.backgroundColor = .clear
        textField.textColor = .systemPurple
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        trackingAreas.forEach { removeTrackingArea($0) }

        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
    }
}

// MARK: - Reset Button View (重置按钮)

/// 重置按钮视图
///
/// 使用 Auto Layout 实现三列布局：
/// - 第一列：预留对勾位置（空）
/// - 第二列："重置为默认配置"文字
/// - 第三列：空
///
/// 功能：
/// - 点击恢复到官方镜像源
/// - 点击不关闭菜单
class ResetButtonView: NSView {
    private var textField: NSTextField!
    var onAction: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupView() {
        wantsLayer = true
        layer?.backgroundColor = .clear

        textField = NSTextField(labelWithString: "重置为默认配置")
        textField.font = NSFont.systemFont(ofSize: 12)
        textField.textColor = .systemBlue
        textField.isEditable = false
        textField.isSelectable = false
        textField.isBordered = false
        textField.backgroundColor = .clear
        textField.translatesAutoresizingMaskIntoConstraints = false
        addSubview(textField)

        // 第二列："重置为默认配置"文字（Auto Layout 约束）
        NSLayoutConstraint.activate([
            textField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: LayoutConstants.secondColumnLeading),
            textField.centerYAnchor.constraint(equalTo: centerYAnchor),
            textField.widthAnchor.constraint(equalToConstant: LayoutConstants.secondColumnWidth)
        ])
    }

    override func mouseDown(with event: NSEvent) {
        debugLog("🖱️ ResetButtonView mouseDown 被调用")

        // 执行重置逻辑
        onAction?()

        // 关键：不调用 super.mouseDown(with: event)
        // 这样系统就不会认为菜单项被"选中"了，菜单也就不会关闭
    }

    override func mouseEntered(with event: NSEvent) {
        layer?.backgroundColor = .clear
        textField.textColor = .systemBlue.withAlphaComponent(0.7)
    }

    override func mouseExited(with event: NSEvent) {
        layer?.backgroundColor = .clear
        textField.textColor = .systemBlue
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        trackingAreas.forEach { removeTrackingArea($0) }

        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
    }
}

// MARK: - Mirror Source Item View (三列布局)

/// 镜像源列表项视图
///
/// 使用 Auto Layout 实现三列布局：
/// - 第一列：对勾（20px 宽，左对齐）
/// - 第二列：镜像源名称（100px 宽）
/// - 第三列：测速速度（48px 宽，右对齐）
///
/// 交互特性：
/// - 点击不关闭菜单（重写 mouseDown 不调用 super）
/// - 点击触发镜像源切换
class MirrorSourceItemView: NSView {
    private let source: MirrorSource
    private let tool: ToolType
    private var checkField: NSTextField!   // 选中状态（对勾）
    private var nameField: NSTextField!   // 镜像源名称
    private var speedField: NSTextField!  // 测速速度
    var onAction: ((MirrorSource, ToolType) -> Void)?

    init(frame: NSRect, source: MirrorSource, tool: ToolType) {
        self.source = source
        self.tool = tool
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        wantsLayer = true
        layer?.backgroundColor = .clear

        // 第一列：选中状态（20px）
        checkField = NSTextField(labelWithString: source.isSelected ? "✓" : "")
        checkField.font = NSFont.systemFont(ofSize: 12)
        checkField.alignment = .center
        checkField.isEditable = false
        checkField.isSelectable = false
        checkField.isBordered = false
        checkField.backgroundColor = .clear
        checkField.translatesAutoresizingMaskIntoConstraints = false
        addSubview(checkField)

        // 第二列：镜像源名称（100px）
        nameField = NSTextField(labelWithString: source.name)
        nameField.font = NSFont.systemFont(ofSize: 12)
        nameField.isEditable = false
        nameField.isSelectable = false
        nameField.isBordered = false
        nameField.backgroundColor = .clear
        nameField.translatesAutoresizingMaskIntoConstraints = false
        addSubview(nameField)

        // 第三列：测速速度（右对齐）
        let speedText: String
        let color: NSColor
        if let ping = source.pingTime {
            speedText = "\(ping)ms"
            color = ping < SpeedThresholds.fast ? .systemGreen : ping < SpeedThresholds.medium ? .systemYellow : .systemRed
        } else {
            speedText = "---"
            color = .systemGray
        }
        speedField = NSTextField(labelWithString: speedText)
        speedField.font = NSFont.systemFont(ofSize: 12)
        speedField.textColor = color
        speedField.alignment = .right
        speedField.isEditable = false
        speedField.isSelectable = false
        speedField.isBordered = false
        speedField.backgroundColor = .clear
        speedField.translatesAutoresizingMaskIntoConstraints = false
        addSubview(speedField)

        // 使用 Auto Layout 约束
        NSLayoutConstraint.activate([
            // 第一列：对勾（左对齐，固定宽度）
            checkField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: LayoutConstants.firstColumnLeading),
            checkField.centerYAnchor.constraint(equalTo: centerYAnchor),
            checkField.widthAnchor.constraint(equalToConstant: LayoutConstants.firstColumnWidth),

            // 第二列：镜像源名称
            nameField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: LayoutConstants.secondColumnLeading),
            nameField.centerYAnchor.constraint(equalTo: centerYAnchor),
            nameField.widthAnchor.constraint(equalToConstant: LayoutConstants.secondColumnWidth),

            // 第三列：测速速度（右对齐到视图边缘）
            speedField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: LayoutConstants.thirdColumnTrailing),
            speedField.centerYAnchor.constraint(equalTo: centerYAnchor),
            speedField.widthAnchor.constraint(equalToConstant: LayoutConstants.thirdColumnWidth)
        ])
    }

    // 关键：重写 mouseDown，但不调用 super
    override func mouseDown(with event: NSEvent) {
        debugLog("🖱️ MirrorSourceItemView mouseDown 被调用: \(source.name)")

        // 执行选择逻辑
        onAction?(source, tool)

        // 关键：不调用 super.mouseDown(with: event)
        // 这样系统就不会认为菜单项被"选中"了，菜单也就不会关闭
    }

    override func mouseEntered(with event: NSEvent) {
        layer?.backgroundColor = .clear
    }

    override func mouseExited(with event: NSEvent) {
        layer?.backgroundColor = .clear
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        trackingAreas.forEach { removeTrackingArea($0) }

        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
    }

    func updateSource(_ source: MirrorSource) {
        // 更新选中状态（对勾）
        checkField.stringValue = source.isSelected ? "✓" : ""

        // 更新速度显示
        let speedText: String
        let color: NSColor
        if let ping = source.pingTime {
            speedText = "\(ping)ms"
            color = ping < SpeedThresholds.fast ? .systemGreen : ping < SpeedThresholds.medium ? .systemYellow : .systemRed
        } else {
            speedText = "---"
            color = .systemGray
        }
        speedField.stringValue = speedText
        speedField.textColor = color

        setNeedsDisplay(bounds)
    }
}

// MARK: - Custom Speed Test View

/// 测速按钮视图
///
/// 使用 Auto Layout 实现三列布局：
/// - 第一列：预留对勾位置（空）
/// - 第二列："测速"文字
/// - 第三列：旋转指示器（右对齐）
///
/// 状态管理：
/// - 正常状态：显示"测速"文字
/// - 测速状态：显示"测速中..."和旋转指示器
///
/// 交互特性：
/// - 点击触发测速
/// - 点击不关闭菜单
class SpeedTestView: NSView {
    let toolName: String
    let toolHash: Int
    var isTesting: Bool
    var onAction: ((Int) -> Void)?

    private var textField: NSTextField!
    private var activityIndicator: NSProgressIndicator?

    init(frame frameRect: NSRect, toolName: String, toolHash: Int, isTesting: Bool) {
        self.toolName = toolName
        self.toolHash = toolHash
        self.isTesting = isTesting
        super.init(frame: frameRect)
        setupView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupView() {
        wantsLayer = true
        layer?.backgroundColor = .clear

        let title = isTesting ? "测速中..." : "测速"
        textField = NSTextField(labelWithString: title)
        textField.font = NSFont.systemFont(ofSize: 12)
        textField.isEditable = false
        textField.isSelectable = false
        textField.isBordered = false
        textField.backgroundColor = .clear
        textField.translatesAutoresizingMaskIntoConstraints = false
        addSubview(textField)

        // 第二列："测速"文字（Auto Layout 约束）
        NSLayoutConstraint.activate([
            textField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: LayoutConstants.secondColumnLeading),
            textField.centerYAnchor.constraint(equalTo: centerYAnchor),
            textField.widthAnchor.constraint(equalToConstant: LayoutConstants.secondColumnWidth - 2)
        ])

        if isTesting {
            let indicator = NSProgressIndicator()
            indicator.style = .spinning
            indicator.startAnimation(nil)
            indicator.translatesAutoresizingMaskIntoConstraints = false
            addSubview(indicator)
            activityIndicator = indicator

            // 第三列：旋转指示器（右对齐到视图边缘，Auto Layout 约束）
            NSLayoutConstraint.activate([
                indicator.trailingAnchor.constraint(equalTo: trailingAnchor, constant: LayoutConstants.thirdColumnTrailing),
                indicator.centerYAnchor.constraint(equalTo: centerYAnchor),
                indicator.widthAnchor.constraint(equalToConstant: 16),
                indicator.heightAnchor.constraint(equalToConstant: 16)
            ])
        }
    }

    // 关键：重写 mouseDown，但不调用 super
    override func mouseDown(with event: NSEvent) {
        debugLog("🖱️ SpeedTestView mouseDown 被调用")

        // 更新 UI
        setTestingState()

        // 执行测速逻辑
        onAction?(toolHash)

        // 关键：不调用 super.mouseDown(with: event)
        // 这样系统就不会认为菜单项被"选中"了，菜单也就不会关闭
    }

    func setTestingState() {
        debugLog("🔄 设置为测速状态")
        textField?.stringValue = "测速中..."

        // 添加活动指示器
        if activityIndicator == nil {
            let indicator = NSProgressIndicator()
            indicator.style = .spinning
            indicator.startAnimation(nil)
            indicator.translatesAutoresizingMaskIntoConstraints = false
            addSubview(indicator)
            activityIndicator = indicator

            // 第三列：旋转指示器（右对齐到视图边缘，Auto Layout 约束）
            NSLayoutConstraint.activate([
                indicator.trailingAnchor.constraint(equalTo: trailingAnchor, constant: LayoutConstants.thirdColumnTrailing),
                indicator.centerYAnchor.constraint(equalTo: centerYAnchor),
                indicator.widthAnchor.constraint(equalToConstant: 16),
                indicator.heightAnchor.constraint(equalToConstant: 16)
            ])
        }

        // 强制刷新视图
        debugLog("🔄 setTestingState: 调用 setNeedsDisplay()")
        setNeedsDisplay(bounds)
    }

    func setNormalState() {
        debugLog("✅ 设置为正常状态")
        debugLog("✅ 当前 textField 值: \(textField?.stringValue ?? "nil")")
        textField?.stringValue = "测速"
        debugLog("✅ 设置后 textField 值: \(textField?.stringValue ?? "nil")")

        // 移除活动指示器
        if let indicator = activityIndicator {
            debugLog("✅ 移除活动指示器")
            indicator.stopAnimation(nil)
            indicator.removeFromSuperview()
            activityIndicator = nil
        }

        // 强制刷新视图
        debugLog("✅ setNormalState: 调用 setNeedsDisplay()")
        setNeedsDisplay(bounds)
        debugLog("✅ setNormalState 完成")
    }

    override func mouseEntered(with event: NSEvent) {
        layer?.backgroundColor = .clear
    }

    override func mouseExited(with event: NSEvent) {
        layer?.backgroundColor = .clear
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        trackingAreas.forEach { removeTrackingArea($0) }

        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
    }
}

// MARK: - Menu Item View (一级菜单项视图)

/// 一级菜单项视图
///
/// 使用 Auto Layout 实现四列布局：
/// - 左列：工具名（左对齐）
/// - 次左列：版本号（工具名右侧，灰色，小字体）
/// - 右列：当前选中的源名称（中间右对齐）
/// - 最右侧：子菜单箭头图标
class MenuItemView: NSView {
    private var nameTextField: NSTextField!
    private var versionTextField: NSTextField!
    private var sourceTextField: NSTextField!
    var arrowTextField: NSTextField!  // 改为 internal，允许外部访问以隐藏箭头
    private let toolName: String
    private let version: String?
    private let sourceName: String

    init(frame frameRect: NSRect, toolName: String, version: String?, sourceName: String) {
        self.toolName = toolName
        self.version = version
        self.sourceName = sourceName
        super.init(frame: frameRect)
        setupView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupView() {
        wantsLayer = true
        layer?.backgroundColor = .clear

        // 左列：工具名
        nameTextField = NSTextField(labelWithString: toolName)
        nameTextField.font = NSFont.systemFont(ofSize: 14)
        nameTextField.textColor = .labelColor
        nameTextField.isEditable = false
        nameTextField.isSelectable = false
        nameTextField.isBordered = false
        nameTextField.backgroundColor = .clear
        nameTextField.translatesAutoresizingMaskIntoConstraints = false
        nameTextField.lineBreakMode = .byTruncatingTail
        addSubview(nameTextField)

        // 次左列：版本号（灰色，小字体）
        let versionText = version ?? ""
        versionTextField = NSTextField(labelWithString: versionText)
        versionTextField.font = NSFont.systemFont(ofSize: 11)
        versionTextField.textColor = .tertiaryLabelColor
        versionTextField.alignment = .left
        versionTextField.isEditable = false
        versionTextField.isSelectable = false
        versionTextField.isBordered = false
        versionTextField.backgroundColor = .clear
        versionTextField.drawsBackground = false
        versionTextField.translatesAutoresizingMaskIntoConstraints = false
        versionTextField.lineBreakMode = .byTruncatingTail
        addSubview(versionTextField)

        // 右列：当前源名称
        sourceTextField = NSTextField(labelWithString: sourceName)
        sourceTextField.font = NSFont.systemFont(ofSize: 13)
        sourceTextField.textColor = .secondaryLabelColor
        sourceTextField.alignment = .right
        sourceTextField.isEditable = false
        sourceTextField.isSelectable = false
        sourceTextField.isBordered = false
        sourceTextField.backgroundColor = .clear
        sourceTextField.translatesAutoresizingMaskIntoConstraints = false
        sourceTextField.lineBreakMode = .byTruncatingTail
        addSubview(sourceTextField)

        // 最右侧：子菜单箭头（使用系统原生样式）
        // macOS 原生菜单箭头使用系统字体渲染
        arrowTextField = NSTextField(labelWithString: "›")
        // 使用系统字体，确保箭头样式与原生一致
        arrowTextField.font = NSFont.menuFont(ofSize: 16)
        arrowTextField.textColor = .white
        arrowTextField.alignment = .right
        arrowTextField.isEditable = false
        arrowTextField.isSelectable = false
        arrowTextField.isBordered = false
        arrowTextField.backgroundColor = .clear
        arrowTextField.translatesAutoresizingMaskIntoConstraints = false
        addSubview(arrowTextField)

        // 使用 Auto Layout 约束
        NSLayoutConstraint.activate([
            // 左列：工具名（左对齐）
            nameTextField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: LayoutConstants.toolNameLeading),
            nameTextField.centerYAnchor.constraint(equalTo: centerYAnchor),

            // 次左列：版本号（在工具名右侧，使用 baseline 对齐）
            versionTextField.leadingAnchor.constraint(equalTo: nameTextField.trailingAnchor, constant: LayoutConstants.versionSpacing),
            versionTextField.lastBaselineAnchor.constraint(equalTo: nameTextField.lastBaselineAnchor),
            versionTextField.widthAnchor.constraint(lessThanOrEqualToConstant: LayoutConstants.versionMaxWidth),

            // 右列：当前源名称（在箭头左侧）
            sourceTextField.trailingAnchor.constraint(equalTo: arrowTextField.leadingAnchor, constant: LayoutConstants.sourceArrowSpacing),
            sourceTextField.centerYAnchor.constraint(equalTo: centerYAnchor),
            sourceTextField.widthAnchor.constraint(lessThanOrEqualToConstant: LayoutConstants.sourceMaxWidth),

            // 最右侧：箭头图标
            arrowTextField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: LayoutConstants.arrowTrailing),
            arrowTextField.centerYAnchor.constraint(equalTo: centerYAnchor),
            arrowTextField.widthAnchor.constraint(equalToConstant: LayoutConstants.arrowWidth),

            // 确保版本号在源名称左侧
            versionTextField.trailingAnchor.constraint(lessThanOrEqualTo: sourceTextField.leadingAnchor, constant: -LayoutConstants.sourceVersionSpacing)
        ])
    }

    /// 更新源名称
    func updateSourceName(_ newName: String) {
        sourceTextField.stringValue = newName
        setNeedsDisplay(bounds)
    }

    override func mouseEntered(with event: NSEvent) {
        layer?.backgroundColor = .clear
    }

    override func mouseExited(with event: NSEvent) {
        layer?.backgroundColor = .clear
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        trackingAreas.forEach { removeTrackingArea($0) }

        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
    }
}
