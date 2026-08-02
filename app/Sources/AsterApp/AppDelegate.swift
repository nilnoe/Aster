//! App 生命周期与壳组装（T-011，ADR-015）。
//!
//! 决策依据：
//! - 启动后只有一个空白窗口（项目哲学）；关闭最后窗口即退出（无后台驻留）。
//! - 关于面板用系统 orderFrontStandardAboutPanel，版本号来自 Core
//!   （App → Bridge → Core 单一路径，版本单一来源，ADR-015）。

import AppKit

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
        // 空白视图：编辑器启动态（项目哲学）；T-012 渲染切片替换为 MetalView。
        window.contentView = NSView(frame: window.contentLayoutRect)
        window.center()
        window.makeKeyAndOrderFront(nil)
    }
}
