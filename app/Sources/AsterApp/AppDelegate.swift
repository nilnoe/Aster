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
  /// 当前文档文件名（标题显示；初始演示 Buffer 显示 App 名）。
  private var currentFileName: String?
  /// 未保存编辑标记（T-037，ADR-023 决策 4：内容变更才置脏）。
  private var isDirty = false
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

  /// 退出前未保存保护（T-037，ADR-023 决策 4）：不静默丢编辑（I-002 主诉）。
  ///
  /// 决策依据：系统关闭流程（关闭最后窗口 / Cmd+Q）都会经此；「保存」失败必须
  /// 阻止退出（ADR-004：失败可见），让用户自己决定。
  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    guard isDirty else { return .terminateNow }
    let alert = NSAlert()
    alert.messageText = "有未保存的更改"
    alert.informativeText = "要保存对“\(currentFileName ?? AppInfo.name)”的更改吗？"
    alert.addButton(withTitle: "保存")
    alert.addButton(withTitle: "不保存")
    alert.addButton(withTitle: "取消")
    switch alert.runModal() {
    case .alertFirstButtonReturn:
      return saveCurrentDocument() ? .terminateNow : .terminateCancel
    case .alertSecondButtonReturn:
      return .terminateNow
    default:
      return .terminateCancel
    }
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
      model.onChange = { [weak self] in self?.markDirty() }
      if let view = mainWindow?.contentView as? MetalView {
        view.load(model)
      }
      currentFileName = url.lastPathComponent
      isDirty = false
      updateWindowTitle()
    } catch {
      NSLog("打开文档失败：\(error)")
      presentOpenError(error)
    }
  }

  /// 保存当前文档（⌘S / 退出保护共用）：成功返回 true。
  ///
  /// 决策依据（T-040，ADR-023 v1.2）：文本来自 Editor 会话（ADR-017），每次保存
  /// 经 Bridge 新建当日「日期+序号」SQLite 快照文件（同日多版本，无需用户指定
  /// 路径）；失败必须可见（ADR-004）。
  @objc func saveDocument(_ sender: Any?) {
    _ = saveCurrentDocument()
  }

  @discardableResult
  private func saveCurrentDocument() -> Bool {
    guard let view = mainWindow?.contentView as? MetalView
    else {
      presentSaveError("没有可保存的视图")
      return false
    }
    do {
      let store = try store_open_next(StorePaths.defaultDirectory())
      try store_save_scratch(store, UInt(view.model.bufferIdValue), view.model.bufferText)
      isDirty = false
      updateWindowTitle()
      return true
    } catch {
      NSLog("保存文档失败：\(error)")
      presentSaveError("\(error)")
      return false
    }
  }

  /// 内容变更后置脏并更新标题（EditorModel.onChange）。
  private func markDirty() {
    isDirty = true
    updateWindowTitle()
  }

  /// 标题 = [● ] + 文件名（初始演示 Buffer 显示 App 名）。
  private func updateWindowTitle() {
    let base = currentFileName ?? AppInfo.name
    mainWindow?.title = isDirty ? "● \(base)" : base
  }

  private func presentSaveError(_ message: String) {
    let alert = NSAlert()
    alert.messageText = "无法保存文档"
    alert.informativeText = message
    alert.alertStyle = .warning
    alert.runModal()
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
