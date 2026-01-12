//
//  ConfigManagementWindow.swift
//  MirrorSwitch
//
//  配置管理窗口
//  提供配置源的添加、删除、启用/禁用等功能
//

import AppKit
import Foundation
import UniformTypeIdentifiers

/// 配置管理窗口
@MainActor
class ConfigManagementWindow: NSWindowController {
    // MARK: - 属性

    /// 配置源列表
    private var configSources: [ConfigSource] = []

    /// 表格视图
    private var tableView: NSTableView!

    /// 添加按钮
    private var addButton: NSButton!

    /// 删除按钮
    private var removeButton: NSButton!

    /// 刷新按钮
    private var refreshButton: NSButton!

    /// 类型选择（本地/远程）
    private var typeSegmentedControl: NSSegmentedControl!

    /// URL 输入框
    private var urlTextField: NSTextField!

    /// 名称输入框
    private var nameTextField: NSTextField!

    /// 浏览按钮
    private var browseButton: NSButton!

    /// 工具可见性容器视图
    private var toolVisibilityContainer: NSView!

    /// 工具可见性表格视图
    private var toolVisibilityTableView: NSTableView!

    /// 工具列表（从配置源加载）
    private var toolsList: [ToolConfiguration] = []

    /// 当前选中的配置源
    private var selectedConfigSource: ConfigSource?

    /// 当前选中的配置源 ID
    private var selectedConfigSourceId: UUID?

    // MARK: - 初始化

    init() {
        super.init(window: nil)
        setupWindow()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupWindow()
    }

    // MARK: - 窗口设置

    private func setupWindow() {
        let contentRect = NSRect(x: 0, y: 0, width: 600, height: 700)

        let configWindow = NSWindow(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )

        configWindow.title = "镜像源配置管理"
        configWindow.center()
        configWindow.isReleasedWhenClosed = false

        // 使用 NSWindowController 的 window 属性
        self.window = configWindow
        setupUI()
        loadData()
    }

    private func setupUI() {
        let contentView = NSView(frame: self.window!.contentView!.bounds)
        self.window!.contentView = contentView

        // 标题
        let titleLabel = NSTextField(labelWithString: "配置源列表")
        titleLabel.font = NSFont.systemFont(ofSize: 16, weight: .bold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(titleLabel)

        // 滚动视图和表格
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .bezelBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(scrollView)

        // 表格视图
        tableView = NSTableView()
        tableView.delegate = self
        tableView.dataSource = self
        tableView.usesAlternatingRowBackgroundColors = true
        scrollView.documentView = tableView

        // 列：启用状态
        let enabledColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("enabled"))
        enabledColumn.headerCell.stringValue = "启用"
        enabledColumn.width = 50
        tableView.addTableColumn(enabledColumn)

        // 列：类型
        let typeColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("type"))
        typeColumn.headerCell.stringValue = "类型"
        typeColumn.width = 60
        tableView.addTableColumn(typeColumn)

        // 列：名称
        let nameColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        nameColumn.headerCell.stringValue = "名称"
        nameColumn.width = 150
        tableView.addTableColumn(nameColumn)

        // 列：URL
        let urlColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("url"))
        urlColumn.headerCell.stringValue = "URL/路径"
        urlColumn.width = 200
        tableView.addTableColumn(urlColumn)

        // 列：状态
        let statusColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("status"))
        statusColumn.headerCell.stringValue = "状态"
        statusColumn.width = 80
        tableView.addTableColumn(statusColumn)

        // 按钮容器
        let buttonContainer = NSView()
        buttonContainer.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(buttonContainer)

        // 添加按钮
        addButton = NSButton(title: "+ 添加", target: self, action: #selector(addButtonClicked))
        addButton.bezelStyle = .rounded
        addButton.translatesAutoresizingMaskIntoConstraints = false
        buttonContainer.addSubview(addButton)

        // 删除按钮
        removeButton = NSButton(title: "- 删除", target: self, action: #selector(removeButtonClicked))
        removeButton.bezelStyle = .rounded
        removeButton.translatesAutoresizingMaskIntoConstraints = false
        buttonContainer.addSubview(removeButton)

        // 刷新按钮
        refreshButton = NSButton(
            title: "↻ 刷新", target: self, action: #selector(refreshButtonClicked))
        refreshButton.bezelStyle = .rounded
        refreshButton.translatesAutoresizingMaskIntoConstraints = false
        buttonContainer.addSubview(refreshButton)

        // 分隔线
        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(separator)

        // 添加配置源区域
        let addConfigLabel = NSTextField(labelWithString: "添加配置源:")
        addConfigLabel.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        addConfigLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(addConfigLabel)

        // 类型选择
        typeSegmentedControl = NSSegmentedControl(
            labels: ["本地文件", "远程 URL"], trackingMode: .selectOne, target: self,
            action: #selector(typeChanged))
        typeSegmentedControl.selectedSegment = 0
        typeSegmentedControl.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(typeSegmentedControl)

        // 名称输入
        let nameLabel = NSTextField(labelWithString: "名称:")
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(nameLabel)

        nameTextField = NSTextField()
        nameTextField.placeholderString = "例如: 我的 Maven 配置"
        nameTextField.isEditable = true  // 明确设置为可编辑
        nameTextField.isSelectable = true  // 允许选择文本
        nameTextField.allowsEditingTextAttributes = false  // 禁用富文本编辑
        nameTextField.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(nameTextField)

        // URL/路径输入
        let urlLabel = NSTextField(
            labelWithString: typeSegmentedControl.selectedSegment == 0 ? "路径:" : "URL:")
        urlLabel.translatesAutoresizingMaskIntoConstraints = false
        urlLabel.identifier = NSUserInterfaceItemIdentifier("urlLabel")
        contentView.addSubview(urlLabel)

        urlTextField = NSTextField()
        urlTextField.placeholderString =
            typeSegmentedControl.selectedSegment == 0
            ? "~/Documents/config.json" : "https://example.com/config.json"
        urlTextField.isEditable = true  // 明确设置为可编辑
        urlTextField.isSelectable = true  // 允许选择文本
        urlTextField.allowsEditingTextAttributes = false
        urlTextField.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(urlTextField)

        // 浏览按钮
        browseButton = NSButton(
            title: "浏览...", target: self, action: #selector(browseButtonClicked))
        browseButton.bezelStyle = .rounded
        browseButton.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(browseButton)

        // 添加配置按钮（表单中的添加按钮）
        let addConfigButton = NSButton(
            title: "+ 添加配置", target: self, action: #selector(saveButtonClicked))
        addConfigButton.bezelStyle = .rounded
        addConfigButton.keyEquivalent = "\r"  // 支持 Enter 键
        addConfigButton.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(addConfigButton)

        // 工具可见性分隔线
        let toolVisibilitySeparator = NSBox()
        toolVisibilitySeparator.boxType = .separator
        toolVisibilitySeparator.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(toolVisibilitySeparator)

        // 工具可见性标题
        let toolVisibilityLabel = NSTextField(labelWithString: "工具可见性配置")
        toolVisibilityLabel.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        toolVisibilityLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(toolVisibilityLabel)

        // 工具可见性说明
        let toolVisibilityHint = NSTextField(labelWithString: "选中一个配置源，然后勾选要在一级菜单中显示的工具")
        toolVisibilityHint.textColor = .secondaryLabelColor
        toolVisibilityHint.font = NSFont.systemFont(ofSize: 11)
        toolVisibilityHint.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(toolVisibilityHint)

        // 工具可见性滚动视图
        let toolVisibilityScrollView = NSScrollView()
        toolVisibilityScrollView.hasVerticalScroller = true
        toolVisibilityScrollView.hasHorizontalScroller = false
        toolVisibilityScrollView.autohidesScrollers = true
        toolVisibilityScrollView.borderType = .bezelBorder
        toolVisibilityScrollView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(toolVisibilityScrollView)

        // 工具可见性表格视图
        toolVisibilityTableView = NSTableView()
        toolVisibilityTableView.delegate = self
        toolVisibilityTableView.dataSource = self
        toolVisibilityTableView.usesAlternatingRowBackgroundColors = true
        toolVisibilityScrollView.documentView = toolVisibilityTableView

        // 列：可见性复选框
        let toolVisibleColumn = NSTableColumn(
            identifier: NSUserInterfaceItemIdentifier("toolVisible"))
        toolVisibleColumn.headerCell.stringValue = "显示"
        toolVisibleColumn.width = 50
        toolVisibilityTableView.addTableColumn(toolVisibleColumn)

        // 列：工具名称
        let toolNameColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("toolName"))
        toolNameColumn.headerCell.stringValue = "工具名称"
        toolNameColumn.width = 200
        toolVisibilityTableView.addTableColumn(toolNameColumn)

        // 布局约束
        NSLayoutConstraint.activate([
            // 标题
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),

            // 表格
            scrollView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 10),
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            scrollView.trailingAnchor.constraint(
                equalTo: contentView.trailingAnchor, constant: -20),
            scrollView.heightAnchor.constraint(equalToConstant: 200),

            // 按钮容器
            buttonContainer.topAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: 10),
            buttonContainer.leadingAnchor.constraint(
                equalTo: contentView.leadingAnchor, constant: 20),
            buttonContainer.trailingAnchor.constraint(
                equalTo: contentView.trailingAnchor, constant: -20),
            buttonContainer.heightAnchor.constraint(equalToConstant: 30),

            // 按钮
            addButton.leadingAnchor.constraint(equalTo: buttonContainer.leadingAnchor),
            addButton.centerYAnchor.constraint(equalTo: buttonContainer.centerYAnchor),

            removeButton.leadingAnchor.constraint(equalTo: addButton.trailingAnchor, constant: 10),
            removeButton.centerYAnchor.constraint(equalTo: buttonContainer.centerYAnchor),

            refreshButton.leadingAnchor.constraint(
                equalTo: removeButton.trailingAnchor, constant: 10),
            refreshButton.centerYAnchor.constraint(equalTo: buttonContainer.centerYAnchor),

            // 分隔线
            separator.topAnchor.constraint(equalTo: buttonContainer.bottomAnchor, constant: 15),
            separator.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            separator.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),

            // 添加配置源标签
            addConfigLabel.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: 15),
            addConfigLabel.leadingAnchor.constraint(
                equalTo: contentView.leadingAnchor, constant: 20),

            // 类型选择
            typeSegmentedControl.topAnchor.constraint(
                equalTo: addConfigLabel.bottomAnchor, constant: 10),
            typeSegmentedControl.leadingAnchor.constraint(
                equalTo: contentView.leadingAnchor, constant: 20),
            typeSegmentedControl.widthAnchor.constraint(equalToConstant: 200),

            // 名称标签 - 使用 centerYAnchor 与输入框对齐
            nameLabel.centerYAnchor.constraint(equalTo: nameTextField.centerYAnchor),
            nameLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            nameLabel.widthAnchor.constraint(equalToConstant: 50),

            // 名称输入框
            nameTextField.topAnchor.constraint(
                equalTo: typeSegmentedControl.bottomAnchor, constant: 15),
            nameTextField.leadingAnchor.constraint(equalTo: nameLabel.trailingAnchor, constant: 10),
            nameTextField.trailingAnchor.constraint(
                equalTo: contentView.trailingAnchor, constant: -20),
            nameTextField.heightAnchor.constraint(equalToConstant: 24),

            // URL 标签 - 使用 centerYAnchor 与输入框对齐
            urlLabel.centerYAnchor.constraint(equalTo: urlTextField.centerYAnchor),
            urlLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            urlLabel.widthAnchor.constraint(equalToConstant: 50),

            // URL 输入框
            urlTextField.topAnchor.constraint(equalTo: nameTextField.bottomAnchor, constant: 10),
            urlTextField.leadingAnchor.constraint(equalTo: urlLabel.trailingAnchor, constant: 10),
            urlTextField.trailingAnchor.constraint(
                equalTo: browseButton.leadingAnchor, constant: -10),
            urlTextField.heightAnchor.constraint(equalToConstant: 24),

            // 浏览按钮
            browseButton.centerYAnchor.constraint(equalTo: urlTextField.centerYAnchor),
            browseButton.trailingAnchor.constraint(
                equalTo: addConfigButton.leadingAnchor, constant: -10),
            browseButton.widthAnchor.constraint(equalToConstant: 80),

            // 添加配置按钮（与浏览按钮在同一行）
            addConfigButton.centerYAnchor.constraint(equalTo: urlTextField.centerYAnchor),
            addConfigButton.trailingAnchor.constraint(
                equalTo: contentView.trailingAnchor, constant: -20),
            addConfigButton.widthAnchor.constraint(equalToConstant: 100),

            // 工具可见性分隔线
            toolVisibilitySeparator.topAnchor.constraint(
                equalTo: addConfigButton.bottomAnchor, constant: 20),
            toolVisibilitySeparator.leadingAnchor.constraint(
                equalTo: contentView.leadingAnchor, constant: 20),
            toolVisibilitySeparator.trailingAnchor.constraint(
                equalTo: contentView.trailingAnchor, constant: -20),

            // 工具可见性标题
            toolVisibilityLabel.topAnchor.constraint(
                equalTo: toolVisibilitySeparator.bottomAnchor, constant: 15),
            toolVisibilityLabel.leadingAnchor.constraint(
                equalTo: contentView.leadingAnchor, constant: 20),

            // 工具可见性说明
            toolVisibilityHint.topAnchor.constraint(
                equalTo: toolVisibilityLabel.bottomAnchor, constant: 5),
            toolVisibilityHint.leadingAnchor.constraint(
                equalTo: contentView.leadingAnchor, constant: 20),
            toolVisibilityHint.trailingAnchor.constraint(
                equalTo: contentView.trailingAnchor, constant: -20),

            // 工具可见性滚动视图
            toolVisibilityScrollView.topAnchor.constraint(
                equalTo: toolVisibilityHint.bottomAnchor, constant: 10),
            toolVisibilityScrollView.leadingAnchor.constraint(
                equalTo: contentView.leadingAnchor, constant: 20),
            toolVisibilityScrollView.trailingAnchor.constraint(
                equalTo: contentView.trailingAnchor, constant: -20),
            toolVisibilityScrollView.bottomAnchor.constraint(
                equalTo: contentView.bottomAnchor, constant: -20),
            toolVisibilityScrollView.heightAnchor.constraint(equalToConstant: 150),
        ])
    }

    // MARK: - 数据加载

    private func loadData() {
        configSources = ConfigSourceManager.shared.getAllSources()
        tableView.reloadData()

        // 加载工具列表
        loadToolsList()
    }

    /// 加载工具列表（从选中的配置源）
    private func loadToolsList() {
        Task {
            // 如果有选中的配置源，只加载该配置源的工具
            if let configSourceId = selectedConfigSourceId {
                let fetchedTools =
                    await ConfigurationDrivenSourceManager.shared.getTools(
                        forConfigSource: configSourceId) ?? []
                self.toolsList = fetchedTools
            } else {
                // 如果没有选中配置源，显示空列表
                self.toolsList = []
            }

            // 刷新表格
            self.toolVisibilityTableView.reloadData()
        }
    }

    /// 选中配置源时更新工具可见性表格
    private func updateToolVisibilityTable() {
        // 重新加载工具列表（确保显示最新的工具）
        loadToolsList()

        // 更新说明文本
        if let source = selectedConfigSource {
            // 查找说明文本字段
            if let hintView = self.window?.contentView?.subviews.first(where: {
                ($0 as? NSTextField)?.stringValue.contains("选中一个配置源") ?? false
            }) as? NSTextField {
                hintView.stringValue = "配置源「\(source.name)」包含以下工具，勾选要在一级菜单中显示的工具"
            }
        }
    }

    // MARK: - 按钮操作

    @objc private func addButtonClicked() {
        // 清空输入框并聚焦到名称输入框
        nameTextField.stringValue = ""
        urlTextField.stringValue = ""
        nameTextField.becomeFirstResponder()
    }

    @objc private func removeButtonClicked() {
        let selectedRow = tableView.selectedRow
        guard selectedRow >= 0, selectedRow < configSources.count else {
            showAlert(message: "请先选择要删除的配置源")
            return
        }

        let source = configSources[selectedRow]

        // 确认删除
        let alert = NSAlert()
        alert.messageText = "确认删除"
        alert.informativeText = "确定要删除配置源「\(source.name)」吗？"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "删除")
        alert.addButton(withTitle: "取消")

        if alert.runModal() == .alertFirstButtonReturn {
            ConfigSourceManager.shared.removeConfigSource(id: source.id)
            loadData()
        }
    }

    @objc private func refreshButtonClicked() {
        loadData()
        showAlert(message: "已刷新配置源列表", style: .informational)
    }

    @objc private func typeChanged() {
        let isLocal = typeSegmentedControl.selectedSegment == 0

        // 更新 URL 标签和占位符
        if let urlLabel = self.window!.contentView?.subviews.first(where: {
            ($0 as? NSTextField)?.identifier?.rawValue == "urlLabel"
        }) as? NSTextField {
            urlLabel.stringValue = isLocal ? "路径:" : "URL:"
        }

        urlTextField.placeholderString =
            isLocal
            ? "~/Documents/maven_mirror.json"
            : "https://example.com/maven_mirror.json"
    }

    @objc private func browseButtonClicked() {
        let panel = NSOpenPanel()
        panel.title = "选择配置文件"
        panel.prompt = "选择"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = false

        panel.beginSheetModal(for: self.window!) { response in
            if response == .OK, let url = panel.url {
                // 如果是用户目录下的文件，使用 ~ 简化显示
                let homeDir = FileManager.default.homeDirectoryForCurrentUser
                let path = url.path

                if path.hasPrefix(homeDir.path) {
                    let relativePath = "~" + String(path.dropFirst(homeDir.path.count))
                    self.urlTextField.stringValue = relativePath
                } else {
                    self.urlTextField.stringValue = path
                }
            }
        }
    }

    @objc private func saveButtonClicked() {
        let name = nameTextField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let url = urlTextField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let isLocal = typeSegmentedControl.selectedSegment == 0

        // 验证输入
        guard !name.isEmpty else {
            showAlert(message: "请输入配置源名称")
            return
        }

        guard !url.isEmpty else {
            showAlert(message: isLocal ? "请输入文件路径" : "请输入远程 URL")
            return
        }

        // 验证 URL 格式
        if isLocal {
            // 本地文件路径
            let expandedPath = NSString(string: url).expandingTildeInPath
            guard FileManager.default.fileExists(atPath: expandedPath) else {
                showAlert(message: "文件不存在: \(expandedPath)")
                return
            }

            // Schema 验证
            let fileURL = URL(fileURLWithPath: expandedPath)
            let validationResult = SchemaValidator.shared.validate(fileURL: fileURL)

            guard validationResult.isValid else {
                showAlert(message: "配置文件格式不正确:\n\(validationResult.errorMessage ?? "未知错误")")
                return
            }

            print("✅ 配置文件 Schema 验证通过")

        } else {
            // 远程 URL
            guard URL(string: url) != nil else {
                showAlert(message: "无效的 URL 格式")
                return
            }

            // 远程配置在加载时验证（ConfigurationLoader 中已有 validateConfiguration 方法）
        }

        // 创建配置源
        let newSource = ConfigSource(
            name: name,
            type: isLocal ? .local : .remote,
            url: url,
            isEnabled: true
        )

        // 添加配置源
        ConfigSourceManager.shared.addConfigSource(newSource)

        // 刷新列表
        loadData()

        // 清空输入框
        nameTextField.stringValue = ""
        urlTextField.stringValue = ""

        showAlert(message: "配置源已添加，工具列表将自动刷新", style: .informational)
    }

    // MARK: - 辅助方法

    private func showAlert(message: String, style: NSAlert.Style = .warning) {
        let alert = NSAlert()
        alert.messageText = message
        alert.alertStyle = style
        alert.addButton(withTitle: "确定")
        alert.runModal()
    }

    // MARK: - 公共方法

    /// 显示窗口
    func show() {
        loadData()
        self.window!.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - NSTableViewDataSource

extension ConfigManagementWindow: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        if tableView == toolVisibilityTableView {
            if selectedConfigSourceId == nil {
                // 没有选中配置源时，显示提示行
                return 1
            }
            return toolsList.count
        }
        return configSources.count
    }
}

// MARK: - NSTableViewDelegate

extension ConfigManagementWindow: NSTableViewDelegate {
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int)
        -> NSView?
    {
        // 处理工具可见性表格
        if tableView == toolVisibilityTableView {
            // 如果没有选中配置源，显示提示信息
            if selectedConfigSourceId == nil {
                // 只在"工具名称"列显示提示
                if tableColumn?.identifier.rawValue == "toolName" {
                    guard
                        let cellView = tableView.makeView(
                            withIdentifier: NSUserInterfaceItemIdentifier("toolEmptyHint"),
                            owner: self
                        ) as? NSTableCellView
                    else {
                        // 创建提示单元格
                        let cellView = NSTableCellView()
                        cellView.identifier = NSUserInterfaceItemIdentifier("toolEmptyHint")

                        let textField = NSTextField(labelWithString: "请先在上方选择一个配置源")
                        textField.textColor = .secondaryLabelColor
                        textField.font = NSFont.systemFont(ofSize: 13)
                        textField.translatesAutoresizingMaskIntoConstraints = false
                        cellView.addSubview(textField)

                        NSLayoutConstraint.activate([
                            textField.centerYAnchor.constraint(equalTo: cellView.centerYAnchor),
                            textField.leadingAnchor.constraint(
                                equalTo: cellView.leadingAnchor, constant: 10),
                        ])

                        return cellView
                    }
                    return cellView
                }
                // 其他列显示空白
                return nil
            }

            guard row < toolsList.count else { return nil }

            let tool = toolsList[row]
            let columnId = tableColumn?.identifier.rawValue ?? ""

            switch columnId {
            case "toolVisible":
                let checkbox = NSButton(
                    checkboxWithTitle: "", target: self,
                    action: #selector(toolVisibilityCheckboxClicked(_:)))
                // 获取当前配置源中此工具的可见性
                let isVisible = ConfigSourceManager.shared.isToolVisibleInMenu(
                    toolId: tool.id,
                    originalId: tool.originalId,
                    configSourceId: selectedConfigSource!.id
                )
                checkbox.state = isVisible ? .on : .off
                checkbox.identifier = NSUserInterfaceItemIdentifier(tool.id)
                return checkbox

            case "toolName":
                let cellView = NSTableCellView()
                let textField = NSTextField(labelWithString: "\(tool.name) (\(tool.id))")
                cellView.addSubview(textField)
                textField.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([
                    textField.centerYAnchor.constraint(equalTo: cellView.centerYAnchor),
                    textField.leadingAnchor.constraint(
                        equalTo: cellView.leadingAnchor, constant: 5),
                ])
                return cellView

            default:
                return nil
            }
        }

        // 处理配置源表格（原有逻辑）
        guard row < configSources.count else { return nil }

        let source = configSources[row]
        let columnId = tableColumn?.identifier.rawValue ?? ""

        switch columnId {
        case "enabled":
            let checkbox = NSButton(
                checkboxWithTitle: "", target: self, action: #selector(enabledCheckboxClicked(_:)))
            checkbox.state = source.isEnabled ? .on : .off
            checkbox.identifier = NSUserInterfaceItemIdentifier(source.id.uuidString)
            // 内置配置可以启用/禁用
            return checkbox

        case "type":
            let cellView = NSTableCellView()
            let textField = NSTextField(
                labelWithString: "\(source.type.icon) \(source.type.displayName)")
            cellView.addSubview(textField)
            textField.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                textField.centerYAnchor.constraint(equalTo: cellView.centerYAnchor),
                textField.leadingAnchor.constraint(equalTo: cellView.leadingAnchor, constant: 5),
            ])
            return cellView

        case "name":
            let cellView = NSTableCellView()
            let textField = NSTextField(labelWithString: source.name)
            cellView.addSubview(textField)
            textField.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                textField.centerYAnchor.constraint(equalTo: cellView.centerYAnchor),
                textField.leadingAnchor.constraint(equalTo: cellView.leadingAnchor, constant: 5),
            ])
            return cellView

        case "url":
            let cellView = NSTableCellView()
            let textField = NSTextField(
                labelWithString: source.url ?? (source.type == .builtin ? "-" : ""))
            textField.textColor = .secondaryLabelColor
            textField.font = NSFont.systemFont(ofSize: 12)
            cellView.addSubview(textField)
            textField.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                textField.centerYAnchor.constraint(equalTo: cellView.centerYAnchor),
                textField.leadingAnchor.constraint(equalTo: cellView.leadingAnchor, constant: 5),
                textField.trailingAnchor.constraint(equalTo: cellView.trailingAnchor, constant: -5),
            ])
            return cellView

        case "status":
            let cellView = NSTableCellView()
            let textField = NSTextField(
                labelWithString: "\(source.status.icon) \(source.status.displayName)")
            cellView.addSubview(textField)
            textField.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                textField.centerYAnchor.constraint(equalTo: cellView.centerYAnchor),
                textField.leadingAnchor.constraint(equalTo: cellView.leadingAnchor, constant: 5),
            ])
            return cellView

        default:
            return nil
        }
    }

    @objc private func enabledCheckboxClicked(_ sender: NSButton) {
        guard let uuidString = sender.identifier?.rawValue,
            let uuid = UUID(uuidString: uuidString)
        else {
            return
        }

        ConfigSourceManager.shared.toggleConfigSource(id: uuid)
        loadData()
    }

    /// 配置源选中事件
    func tableViewSelectionDidChange(_ notification: Notification) {
        guard let tableView = notification.object as? NSTableView else { return }

        if tableView == self.tableView {
            let selectedRow = tableView.selectedRow
            if selectedRow >= 0 && selectedRow < configSources.count {
                selectedConfigSource = configSources[selectedRow]
                selectedConfigSourceId = selectedConfigSource?.id
                updateToolVisibilityTable()
            } else {
                selectedConfigSource = nil
                selectedConfigSourceId = nil
                updateToolVisibilityTable()
            }
        }
    }

    /// 工具可见性复选框点击事件
    @objc private func toolVisibilityCheckboxClicked(_ sender: NSButton) {
        guard let toolId = sender.identifier?.rawValue,
            let source = selectedConfigSource
        else {
            return
        }

        let isVisible = sender.state == .on
        ConfigSourceManager.shared.setToolVisibility(
            configSourceId: source.id,
            toolId: toolId,
            isVisible: isVisible
        )
    }
}
