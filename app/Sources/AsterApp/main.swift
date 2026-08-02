//! Aster 启动入口（T-011，ADR-015）。
//!
//! 决策依据：程序化启动 NSApplication（无 xib / storyboard）——极简、可编程
//! （项目哲学）；AppKit 非 SwiftUI 壳用 main.swift 显式引导（@main 不适用）。

import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
