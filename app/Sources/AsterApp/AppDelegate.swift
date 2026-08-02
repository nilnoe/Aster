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
  /// DocumentManager 注册表（T-015 首次进产品，Rule 14 存量处置；
  /// 所有打开路径统一经它，ADR-001）。
  private let documentManager = document_manager_new()
  private var mainWindow: NSWindow?

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

  /// File 菜单「打开…」：NSOpenPanel 选文件（系统能力，Principle 4）。
  @objc func openDocument(_ sender: Any?) {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = false
    panel.begin { [weak self] response in
      guard response == .OK, let url = panel.url else { return }
      self?.open(url)
    }
  }

  /// 打开文件：DocumentManager Disk 源读入 → 新建 Editor 会话 → 替换当前内容。
  ///
  /// 决策依据（T-015，ADR-001 v1.1）：注册表持有的 Buffer 副本与编辑会话分离，
  /// 激活文档统一归属随 T-024（Command Palette）落地，本切片不引入激活状态。
  func open(_ url: URL) {
    do {
      let id = try document_manager_open_disk(documentManager, url.path)
      let text = document_manager_text(documentManager, id).toString()
      let buffer = Buffer(BufferId(UInt64(id)))
      _ = try buffer_insert(buffer, 0, text)
      let model = EditorModel(buffer: buffer)
      if let view = mainWindow?.contentView as? MetalView {
        view.load(model)
      }
      mainWindow?.title = url.lastPathComponent
    } catch {
      NSLog("打开文档失败：\(error)")
      presentOpenError(error)
    }
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
    let view = MetalView(frame: window.contentLayoutRect, model: model)
    view.onOpenFile = { [weak self] url in self?.open(url) }
    window.contentView = view
    mainWindow = window
    window.center()
    window.makeKeyAndOrderFront(nil)
  }

  /// 打开失败必须可见（ADR-004），不静默回退到空文档。
  private func presentOpenError(_ error: Error) {
    let alert = NSAlert()
    alert.messageText = "无法打开文档"
    alert.informativeText = "\(error)"
    alert.alertStyle = .warning
    alert.runModal()
  }
}
