//! App 生命周期与壳组装（T-011，ADR-015；T-045 拆分，Rule 3）。
//!
//! 决策依据：
//! - 启动后只有一个空白窗口（项目哲学）；关闭最后窗口即退出（无后台驻留）。
//! - 关于面板用系统 orderFrontStandardAboutPanel，版本号来自 Core
//!   （App → Bridge → Core 单一路径，版本单一来源，ADR-015）。
//! - 保存模型（ADR-023 v1.3）：Cmd+N 建快照（日期+序号文本文件）；内容变更
//!   自动写入缓冲文件（崩溃保护）；Cmd+S 把缓冲合并进当前快照；dirty 指示用
//!   系统原生 isDocumentEdited（关闭按钮红点，T-067），退出保护基于「缓冲 ≠
//!   快照」的未提交编辑。
//! - T-070（ADR-025）：文档生命周期状态（未决 / 快照序号 / 固化基线 / 失败
//!   提示）收拢进 Core `Session`，本类只保留 frame（窗口）层视图状态。
//! - 存储 / 保存 / 崩溃恢复逻辑在 `AppDelegate+Storage.swift`（Rule 3 拆分，
//!   MetalView + MetalView+Input 同一模式）。

import AppKit
import AsterBridge

@MainActor
// T-050：移除 `final` 使测试可子类化注入模态提示决策（docs/testing.md 接缝）。
// 决策依据：`final` 只是编译期优化，非架构约束；测试 seam 需要子类覆写
// `presentPendingDocsAlert` / `presentRecoveryAlert`（Rule 9：0 抽象层，
// 只放开一个继承点）。
class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
  /// 文档会话（T-070，ADR-025）：DM 注册表 + 缓冲 + 快照 + 未决 / 快照序号 /
  /// 固化基线 / 失败提示的统一所有者——App 不再持有任何文档生命周期账本
  /// （旧三账本 + 全局布尔导致的 BUG-010~018 由收拢消除）。
  var session: Session?
  /// 启动时是否检测到异常退出且有缓冲文档（T-043：崩溃恢复提示）。
  var needsRecoveryPrompt = false
  /// 全部 Frame 及其文档关联（T-069 / T-074）：frame = 窗口级容器（当前由
  /// AppKit NSWindow 直接承载，Rule 1：不为将来抽象建类型）；frame ↔ 文档
  /// 关联收拢为 `FrameDocument` 单一登记（I-013，替换旧 frames 数组 +
  /// frameFileName 字典两套平行结构）。
  var frameDocs: [FrameDocument] = []
  /// 主线程卡死看门狗（BUG-018 诊断：菊花 = 主线程阻塞，复现难；下次卡死
  /// 由后台探针 NSLog 卡死时间窗，控制台可直接定位）。
  private let watchdog = MainThreadWatchdog()

  deinit {
    // BUG-018：Timer 保留环教训——看门狗退出时确定性停止（测试 teardown 与
    // 生产退出都走 deinit；applicationWillTerminate 提前 stop 幂等）。
    watchdog.stop()
  }

  /// 当前 Frame：键窗口优先（⌘S / ⌘O / ⌘N 作用于用户正在操作的 frame），
  /// 无键窗口时回退第一个（启动早期 / 测试环境）。
  var currentFrame: NSWindow? {
    if let key = NSApp.keyWindow, frameDocs.contains(where: { $0.window === key }) {
      return key
    }
    return frameDocs.first?.window
  }

  /// frame → 当前文档 id（T-074：FrameDocument 单一所有者，I-013）。
  func frameDocumentId(for frame: NSWindow) -> UInt? {
    frameDocs.first { $0.window === frame }?.documentId
  }

  /// frame 的当前文件名（标题用；Scratch 为 nil）。
  func frameFileName(_ frame: NSWindow) -> String? {
    frameDocs.first { $0.window === frame }?.fileName
  }

  /// frame 登记当前文档（新建 / 打开 / 恢复共用）。同一 frame 只保留一条登记
  /// ——不变量由本方法保证（Rule 18）；调用方负责与 view.model 使用同一 id。
  func setFrameDocument(_ frame: NSWindow, documentId: UInt, fileName: String?) {
    if let i = frameDocs.firstIndex(where: { $0.window === frame }) {
      frameDocs[i] = FrameDocument(window: frame, documentId: documentId, fileName: fileName)
    } else {
      frameDocs.append(FrameDocument(window: frame, documentId: documentId, fileName: fileName))
    }
  }

  /// 未决文档总数（Session 单一事实来源；退出提示文案用）。
  var pendingDocsCount: Int {
    session.map { session_pending_ids($0).count } ?? 0
  }

  /// 崩溃恢复决策（T-043，ADR-013 v1.1）：纯函数便于单测。
  ///
  /// 决策依据：哨兵缺失 / 为 false 视为异常退出；缓冲有文档才有内容可恢复。
  nonisolated static func shouldOfferRecovery(cleanExit: Bool, bufferedDocCount: Int) -> Bool {
    !cleanExit && bufferedDocCount > 0
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.mainMenu = AppMenu.build(aboutTarget: self)
    setupStorage()
    // 启动默认 Frame（样例内容验证 CJK + 多行渲染链路，T-012，ADR-016）；
    // 容忍快照创建失败（setupStorage 已提示存储未就绪，窗口照开，保存时再报）。
    makeFrame(seedContent: "你好，世界。Hello, Aster!\nMetal 文本渲染 — 第二行 CJK")
    presentRecoveryIfNeeded()
    watchdog.start()
    NSApp.activate(ignoringOtherApps: true)
  }

  /// 正常退出写干净哨兵（T-043）：崩溃路径不执行本回调 → 下次启动提示恢复。
  ///
  /// 决策依据：AppKit 在正常终止（Cmd+Q / 关最后窗口，且未被取消）时调用本方法；
  /// kill / 崩溃不调用，哨兵保持非干净。哨兵不承担数据清理（ADR-013 v1.3）。
  func applicationWillTerminate(_ notification: Notification) {
    watchdog.stop()
    guard let session else { return }
    _ = try? session_set_clean_exit(session, true)
    // T-047（ADR-023 v1.6）：进程干净退出时删除空快照文件（启动即建 / 从未
    // 输入合并的空文档不累积）；崩溃退出不执行本回调，下次干净退出一并处理。
    _ = try? session_prune_empty(session)
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
  /// 未决文档退出提示（T-050 集成测试接缝；docs/testing.md）。
  ///
  /// 决策依据：模态交互（runModal）无法被测试进程驱动，把「弹窗并返回用户
  /// 选择」抽为 internal 方法，测试子类覆写注入决策；生产路径行为不变
  /// （Rule 9：1 个方法而非抽象层；无依赖注入框架）。
  /// 返回 `Int?`：1 = 保存全部；0 = 全部不保存；nil = 取消。
  /// 关闭窗口路径只决策该窗口的文档（closeDocumentId 非 nil）；退出路径
  /// 决策全部未决（T-070 修正：旧实现全局决策，关 frame B 会弹 frame A 的
  /// 未决提示）。T-074（I-012）：关闭决策上下文改为**显式参数**，不再存
  /// AppDelegate 实例字段（Rule 17 同型模式回潮处置）。
  func presentPendingDocsAlert(closeDocumentId: UInt? = nil) -> Int? {
    let alert = NSAlert()
    let currentName = currentFrame.flatMap { frameFileName($0) } ?? AppInfo.name
    if closeDocumentId != nil {
      alert.messageText = "文档存在未提交更改"
      alert.informativeText =
        "“\(currentName)”存在未保存的更改。保存将合并进其快照；不保存将丢弃更改。"
      alert.addButton(withTitle: "保存")
      alert.addButton(withTitle: "不保存")
    } else {
      alert.messageText = "有 \(pendingDocsCount) 个文档存在未提交更改"
      alert.informativeText =
        "包括“\(currentName)”等 \(pendingDocsCount) 个文档。"
        + "保存全部将合并进各自的快照。"
      alert.addButton(withTitle: "保存全部")
      alert.addButton(withTitle: "全部不保存")
    }
    alert.addButton(withTitle: "取消")
    switch alert.runModal() {
    case .alertFirstButtonReturn: return 1
    case .alertSecondButtonReturn: return 0
    default: return 2
    }
  }

  /// 崩溃恢复提示（T-050 集成测试接缝；docs/testing.md）。
  ///
  /// 决策依据：模态交互（runModal）无法被测试进程驱动，把「弹窗并返回用户
  /// 选择」抽为 internal 类体方法，测试子类覆写注入决策（跨模块覆写要求
  /// 方法声明在类体而非 extension，Swift 语言约束）；生产路径行为不变
  /// （Rule 9：1 个方法而非抽象层；无依赖注入框架）。
  func presentRecoveryAlert(count: Int) -> Int {
    let alert = NSAlert()
    alert.messageText = "检测到异常退出"
    alert.informativeText =
      "上次会话未正常退出，发现 \(count) 个未提交文档。要恢复最近的一个吗？"
      + "（未恢复的内容会登记为未决文档，退出时可一并保存或丢弃）"
    alert.addButton(withTitle: "恢复")
    alert.addButton(withTitle: "忽略")
    return alert.runModal() == .alertFirstButtonReturn ? 1 : 0
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
    guard let frame = currentFrame else { return }
    do {
      let model = try makeScratchModel(in: frame)
      if let view = frame.contentView as? MetalView {
        view.load(model)
      }
      setFrameDocument(frame, documentId: UInt(model.bufferIdValue), fileName: nil)
      updateWindowTitle(frame)
    } catch {
      NSLog("新建文档失败：\(error)")
      presentSaveError(errorText(error))
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
    guard let frame = currentFrame, let session else { return }
    do {
      let id = UInt(try session_open_disk(session, url.path))
      let text = try session_text(session, id).toString()
      let buffer = Buffer(BufferId(UInt64(id)))
      _ = try buffer_insert(buffer, 0, text)
      let model = makeModel(buffer, in: frame)
      if let view = frame.contentView as? MetalView {
        view.load(model)
      }
      setFrameDocument(
        frame, documentId: UInt(model.bufferIdValue), fileName: url.lastPathComponent)
      updateWindowTitle(frame)
    } catch {
      NSLog("打开文档失败：\(error)")
      presentOpenError(errorText(error))
    }
  }

  /// 统一创建 EditorModel 并接线内容变更回调（onChange → onContentChanged，
  /// 按 frame 接线，T-069）。
  ///
  /// 决策依据（T-041）：启动默认 Buffer 与打开的文件都走同一接线，杜绝此前
  /// 只在 open() 接线导致的「默认文档无 dirty / 无退出保护」；T-069 多 Frame
  /// 下弱捕获 frame，编辑各自文档状态互不污染，且避免 frame→view→model→
  /// closure→frame 循环保留。
  func makeModel(_ buffer: Buffer, in frame: NSWindow) -> EditorModel {
    let model = EditorModel(buffer: buffer)
    model.onChange = { [weak self, weak frame] in
      guard let frame else { return }
      self?.onContentChanged(in: frame)
    }
    return model
  }

  /// 标题 = 该 frame 的文件名（Scratch 显示 App 名）；未保存指示用系统原生
  /// `isDocumentEdited`（关闭按钮红点，T-067）。T-069 起按 frame 刷新——
  /// 每个 frame 反映自己的文档状态。
  ///
  /// 决策依据（T-067）：旧实现手拼「● 」前缀进标题文本；macOS 文档编辑状态的
  /// 平台约定是 `NSWindow.isDocumentEdited`——AppKit 自动在左上角关闭按钮内
  /// 画 dirty 点（TextEdit / Pages 同款），与总纲 Principle 4（不 fight 系统）
  /// 和宪法 Rule 11（系统能力优先）一致，并删除自研前缀渲染。
  func updateWindowTitle(_ frame: NSWindow) {
    let base = frameFileName(frame) ?? AppInfo.name
    let currentDirty =
      frameDocumentId(for: frame)
      .map { id -> Bool in
        session.map { session_is_pending($0, id) } ?? false
      } ?? false
    frame.title = base
    frame.isDocumentEdited = currentDirty
  }

  /// 刷新全部 frame 标题（保存全部 / 丢弃后，各 frame 反映各自文档状态，T-069）。
  func refreshFrameTitles() {
    for frameDoc in frameDocs {
      updateWindowTitle(frameDoc.window)
    }
  }

  func presentSaveError(_ message: String) {
    let alert = NSAlert()
    alert.messageText = "无法保存文档"
    alert.informativeText = message
    alert.alertStyle = .warning
    alert.runModal()
  }

  /// 打开失败必须可见（ADR-004），不静默回退到空文档。
  private func presentOpenError(_ message: String) {
    let alert = NSAlert()
    alert.messageText = "无法打开文档"
    alert.informativeText = message
    alert.alertStyle = .warning
    alert.runModal()
  }
}
