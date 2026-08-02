//! App 生命周期与壳组装（T-011，ADR-015）。
//!
//! 决策依据：
//! - 启动后只有一个空白窗口（项目哲学）；关闭最后窗口即退出（无后台驻留）。
//! - 关于面板用系统 orderFrontStandardAboutPanel，版本号来自 Core
//!   （App → Bridge → Core 单一路径，版本单一来源，ADR-015）。
//! - 保存模型（T-041，ADR-023 v1.3）：Cmd+N 建快照（日期+序号文件）；内容变更
//!   自动写入缓冲文件（崩溃保护）；Cmd+S 把缓冲合并进当前快照；dirty「●」与
//!   退出保护基于「缓冲 ≠ 快照」的未提交编辑。

import AppKit
import AsterBridge

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  /// DocumentManager 注册表（T-015 首次进产品，Rule 14 存量处置；
  /// 所有打开路径统一经它，ADR-001）。
  private let documentManager = document_manager_new()
  /// 自动保存缓冲 Store（启动时打开并保持连接，崩溃保护；ADR-023 v1.3 决策 2）。
  private var bufferStore: Store?
  /// 纯文本快照目录句柄（T-042，ADR-023 v1.4：Cmd+N 创建 / Cmd+S 合并）。
  private let snapshot = snapshot_new(StorePaths.defaultDirectory())
  /// 当前快照序号（Cmd+N 创建；Cmd+S 合并目标；ADR-023 v1.3 决策 2）。
  private var currentSnapshotSeq: UInt?
  /// 当前文档文件名（标题显示；初始演示 Buffer 显示 App 名）。
  private var currentFileName: String?
  /// 未提交编辑标记（ADR-023 v1.3：缓冲 ≠ 快照；内容变更置脏，Cmd+S 合并后清除）。
  private var isDirty = false
  /// 启动时是否检测到异常退出且有缓冲文档（T-043：崩溃恢复提示）。
  private var needsRecoveryPrompt = false
  private var mainWindow: NSWindow?

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
  /// kill / 崩溃不调用，哨兵保持非干净。
  func applicationWillTerminate(_ notification: Notification) {
    guard let store = bufferStore else { return }
    try? store_set_clean_exit(store, true)
  }

  /// 启动存储：打开缓冲文件 + 创建当日第一个快照（隐式新文档）。
  ///
  /// 决策依据（ADR-023 v1.3）：缓冲连接保持整个会话；快照序号供 Cmd+S 合并。
  /// 初始化失败必须可见（ADR-004），但不阻止启动（可继续编辑，保存时再报）。
  private func setupStorage() {
    do {
      let dir = StorePaths.defaultDirectory()
      let store = try store_open_buffer(dir)
      bufferStore = store
      currentSnapshotSeq = UInt(try snapshot_create_next(snapshot))
      // T-043：先读哨兵（上次是否异常退出），随即清哨兵（本次运行期间的崩溃
      // 检测基准）；再枚举缓冲文档决定是否提示恢复。
      let cleanExit = try store_is_clean_exit(store)
      try store_set_clean_exit(store, false)
      needsRecoveryPrompt = Self.shouldOfferRecovery(
        cleanExit: cleanExit,
        bufferedDocCount: store_scratch_ids(store).count
      )
    } catch {
      NSLog("存储初始化失败：\(error)")
    }
  }

  /// 崩溃恢复提示（T-043，ADR-013 v1.1）：恢复最近一个缓冲文档，忽略则保留在缓冲。
  ///
  /// 决策依据：缓冲是崩溃保护的连续工作副本（ADR-023 v1.4）；恢复 = 载入最新
  /// 内容并置脏（用户经 Cmd+S 合并进新快照）；其余缓冲文档随 T-029 会话完整恢复。
  private func presentRecoveryIfNeeded() {
    guard needsRecoveryPrompt, let store = bufferStore else { return }
    let ids = store_scratch_ids(store)
    guard let latest = ids.max() else { return }
    let alert = NSAlert()
    alert.messageText = "检测到异常退出"
    alert.informativeText =
      "上次会话未正常退出，发现 \(ids.count) 个未提交文档。要恢复最近的一个吗？"
      + "（未恢复的内容仍保留在缓冲中）"
    alert.addButton(withTitle: "恢复")
    alert.addButton(withTitle: "忽略")
    guard alert.runModal() == .alertFirstButtonReturn else { return }
    do {
      let text = try store_load_scratch(store, latest).toString()
      let id = try document_manager_open_scratch(documentManager)
      let buffer = Buffer(BufferId(UInt64(id)))
      _ = try buffer_insert(buffer, 0, text)
      let model = makeModel(buffer)
      if let view = mainWindow?.contentView as? MetalView {
        view.load(model)
      }
      currentSnapshotSeq = UInt(try snapshot_create_next(snapshot))
      currentFileName = nil
      isDirty = true
      updateWindowTitle()
    } catch {
      NSLog("恢复文档失败：\(error)")
      presentSaveError("\(error)")
    }
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    // 决策依据：壳只提供单个空白窗口，关闭即退出；不后台驻留。
    true
  }

  /// 退出前未提交保护（ADR-023 v1.3）：不静默丢编辑（I-002 主诉）。
  ///
  /// 决策依据：系统关闭流程（关闭最后窗口 / Cmd+Q）都会经此；「保存」失败必须
  /// 阻止退出（ADR-004：失败可见），让用户自己决定。
  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    guard isDirty else { return .terminateNow }
    let alert = NSAlert()
    alert.messageText = "有未提交的更改"
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
      currentFileName = nil
      isDirty = false
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
      isDirty = false
      updateWindowTitle()
    } catch {
      NSLog("打开文档失败：\(error)")
      presentOpenError(error)
    }
  }

  /// 保存当前文档（⌘S / 退出保护共用）：成功返回 true。
  ///
  /// 决策依据（T-041，ADR-023 v1.3）：Cmd+S = 把缓冲内容合并进当前快照（提交 /
  /// 固化），不是新建文件；合并成功后 dirty 清除；失败必须可见（ADR-004）。
  @objc func saveDocument(_ sender: Any?) {
    _ = saveCurrentDocument()
  }

  @discardableResult
  private func saveCurrentDocument() -> Bool {
    guard let view = mainWindow?.contentView as? MetalView,
      let seq = currentSnapshotSeq
    else {
      presentSaveError("当前没有快照可合并")
      return false
    }
    do {
      // Cmd+S = 合并：缓冲文本覆盖写进当前快照（提交 / 固化，ADR-023 v1.4）。
      try snapshot_write(snapshot, seq, view.model.bufferText)
      isDirty = false
      updateWindowTitle()
      return true
    } catch {
      NSLog("保存文档失败：\(error)")
      presentSaveError("\(error)")
      return false
    }
  }

  /// 内容变更：置脏 + 更新标题 + 自动写缓冲（ADR-023 v1.3）。
  ///
  /// 决策依据：EditorModel.onChange 在 makeModel 统一接线（修复启动默认 Buffer
  /// 未接线导致无 dirty / 退出保护失效的 bug）；缓冲写失败不阻塞编辑（日志可见，
  /// ADR-004 精神：失败不静默，但不打断输入流）。
  private func onContentChanged() {
    isDirty = true
    updateWindowTitle()
    autoSaveToBuffer()
  }

  /// 自动保存：当前编辑内容写入缓冲文件（崩溃保护）。
  private func autoSaveToBuffer() {
    guard let store = bufferStore,
      let view = mainWindow?.contentView as? MetalView
    else { return }
    do {
      try store_save_scratch(store, UInt(view.model.bufferIdValue), view.model.bufferText)
    } catch {
      NSLog("缓冲自动保存失败：\(error)")
    }
  }

  /// 统一创建 EditorModel 并接线内容变更回调（onChange → onContentChanged）。
  ///
  /// 决策依据（T-041）：启动默认 Buffer 与打开的文件都走同一接线，杜绝此前
  /// 只在 open() 接线导致的「默认文档无 dirty ● / 无退出保护」。
  private func makeModel(_ buffer: Buffer) -> EditorModel {
    let model = EditorModel(buffer: buffer)
    model.onChange = { [weak self] in self?.onContentChanged() }
    return model
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
    // 启动默认文档 = 首个 Scratch（DM 分配唯一 id，作保存键；ADR-001 v1.2）。
    // Scratch 打开不可失败（无 IO）；兜底 id 1 仅为结构完整性（ADR-004 不静默）。
    let id = (try? document_manager_open_scratch(documentManager)) ?? 1
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
