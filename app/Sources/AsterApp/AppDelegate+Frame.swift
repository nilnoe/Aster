//! AppDelegate Frame（广义窗口）扩展（T-069 拆分，Rule 3；T-070 经 Session）。
//!
//! 决策依据：
//! - frame = 窗口级容器（未来支持窗内分窗，故不用 window 表述）；当前由
//!   AppKit NSWindow 直接承载（Rule 1：不为将来抽象建类型）。
//! - T-070（ADR-025）：文档创建经 Session 单一入口——`session_open_scratch`
//!   内部完成 DM 注册 + 快照创建（失败容忍）+ 状态登记，App 只拿 id 建编辑
//!   Buffer；旧手工同步三张账本（BUG-010 / 011 来源）不再存在。

import AppKit
import AsterBridge

@MainActor
extension AppDelegate {
  /// 新建 Frame（⌘⇧N，T-069）：新窗口 + 全新 Scratch 文档。
  ///
  /// 决策依据：绑定（⌘⇧N）只存在于 File 菜单（AppMenu 是单一来源——按键将来
  /// 可改，与动作解耦：动作是普通 selector，keyDown 不处理菜单快捷键）。
  @objc func newFrame(_ sender: Any?) {
    makeFrame()
  }

  /// 打开新 Scratch 文档（Session 登记 + 快照序号），返回文档 id。
  func openScratchDoc() throws -> UInt {
    guard let session else {
      // 防御：setupStorage 先于任何 frame 创建（启动顺序），正常不可达；
      // ADR-004 精神：失败可见而非 force unwrap。
      throw NSError(
        domain: "Aster", code: 1,
        userInfo: [NSLocalizedDescriptionKey: "存储未就绪"])
    }
    return UInt(try session_open_scratch(session))
  }

  /// 新 Scratch 文档（⌘N / 新建 Frame / 崩溃恢复共用）：Session 登记 + 按
  /// frame 接线的模型（T-041 统一接线：启动默认与打开的文件同一条路径）。
  func makeScratchModel(in frame: NSWindow) throws -> EditorModel {
    let id = try openScratchDoc()
    let buffer = Buffer(BufferId(UInt64(id)))
    return makeModel(buffer, in: frame)
  }

  /// 创建 Frame（启动与 ⌘⇧N 共用，T-069）。
  ///
  /// 决策依据：onOpenFile / onChange 都按 frame 接线。`seedContent` 仅供启动
  /// 默认文档的 CJK 渲染样例（T-012），直接进 Buffer、不进编辑历史、不置脏。
  @discardableResult
  func makeFrame(seedContent: String = "") -> NSWindow? {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered,
      defer: false
    )
    // BUG-017：关闭按钮必须经 windowShouldClose 拦截未决文档决策，
    // 否则窗口先关、提示后弹，取消后无窗口导致终止流程反复重触发。
    window.delegate = self
    let id: UInt
    do {
      id = try openScratchDoc()
    } catch {
      NSLog("新建 Frame 失败：\(error)")
      presentSaveError("新建 Frame 失败：\(error)")
      return nil
    }
    let buffer = Buffer(BufferId(UInt64(id)))
    if !seedContent.isEmpty {
      _ = try? buffer_insert(buffer, 0, seedContent)
    }
    let model = makeModel(buffer, in: window)
    let view = MetalView(frame: window.contentLayoutRect, model: model)
    view.onOpenFile = { [weak self] url in self?.open(url) }
    window.contentView = view
    frameDocs.append(FrameDocument(window: window, documentId: id, fileName: nil))
    updateWindowTitle(window)
    window.center()
    window.makeKeyAndOrderFront(nil)
    return window
  }
}
