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
    /// 视图总宽度
    static let viewWidth: CGFloat = 190.0

    /// 第一列（对勾）：左边距和宽度
    static let firstColumnLeading: CGFloat = 10.0
    static let firstColumnWidth: CGFloat = 20.0

    /// 第二列（文本）：左边距和宽度
    static let secondColumnLeading: CGFloat = 32.0
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

        // 初始化 SourceManager 和创建菜单
        Task {
            await SourceManager.shared.initialize()
            await MainActor.run {
                setupStatusBarMenu()
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
    private func setupStatusBarMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            if let image = NSImage(systemSymbolName: "arrow.triangle.2.circlepath",
                                   accessibilityDescription: "Mirror Switch") {
                button.image = image
            } else {
                button.title = "⚡️"
            }
        }

        // 创建菜单更新助手
        menuUpdateHelper = MenuUpdateHelper(statusItem: statusItem)
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
@MainActor
class MenuUpdateHelper: NSObject {
    private weak var statusItem: NSStatusItem?
    private var testingTools: Set<ToolType> = []
    private var speedTestViews: [Int: SpeedTestView] = [:]  // 保存测速按钮 view 引用
    private var sourceItemViews: [Int: [MirrorSourceItemView]] = [:]  // 保存镜像源列表 view 引用

    init(statusItem: NSStatusItem?) {
        self.statusItem = statusItem
        super.init()
    }

    func buildMenu() {
        guard let statusItem = statusItem else { return }

        let menu = NSMenu()
        menu.delegate = self

        // 为每个工具创建子菜单
        for tool in ToolType.allCases {
            let menuItem = NSMenuItem(title: tool.displayName, action: nil, keyEquivalent: "")
            let submenu = buildSubMenu(for: tool)
            menuItem.submenu = submenu
            menu.addItem(menuItem)
        }

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
    /// 5. 重置按钮（ResetButtonView）
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
        let sources = SourceManager.shared.getSources(for: tool)
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

        for tool in ToolType.allCases {
            let menuItem = NSMenuItem(title: tool.displayName, action: nil, keyEquivalent: "")
            let submenu = buildSubMenu(for: tool)
            menuItem.submenu = submenu
            newMenu.addItem(menuItem)
        }

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
            let sources = SourceManager.shared.getSources(for: tool)
            await SourceManager.shared.testSpeed(sources: sources)
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
        let sources = SourceManager.shared.getSources(for: tool)

        // 更新每个 view 的数据
        for (index, view) in views.enumerated() {
            if index < sources.count {
                let source = sources[index]
                view.updateSource(source)
            }
        }

        debugLog("✅ 镜像源列表更新完成")
    }

    @objc private func selectSource(_ sender: NSMenuItem) {
        guard let source = sender.representedObject as? MirrorSource,
              let tool = ToolType.allCases.first(where: { $0.hashValue == sender.tag }) else {
            return
        }

        print("🔄 选择 \(tool.displayName) 镜像源: \(source.name)")

        Task {
            do {
                try await SourceManager.shared.switchSource(tool: tool, source: source)
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
    ///
    /// - Parameters:
    ///   - source: 要切换到的镜像源
    ///   - tool: 工具类型
    func selectSource(source: MirrorSource, tool: ToolType) {
        debugLog("🔄 选择 \(tool.displayName) 镜像源: \(source.name)")

        Task {
            do {
                try await SourceManager.shared.switchSource(tool: tool, source: source)
                await MainActor.run {
                    // 直接更新镜像源列表的对勾状态，不重建菜单
                    self.updateSourceList(for: tool)
                }
            } catch {
                debugLog("❌ 切换失败: \(error.localizedDescription)")
            }
        }
    }

    // 重置为默认配置
    func resetToDefault(for tool: ToolType) {
        debugLog("🔄 重置 \(tool.displayName) 为默认配置")

        // 获取该工具的所有镜像源
        let sources = SourceManager.shared.getSources(for: tool)

        // 查找官方源（通常是第一个源或 id 包含 "official" 的源）
        guard let defaultSource = sources.first(where: { $0.id.contains("official") || $0.name.contains("官方") }) ?? sources.first else {
            debugLog("❌ 找不到 \(tool.displayName) 的默认源")
            return
        }

        debugLog("🔄 找到默认源: \(defaultSource.name)")

        Task {
            do {
                try await SourceManager.shared.switchSource(tool: tool, source: defaultSource)
                await MainActor.run {
                    // 直接更新镜像源列表的对勾状态，不重建菜单
                    self.updateSourceList(for: tool)
                    debugLog("✅ \(tool.displayName) 已重置为默认配置")
                }
            } catch {
                debugLog("❌ 重置失败: \(error.localizedDescription)")
            }
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
