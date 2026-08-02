//! App 生命周期与壳组装（T-011，ADR-015）。
//!
//! 决策依据：
//! - 启动后只有一个空白窗口（项目哲学）；关闭最后窗口即退出（无后台驻留）。
//! - 关于面板用系统 orderFrontStandardAboutPanel，版本号来自 Core
//!   （App → Bridge → Core 单一路径，版本单一来源，ADR-015）。

import AppKit
import AsterBridge

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.mainMenu = AppMenu.build(aboutTarget: self)
    makeMainWindow()
    NSApp.activate(ignoringOtherApps: true)
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    // 决策依据：壳只提供单个空白窗口，关闭即退出；不后台驻留。
    true
  }

  @objc func showAbout(_ sender: Any?) {
    NSApp.orderFrontStandardAboutPanel(options: [
      .applicationName: AppInfo.name,
      .applicationVersion: AppInfo.version,
    ])
  }

  private func makeMainWindow() {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered,
      defer: false
    )
    window.title = AppInfo.name
    // 样例 Buffer：验证 CJK + 多行渲染链路（T-012，ADR-016）；
    // 真实文档 / Scratch 数据源随 T-013 / T-019 接线。
    let buffer = Buffer(BufferId(1))
    _ = try? buffer_insert(buffer, 0, "你好，世界。Hello, Aster!\nMetal 文本渲染 — 第二行 CJK")
    let model = EditorModel(buffer: buffer)
    window.contentView = MetalView(frame: window.contentLayoutRect, model: model)
    window.center()
    window.makeKeyAndOrderFront(nil)
  }
}
