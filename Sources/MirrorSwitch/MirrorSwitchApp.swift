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

// MARK: - 后置动作触发时机

/// 后置动作触发时机
enum PostActionTrigger {
    case onSourceChanged  // 切换镜像源后
    case onReset          // 重置为默认配置后
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

            // 1. 初始化配置驱动管理器
            debugLog("⚙️ 初始化配置驱动管理器...")
            await ConfigurationDrivenSourceManager.shared.initialize()
            debugLog("✅ 配置驱动管理器初始化完成")

            // 2. 检测已安装的工具并获取版本
            debugLog("🔍 开始检测已安装的工具...")
            let toolVersions = await DynamicToolDetector.shared.detectAllTools()
            debugLog("✅ 检测完成，发现 \(toolVersions.count) 个工具")

            await MainActor.run {
                setupStatusBarMenu(with: toolVersions)
            }

            // 3. 为所有检测到的工具自动测速
            if !toolVersions.isEmpty {
                debugLog("⚡️ 开始自动测速...")
                for toolId in toolVersions.keys {
                    // 延迟一点避免同时发起太多请求
                    try? await Task.sleep(nanoseconds: UInt64(100_000_000)) // 0.1 秒
                    menuUpdateHelper?.startSpeedTest(for: toolId)
                }
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
    private func setupStatusBarMenu(with toolVersions: [String: String]) {
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
    private var testingTools: Set<String> = []  // 工具 ID 集合（用于动态工具）
    private var speedTestViews: [Int: SpeedTestView] = [:]  // 保存测速按钮 view 引用
    private var sourceItemViews: [Int: [MirrorSourceItemView]] = [:]  // 保存镜像源列表 view 引用
    private var menuItemViews: [String: MenuItemView] = [:]  // 保存一级菜单 view 引用（toolId -> view）
    private var toolVersions: [String: String] = [:]  // 工具版本信息（toolId -> version）
    private var toolCurrentSources: [String: MirrorSource] = [:]  // 工具当前选中的源（toolId -> source）
    private var configManagementWindow: ConfigManagementWindow?  // 配置管理窗口
    private var observer: NSObjectProtocol?  // 通知观察者
    private let debouncer = Debouncer(delay: 0.5)  // 防抖器

    init(statusItem: NSStatusItem?) {
        self.statusItem = statusItem
        super.init()
        setupNotificationObserver()
    }

    // MARK: - 通知处理

    /// 设置通知监听
    private func setupNotificationObserver() {
        observer = NotificationCenter.default.addObserver(
            forName: .configSourcesDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleConfigSourcesChange()
        }
    }

    /// 处理配置源变更
    private func handleConfigSourcesChange() {
        debouncer.debounce { [weak self] in
            self?.performConfigReload()
        }
    }

    /// 执行配置重新加载
    private func performConfigReload() {
        debugLog("📣 收到配置源变更通知，正在刷新工具列表...")

        Task {
            do {
                // 强制重新加载配置
                try await ConfigurationLoader.shared.reloadConfiguration()

                // 重新加载源管理器的配置（使用 reloadConfiguration 而不是 initialize）
                try await ConfigurationDrivenSourceManager.shared.reloadConfiguration()

                // 重新检测工具版本（添加新配置源时需要检测新工具）
                debugLog("🔍 重新检测工具版本...")
                let toolVersions = await DynamicToolDetector.shared.detectAllTools()
                debugLog("✅ 检测完成，发现 \(toolVersions.count) 个工具")

                // 在主线程更新菜单
                await MainActor.run {
                    self.setToolVersions(toolVersions)
                    self.refreshMenu()
                    debugLog("✅ 工具列表已刷新")
                }
            } catch {
                debugLog("⚠️ 配置重新加载失败: \(error)")
            }
        }
    }

    // MARK: - 版本管理

    /// 设置工具版本信息
    func setToolVersions(_ versions: [String: String]) {
        self.toolVersions = versions
        let detectedCount = versions.count
        debugLog("🔍 已检测到 \(detectedCount) 个工具")
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
        // 从配置驱动管理器获取所有工具配置
        let tools = ConfigurationDrivenSourceManager.shared.getAllTools()

        for toolConfig in tools {
            let toolId = toolConfig.id

            // 检查工具是否在一级菜单中可见
            guard ConfigSourceManager.shared.isToolVisibleInMenu(toolId: toolId) else {
                debugLog("⏭️  跳过工具 \(toolConfig.name)（已在配置中隐藏）")
                continue
            }

            // 获取当前选中的源
            let sources = ConfigurationDrivenSourceManager.shared.getSources(for: toolId)
            let currentSource = sources.first(where: { $0.isSelected })
            // 更新当前源（包括 nil 的情况）
            toolCurrentSources[toolId] = currentSource

            // 构建标题：工具名 + 版本号（如果有）
            let displayName = toolConfig.name
            let formattedVersion = toolVersions[toolId].flatMap { formatVersion($0) }

            // 创建自定义视图菜单项
            let menuItemView = MenuItemView(
                frame: NSRect(x: 0, y: 0, width: LayoutConstants.primaryMenuWidth, height: LayoutConstants.primaryMenuHeight),
                toolName: displayName,
                version: formattedVersion,
                sourceName: currentSource?.name ?? "未选择"
            )

            // 保存 MenuItemView 引用
            menuItemViews[toolId] = menuItemView

            let menuItem = NSMenuItem()
            menuItem.view = menuItemView
            menu.addItem(menuItem)

            // 创建子菜单
            let submenu = buildSubMenu(for: toolConfig)
            menuItem.submenu = submenu
        }

        // 添加分隔线
        menu.addItem(NSMenuItem.separator())

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
    /// 5. 手动选择目录（始终显示）
    /// 6. 打开配置文件目录
    /// 7. 重置按钮（ResetButtonView）
    ///
    /// - Parameter toolConfig: 工具配置
    /// - Returns: 构建好的子菜单
    private func buildSubMenu(for toolConfig: ToolConfiguration) -> NSMenu {
        let menu = NSMenu(title: toolConfig.name)
        let toolId = toolConfig.id

        // 测速按钮 - 作为镜像源列表的第一项
        let toolHash = toolId.hashValue
        debugLog("🏗️ 创建 SpeedTestView: tool=\(toolConfig.name), hash=\(toolHash)")

        let testSpeedView = SpeedTestView(
            frame: NSRect(x: 0, y: 0, width: LayoutConstants.viewWidth, height: LayoutConstants.speedTestViewHeight),
            toolName: toolConfig.name,
            toolHash: toolHash,
            isTesting: testingTools.contains(toolId)
        )

        // 保存 view 引用
        speedTestViews[toolHash] = testSpeedView
        debugLog("💾 已保存 view 引用，当前 keys: \(speedTestViews.keys)")

        testSpeedView.onAction = { [weak self] toolHash in
            self?.startSpeedTest(for: toolId)
        }

        let testSpeedItem = NSMenuItem()
        testSpeedItem.view = testSpeedView
        menu.addItem(testSpeedItem)

        menu.addItem(NSMenuItem.separator())

        // 镜像源列表 - 紧跟在测速按钮后面
        let sources = ConfigurationDrivenSourceManager.shared.getSources(for: toolId)
        var views: [MirrorSourceItemView] = []

        for source in sources {
            let sourceItemView = MirrorSourceItemView(
                frame: NSRect(x: 0, y: 0, width: LayoutConstants.viewWidth, height: LayoutConstants.sourceItemViewHeight),
                source: source,
                toolId: toolId,
                toolName: toolConfig.name
            )

            sourceItemView.onAction = { [weak self] (source, toolId) in
                self?.selectSource(source: source, toolId: toolId)
            }

            sourceItemView.onVisibilityToggle = { [weak self] sourceId in
                self?.toggleSourceVisibility(sourceId: sourceId, toolId: toolId)
            }

            views.append(sourceItemView)

            let sourceItem = NSMenuItem()
            sourceItem.view = sourceItemView
            menu.addItem(sourceItem)
        }

        // 保存 view 引用
        sourceItemViews[toolHash] = views
        debugLog("💾 已保存 \(views.count) 个镜像源 view，tool=\(toolConfig.name)")

        menu.addItem(NSMenuItem.separator())

        // 手动选择目录选项（始终显示）
        let customPath = ConfigManager.shared.getCustomPath(for: toolId)

        let customPathView = CustomPathView(
            frame: NSRect(x: 0, y: 0, width: LayoutConstants.viewWidth, height: LayoutConstants.speedTestViewHeight),
            toolId: toolId,
            currentPath: customPath
        )

        customPathView.onAction = { [weak self] path in
            self?.handleCustomPathSelection(path: path, toolId: toolId)
        }

        let customPathItem = NSMenuItem()
        customPathItem.view = customPathView
        menu.addItem(customPathItem)

        // 打开配置文件目录
        let openConfigDirView = OpenConfigDirView(
            frame: NSRect(x: 0, y: 0, width: LayoutConstants.viewWidth, height: LayoutConstants.speedTestViewHeight),
            toolId: toolId
        )
        openConfigDirView.onAction = { [weak self] toolId in
            self?.openConfigDirectory(for: toolId)
        }

        let openConfigDirItem = NSMenuItem()
        openConfigDirItem.view = openConfigDirView
        menu.addItem(openConfigDirItem)

        // 重置按钮
        let resetButtonView = ResetButtonView(frame: NSRect(x: 0, y: 0, width: LayoutConstants.viewWidth, height: LayoutConstants.speedTestViewHeight))
        resetButtonView.onAction = { [weak self] in
            self?.resetToDefault(for: toolId)
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
        let tools = ConfigurationDrivenSourceManager.shared.getAllTools()
        for toolConfig in tools {
            let toolId = toolConfig.id

            // 检查工具是否在一级菜单中可见
            guard ConfigSourceManager.shared.isToolVisibleInMenu(toolId: toolId) else {
                debugLog("⏭️  跳过工具 \(toolConfig.name)（已在配置中隐藏）")
                continue
            }

            // 获取当前选中的源
            let sources = ConfigurationDrivenSourceManager.shared.getSources(for: toolId)
            let currentSource = sources.first(where: { $0.isSelected })
            // 更新当前源（包括 nil 的情况）
            toolCurrentSources[toolId] = currentSource

            // 构建标题：工具名 + 版本号（如果有）
            let displayName = toolConfig.name
            let formattedVersion = toolVersions[toolId].flatMap { formatVersion($0) }

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

            // 保存 view 引用
            menuItemViews[toolId] = menuItemView

            // 创建子菜单
            let submenu = buildSubMenu(for: toolConfig)
            menuItem.submenu = submenu
        }

        // 添加分隔线（工具列表与配置选项之间）
        newMenu.addItem(NSMenuItem.separator())

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
    /// - Parameter toolId: 要测速的工具 ID
    func startSpeedTest(for toolId: String) {
        let toolHash = toolId.hashValue
        debugLog("⚡️ ===== 开始测速 \(toolId) (hash: \(toolHash)) =====")
        debugLog("⚡️ 当前 speedTestViews keys: \(speedTestViews.keys)")
        debugLog("⚡️ 检查 view 是否存在: \(speedTestViews[toolHash] != nil ? "✅ 存在" : "❌ 不存在")")

        testingTools.insert(toolId)

        // 直接更新 view 状态为"测速中..."
        debugLog("⚡️ 准备调用 updateSpeedTestView(isTesting: true)")
        updateSpeedTestView(for: toolId, isTesting: true)

        // 在后台执行测速
        Task {
            debugLog("⚡️ 后台测速任务开始")
            let sources = ConfigurationDrivenSourceManager.shared.getSources(for: toolId)
            await ConfigurationDrivenSourceManager.shared.testSpeed(sources: sources)
            debugLog("⚡️ 后台测速任务完成")

            await MainActor.run {
                debugLog("⚡️ 测速完成，准备移除 \(toolId)")
                self.testingTools.remove(toolId)
                debugLog("📝 移除后 testingTools 状态: \(self.testingTools)")

                // 直接更新 view 状态为"测速"
                debugLog("⚡️ 准备调用 updateSpeedTestView(isTesting: false)")
                self.updateSpeedTestView(for: toolId, isTesting: false)

                // 更新镜像源列表的延迟显示
                debugLog("⚡️ 准备调用 updateSourceList")
                self.updateSourceList(for: toolId)

                debugLog("✓ 菜单已刷新")
                debugLog("⚡️ ===== 测速流程结束 =====")
            }
        }
    }

    private func updateSpeedTestView(for toolId: String, isTesting: Bool) {
        let toolHash = toolId.hashValue
        debugLog("🔍 updateSpeedTestView 被调用: toolId=\(toolId), isTesting=\(isTesting)")
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
    /// - Parameter toolId: 要更新的工具 ID
    private func updateSourceList(for toolId: String) {
        let toolHash = toolId.hashValue
        guard let views = sourceItemViews[toolHash] else {
            debugLog("❌ 找不到 toolId=\(toolId) 的镜像源 view")
            return
        }

        debugLog("🔄 更新 \(toolId) 的镜像源列表，共 \(views.count) 个 view")

        // 获取最新的镜像源数据
        let sources = ConfigurationDrivenSourceManager.shared.getSources(for: toolId)

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
    /// - Parameter toolId: 要更新的工具 ID
    func updatePrimaryMenuItem(for toolId: String) {
        guard let menuItemView = menuItemViews[toolId] else {
            debugLog("❌ 找不到 toolId=\(toolId) 的一级菜单 view")
            return
        }

        // 从 toolCurrentSources 获取当前选中的源
        guard let currentSource = toolCurrentSources[toolId] else {
            // 没有选中的源，显示"未选择"
            menuItemView.updateSourceName("未选择")
            debugLog("✅ 一级菜单已更新: \(toolId) -> 未选择")
            return
        }

        // 更新显示的源名称
        menuItemView.updateSourceName(currentSource.name)
        debugLog("✅ 一级菜单已更新: \(toolId) -> \(currentSource.name)")
    }

    @objc private func selectSource(_ sender: NSMenuItem) {
        // 这个方法已经不再使用，保留是为了兼容旧的 NSMenuItem 调用
        debugLog("⚠️ selectSource(NSMenuItem) 被调用，这是旧方法")
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
    /// 6. 执行配置的后置动作（如显示对话框）
    ///
    /// - Parameters:
    ///   - source: 要切换到的镜像源
    ///   - toolId: 工具 ID
    func selectSource(source: MirrorSource, toolId: String) {
        debugLog("🔄 选择 \(toolId) 镜像源: \(source.name)")

        Task {
            do {
                try await ConfigurationDrivenSourceManager.shared.switchSource(toolId: toolId, source: source)
                await MainActor.run {
                    // 更新 toolCurrentSources 字典
                    self.toolCurrentSources[toolId] = source

                    // 直接更新镜像源列表的对勾状态
                    self.updateSourceList(for: toolId)

                    // 更新一级菜单的显示（不关闭菜单）
                    self.updatePrimaryMenuItem(for: toolId)

                    // 通用后置动作处理
                    self.handlePostActions(for: toolId, trigger: .onSourceChanged)
                }
            } catch {
                debugLog("❌ 切换失败: \(error.localizedDescription)")
            }
        }
    }

    /// 切换镜像源可见性
    /// - Parameters:
    ///   - sourceId: 镜像源 ID
    ///   - toolId: 工具 ID
    private func toggleSourceVisibility(sourceId: String, toolId: String) {
        guard let source = ConfigurationDrivenSourceManager.shared.getSources(for: toolId)
                .first(where: { $0.id == sourceId }) else {
            return
        }

        // 切换可见性
        let newVisibility = !source.isVisible
        ConfigurationDrivenSourceManager.shared.setSourceVisibility(
            sourceId: sourceId,
            isVisible: newVisibility
        )

        debugLog("👁️ 镜像源 \(source.name) 可见性: \(newVisibility ? "显示" : "隐藏")")

        // 刷新镜像源列表
        updateSourceList(for: toolId)
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

    /// 处理后置动作
    /// - Parameters:
    ///   - toolId: 工具 ID
    ///   - trigger: 触发时机
    private func handlePostActions(for toolId: String, trigger: PostActionTrigger) {
        guard let toolConfig = ConfigurationDrivenSourceManager.shared.getTool(by: toolId),
              let postActions = toolConfig.postActions else {
            return
        }

        let postAction: PostAction?
        switch trigger {
        case .onSourceChanged:
            postAction = postActions.onSourceChanged
        case .onReset:
            postAction = postActions.onReset
        }

        guard let action = postAction else {
            return
        }

        // 如果需要显示对话框（需要关闭菜单）
        if action.type == .showConfirmationDialog {
            closeMenu()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                PostActionExecutor.shared.execute(action) { _ in
                    // 执行完成后刷新菜单
                    self.refreshMenu()
                }
            }
        } else {
            PostActionExecutor.shared.execute(action) { _ in }
        }
    }

    /// 处理自定义路径选择
    ///
    /// 当用户手动选择工具目录后：
    /// 1. 保存路径到配置文件
    /// 2. 尝试重新检测工具版本
    /// 3. 如果检测成功，刷新菜单显示
    ///
    /// - Parameters:
    ///   - path: 用户选择的目录路径
    ///   - toolId: 工具 ID
    func handleCustomPathSelection(path: String, toolId: String) {
        guard let toolConfig = ConfigurationDrivenSourceManager.shared.getTool(by: toolId) else {
            debugLog("❌ 找不到工具配置: \(toolId)")
            return
        }

        debugLog("💾 保存 \(toolConfig.name) 自定义路径: \(path)")

        // 保存路径到配置文件
        ConfigManager.shared.saveCustomPath(toolId: toolId, path: path)

        // 在后台尝试重新检测版本
        Task {
            debugLog("🔍 使用自定义路径重新检测 \(toolConfig.name) 版本...")

            // 尝试从自定义路径检测工具
            let detected = await detectToolWithCustomPath(toolConfig: toolConfig, path: path)

            await MainActor.run {
                if let version = detected {
                    // 检测成功，更新版本信息
                    toolVersions[toolId] = version
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
    ///   - toolConfig: 工具配置
    ///   - path: 自定义路径
    /// - Returns: 版本字符串，检测失败返回 nil
    private func detectToolWithCustomPath(toolConfig: ToolConfiguration, path: String) async -> String? {
        // 构建可能的可执行文件路径
        let command = toolConfig.detection.command
        let executableNames = [
            command,
            "\(command).sh",
            "bin/\(command)",
            "bin/\(command).sh"
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
            let command = "\"\(fullPath)\" \(toolConfig.detection.arguments.joined(separator: " "))"
            let result = try? await ShellExecutor.execute(
                "/bin/sh",
                arguments: ["-lc", command]
            )

            if let output = result?.standardOutput, !output.isEmpty {
                let lines = output.components(separatedBy: CharacterSet.newlines)
                let versionLine = lines.first?.trimmingCharacters(in: CharacterSet.whitespaces)

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
    /// - Parameter toolId: 工具 ID
    func openConfigDirectory(for toolId: String) {
        guard let toolConfig = ConfigurationDrivenSourceManager.shared.getTool(by: toolId) else {
            debugLog("❌ 找不到工具配置: \(toolId)")
            return
        }

        debugLog("📂 打开 \(toolConfig.name) 配置文件目录")

        // 从工具配置获取配置文件目录
        guard let configDirString = toolConfig.strategy.configDirectory else {
            debugLog("❌ 该工具类型无法确定配置文件目录")
            showConfigDirNotFoundAlert(for: toolId, toolName: toolConfig.name)
            return
        }

        let configDir = URL(fileURLWithPath: (configDirString as NSString).expandingTildeInPath)

        // 检查目录是否存在
        if !FileManager.default.fileExists(atPath: configDir.path) {
            debugLog("❌ 配置文件目录不存在: \(configDir.path)")
            showConfigDirNotFoundAlert(for: toolId, toolName: toolConfig.name)
            return
        }

        // 在 Finder 中打开目录
        NSWorkspace.shared.open(configDir)
        debugLog("✅ 已在 Finder 中打开: \(configDir.path)")
    }

    /// 显示配置文件目录未找到的提示
    private func showConfigDirNotFoundAlert(for toolId: String, toolName: String) {
        let alert = NSAlert()
        alert.messageText = "无法找到配置文件目录"
        alert.informativeText = """
        无法找到 \(toolName) 的配置文件目录。

        请确保 \(toolName) 已正确安装。
        """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "确定")

        // 菜单栏应用直接使用 runModal，对话框会居中显示
        alert.runModal()
    }

    // 重置为默认配置
    func resetToDefault(for toolId: String) {
        debugLog("🔄 重置 \(toolId) 为默认配置")

        Task {
            do {
                try await ConfigurationDrivenSourceManager.shared.restoreConfig(for: toolId)

                // 恢复默认配置后，不重新检测当前源（保持"未选择"状态）
                // 直接从 ConfigurationDrivenSourceManager 获取最新状态（应该为 nil）
                let sourceId = ConfigurationDrivenSourceManager.shared.getCurrentSelection(toolId: toolId)
                let sources = ConfigurationDrivenSourceManager.shared.getSources(for: toolId)

                if let sourceId = sourceId,
                   let currentSource = sources.first(where: { $0.id == sourceId }) {
                    // 有匹配的镜像源
                    toolCurrentSources[toolId] = currentSource
                } else {
                    // 没有匹配的镜像源，清除缓存
                    toolCurrentSources.removeValue(forKey: toolId)
                }

                await MainActor.run {
                    // 直接更新镜像源列表的对勾状态
                    self.updateSourceList(for: toolId)

                    // 更新一级菜单的显示
                    self.updatePrimaryMenuItem(for: toolId)

                    debugLog("✅ \(toolId) 已重置为默认配置")
                }

                await MainActor.run {
                    // 通用后置动作处理
                    self.handlePostActions(for: toolId, trigger: .onReset)
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
            toolName: "配置...",
            version: nil,
            sourceName: ""
        )

        // 隐藏箭头（配置菜单项不需要箭头）
        if let arrowTextField = configItemView.arrowTextField {
            arrowTextField.isHidden = true
        }

        // 设置点击回调
        configItemView.onAction = { [weak self] in
            self?.openConfigWindow()
        }

        let menuItem = NSMenuItem()
        menuItem.view = configItemView

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
    private let toolId: String
    private let toolName: String
    private let detectionCommand: String
    private var textField: NSTextField!
    private var pathField: NSTextField?
    var onAction: ((String) -> Void)?

    init(frame frameRect: NSRect, toolId: String, currentPath: String?) {
        self.toolId = toolId
        // 从 ConfigurationDrivenSourceManager 获取工具配置
        if let toolConfig = ConfigurationDrivenSourceManager.shared.getTool(by: toolId) {
            self.toolName = toolConfig.name
            self.detectionCommand = toolConfig.detection.command
        } else {
            self.toolName = toolId
            self.detectionCommand = toolId
        }
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
        panel.title = "选择 \(toolName) 安装目录"
        panel.prompt = "选择"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser

        // 设置面板级别，确保在最前面
        panel.level = .floating

        // 激活应用，确保面板可见
        NSApp.activate(ignoringOtherApps: true)

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
            detectionCommand,
            "\(detectionCommand).sh",
            "bin/\(detectionCommand)",
            "bin/\(detectionCommand).sh"
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
        alert.messageText = "无效的 \(toolName) 安装目录"
        alert.informativeText = """
        在选定目录中未找到 \(toolName) 可执行文件。

        请确保 \(toolName) 已正确安装。
        """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "确定")

        // 菜单栏应用直接使用 runModal，对话框会居中显示
        alert.runModal()
    }

    /// 更新路径显示
    /// - Parameter path: 新路径
    private func updatePathDisplay(_ path: String) {
        // 移除旧的 pathField（如果存在）
        pathField?.removeFromSuperview()

        // 创建新的 pathField
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

            // 添加约束
            NSLayoutConstraint.activate([
                pathField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: LayoutConstants.thirdColumnTrailing),
                pathField.centerYAnchor.constraint(equalTo: centerYAnchor),
                pathField.widthAnchor.constraint(equalToConstant: LayoutConstants.thirdColumnWidth + 30)
            ])
        }
    }

    /// 简化路径显示
    /// - Parameter path: 完整路径
    /// - Returns: 简化后的路径
    private func abbreviatePath(_ path: String) -> String {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(homeDir) {
            return "~" + String(path.dropFirst(homeDir.count))
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
    private let toolId: String
    private var textField: NSTextField!
    var onAction: ((String) -> Void)?

    init(frame frameRect: NSRect, toolId: String) {
        self.toolId = toolId
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
        onAction?(toolId)

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
    private let toolId: String
    private let toolName: String
    private var checkField: NSTextField!   // 选中状态（对勾）
    private var nameField: NSTextField!   // 镜像源名称
    private var configSourceField: NSTextField!  // 配置源名称
    private var speedField: NSTextField!  // 测速速度
    var onAction: ((MirrorSource, String) -> Void)?
    var onVisibilityToggle: ((String) -> Void)?

    init(frame: NSRect, source: MirrorSource, toolId: String, toolName: String) {
        self.source = source
        self.toolId = toolId
        self.toolName = toolName
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

        // 第二列：镜像源名称 + 配置源标签
        let nameText: String
        if let configSourceName = source.configSourceName {
            nameText = "\(source.name) [\(configSourceName)]"
        } else {
            nameText = source.name
        }
        nameField = NSTextField(labelWithString: nameText)
        nameField.font = NSFont.systemFont(ofSize: 11)
        nameField.textColor = source.configSourceName != nil ? .secondaryLabelColor : .labelColor
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

            // 第二列：镜像源名称（扩展以容纳配置源标签）
            nameField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: LayoutConstants.secondColumnLeading),
            nameField.centerYAnchor.constraint(equalTo: centerYAnchor),
            nameField.widthAnchor.constraint(equalToConstant: LayoutConstants.secondColumnWidth + 40),  // 增加宽度以显示配置源标签

            // 第三列：测速速度（右对齐到视图边缘）
            speedField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: LayoutConstants.thirdColumnTrailing),
            speedField.centerYAnchor.constraint(equalTo: centerYAnchor),
            speedField.widthAnchor.constraint(equalToConstant: LayoutConstants.thirdColumnWidth)
        ])
    }

    // 关键：重写 mouseDown，但不调用 super
    override func mouseDown(with event: NSEvent) {
        debugLog("🖱️ MirrorSourceItemView mouseDown 被调用: \(source.name)")

        // 检查是否是右键点击
        if event.buttonNumber == 1 {  // 右键
            showContextMenu(at: event.locationInWindow)
            return
        }

        // 执行选择逻辑
        onAction?(source, toolId)

        // 关键：不调用 super.mouseDown(with: event)
        // 这样系统就不会认为菜单项被"选中"了，菜单也就不会关闭
    }

    /// 显示右键菜单
    private func showContextMenu(at location: NSPoint) {
        let menu = NSMenu()

        // 隐藏/显示镜像源选项
        let visibilityTitle = source.isVisible ? "隐藏此源" : "显示此源"
        let visibilityItem = NSMenuItem(title: visibilityTitle, action: #selector(toggleVisibility), keyEquivalent: "")
        visibilityItem.target = self
        menu.addItem(visibilityItem)

        // 分隔线
        menu.addItem(NSMenuItem.separator())

        // 显示配置源信息
        if let configSourceName = source.configSourceName {
            let infoItem = NSMenuItem(title: "配置源: \(configSourceName)", action: nil, keyEquivalent: "")
            infoItem.isEnabled = false
            menu.addItem(infoItem)
        }

        // 显示菜单
        menu.popUp(positioning: nil, at: location, in: self)
    }

    @objc private func toggleVisibility() {
        onVisibilityToggle?(source.id)
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

    /// 点击回调（用于配置菜单项等不需要子菜单的项）
    var onAction: (() -> Void)?

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

    override func mouseDown(with event: NSEvent) {
        // 如果有点击回调，执行回调
        if let action = onAction {
            action()
        }
    }
}
