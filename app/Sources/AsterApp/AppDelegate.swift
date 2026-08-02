//! App 生命周期与壳组装（T-011，ADR-015；T-045 拆分，Rule 3）。
//!
//! 决策依据：
//! - 启动后只有一个空白窗口（项目哲学）；关闭最后窗口即退出（无后台驻留）。
//! - 关于面板用系统 orderFrontStandardAboutPanel，版本号来自 Core
//!   （App → Bridge → Core 单一路径，版本单一来源，ADR-015）。
//! - 保存模型（ADR-023 v1.3）：Cmd+N 建快照（日期+序号文本文件）；内容变更
//!   自动写入缓冲文件（崩溃保护）；Cmd+S 把缓冲合并进当前快照；dirty「●」与
//!   退出保护基于「缓冲 ≠ 快照」的未提交编辑。
//! - 存储 / 保存 / 崩溃恢复逻辑在 `AppDelegate+Storage.swift`（Rule 3 拆分，
//!   MetalView + MetalView+Input 同一模式）。

import AppKit
import AsterBridge

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  /// DocumentManager 注册表（T-015 首次进产品，Rule 14 存量处置；
  /// 所有打开路径统一经它，ADR-001）。
  var documentManager = document_manager_new()
  /// 自动保存缓冲 Store（启动时打开并保持连接，崩溃保护；ADR-023 v1.3）。
  /// internal：存储扩展读写（Rule 4 / 12 模块边界内封装）。
  var bufferStore: Store?
  /// 纯文本快照目录句柄（T-042，ADR-023 v1.4：Cmd+N 创建 / Cmd+S 合并）。
  let snapshot = snapshot_new(StorePaths.defaultDirectory())
  /// 当前快照序号（Cmd+N 创建；Cmd+S 合并目标）。
  var currentSnapshotSeq: UInt?
  /// 当前文档文件名（标题显示；初始演示 Buffer 显示 App 名）。
  var currentFileName: String?
  /// 多文档未提交状态（T-046，ADR-013 v1.4）：进程生命周期内全程检查，
  /// 切换文档 / 打开新文件不抛弃前一个文档的未决状态。
  var pendingDocs = PendingDocs()
  /// 文档 id → 快照序号（⌘N / 恢复 / 打开时登记；⌘S 与退出「保存全部」合并目标）。
  var snapshotSeqByDocId: [UInt: UInt] = [:]
  /// 启动时是否检测到异常退出且有缓冲文档（T-043：崩溃恢复提示）。
  var needsRecoveryPrompt = false
  var mainWindow: NSWindow?

  /// 崩溃恢复决策（T-043，ADR-013 v1.1）：纯函数便于单测。
  ///
  /// 决策依据：哨兵缺失 / 为 false 视为异常退出；缓冲有文档才有内容可恢复。
  nonisolated static func shouldOfferRecovery(cleanExit: Bool, bufferedDocCount: Int) -> Bool {
    !cleanExit && bufferedDocCount > 0
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.mainMenu = AppMenu.build(aboutTarget: self)
    setupStorage()
    makeMainWindow()
    presentRecoveryIfNeeded()
    NSApp.activate(ignoringOtherApps: true)
  }

  /// 正常退出写干净哨兵（T-043）：崩溃路径不执行本回调 → 下次启动提示恢复。
  ///
  /// 决策依据：AppKit 在正常终止（Cmd+Q / 关最后窗口，且未被取消）时调用本方法；
  /// kill / 崩溃不调用，哨兵保持非干净。哨兵不承担数据清理（ADR-013 v1.3）。
  func applicationWillTerminate(_ notification: Notification) {
    guard let store = bufferStore else { return }
    try? store_set_clean_exit(store, true)
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    // 决策依据：壳只提供单个空白窗口，关闭即退出；不后台驻留。
    true
  }

  /// 退出前未提交保护（ADR-023 v1.3）：不静默丢编辑（I-002 主诉）。
  ///
  /// 决策依据：系统关闭流程（关闭最后窗口 / Cmd+Q）都会经此；「保存」失败必须
  /// 阻止退出（ADR-004：失败可见），让用户自己决定。「不保存」删除缓冲行
  /// （ADR-013 v1.3 删除时机 3）。
  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    guard !pendingDocs.isEmpty else { return .terminateNow }
    let alert = NSAlert()
    alert.messageText = "有 \(pendingDocs.count) 个文档存在未提交更改"
    alert.informativeText =
      "包括“\(currentFileName ?? AppInfo.name)”等 \(pendingDocs.count) 个文档。"
      + "保存全部将合并进各自的快照。"
    alert.addButton(withTitle: "保存全部")
    alert.addButton(withTitle: "全部不保存")
    alert.addButton(withTitle: "取消")
    switch alert.runModal() {
    case .alertFirstButtonReturn:
      return saveAllPending() ? .terminateNow : .terminateCancel
    case .alertSecondButtonReturn:
      discardAllPending()
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

  /// File 菜单「新建」（⌘N）：创建当日下一个快照文件 + 新的空白 Scratch 文档。
  ///
  /// 决策依据（T-041，ADR-001 v1.2 / ADR-023 v1.3）：新文档 = 新快照（日期+序号），
  /// 缓冲内容按 id 隔离自动保存；旧文档未提交编辑仍在缓冲（崩溃保护），合并由
  /// 用户回到对应会话时执行（激活文档随 T-024 统一）。
  @objc func newDocument(_ sender: Any?) {
    do {
      let seq = UInt(try snapshot_create_next(snapshot))
      let id = try document_manager_open_scratch(documentManager)
      let buffer = Buffer(BufferId(UInt64(id)))
      let model = makeModel(buffer)
      if let view = mainWindow?.contentView as? MetalView {
        view.load(model)
      }
      currentSnapshotSeq = seq
      snapshotSeqByDocId[id] = seq
      currentFileName = nil
      updateWindowTitle()
    } catch {
      NSLog("新建文档失败：\(error)")
      presentSaveError("\(error)")
    }
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
      let model = makeModel(buffer)
      if let view = mainWindow?.contentView as? MetalView {
        view.load(model)
      }
      currentFileName = url.lastPathComponent
      // T-046：打开的文件继承当前 Scratch 快照作为合并目标（v1 语义）。
      if let seq = currentSnapshotSeq {
        snapshotSeqByDocId[id] = seq
      }
      updateWindowTitle()
    } catch {
      NSLog("打开文档失败：\(error)")
      presentOpenError(error)
    }
  }

  /// 统一创建 EditorModel 并接线内容变更回调（onChange → onContentChanged）。
  ///
  /// 决策依据（T-041）：启动默认 Buffer 与打开的文件都走同一接线，杜绝此前
  /// 只在 open() 接线导致的「默认文档无 dirty ● / 无退出保护」。
  func makeModel(_ buffer: Buffer) -> EditorModel {
    let model = EditorModel(buffer: buffer)
    model.onChange = { [weak self] in self?.onContentChanged() }
    return model
  }

  /// 标题 = [● ] + 文件名（初始演示 Buffer 显示 App 名）。
  func updateWindowTitle() {
    let base = currentFileName ?? AppInfo.name
    let currentDirty =
      (mainWindow?.contentView as? MetalView)
      .map { pendingDocs.contains(UInt($0.model.bufferIdValue)) } ?? false
    mainWindow?.title = currentDirty ? "● \(base)" : base
  }

  func presentSaveError(_ message: String) {
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
    // 启动默认文档 = 首个 Scratch（DM 分配唯一 id，作保存键；ADR-001 v1.2）。
    // Scratch 打开不可失败（无 IO）；兜底 id 1 仅为结构完整性（ADR-004 不静默）。
    let id = (try? document_manager_open_scratch(documentManager)) ?? 1
    // T-046：启动默认文档登记快照序号（合并目标）。
    if let seq = currentSnapshotSeq {
      snapshotSeqByDocId[id] = seq
    }
    // 样例内容验证 CJK + 多行渲染链路（T-012，ADR-016）。
    let buffer = Buffer(BufferId(UInt64(id)))
    _ = try? buffer_insert(buffer, 0, "你好，世界。Hello, Aster!\nMetal 文本渲染 — 第二行 CJK")
    let model = makeModel(buffer)
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
