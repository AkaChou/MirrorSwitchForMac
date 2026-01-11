//
//  main.swift
//  MirrorSwitch
//
//  应用入口点
//

import AppKit

// 创建应用代理并启动应用
let appDelegate = AppDelegate()
let app = NSApplication.shared
app.delegate = appDelegate

// 运行应用（不返回）
app.run()
