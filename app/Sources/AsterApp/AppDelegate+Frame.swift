//! AppDelegate Frame（广义窗口）扩展（T-069 拆分，Rule 3）。
//!
//! 决策依据：
//! - frame = 窗口级容器（未来支持窗内分窗，故不用 window 表述）；当前由
//!   AppKit NSWindow 直接承载（Rule 1：不为将来抽象建类型）。frame 状态
//!   （frames / frameFileName / currentFrame）声明在 AppDelegate.swift。
//! - 启动默认 frame 与 ⌘⇧N 共用 makeFrame（单一创建路径；与 AppDelegate+
//!   Storage / AppDelegate+CloseFlow 同模式拆分，Rule 3）。

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

  /// 新 Scratch 文档（⌘N / 新建 Frame / 崩溃恢复共用）：新快照序号 + DM id
  /// + 按 frame 接线的模型。
  ///
  /// 决策依据（ADR-023 v1.3）：每个文档独立快照序号（BUG-010）；内容基线
  /// 空字符串（BUG-012 比较基线）。
  /// internal：存储扩展（恢复分支）调用（Rule 4 / 12 模块边界内封装）。
  func makeScratchModel(in frame: NSWindow) throws -> EditorModel {
    let seq = UInt(try snapshot_create_next(snapshot))
    let id = try document_manager_open_scratch(documentManager)
    let buffer = Buffer(BufferId(UInt64(id)))
    let model = makeModel(buffer, in: frame)
    snapshotSeqByDocId[id] = seq
    committedTextByDocId[id] = ""
    return model
  }

  /// 创建 Frame（启动与 ⌘⇧N 共用，T-069）。
  ///
  /// 决策依据：onOpenFile / onChange 都按 frame 接线。`seedContent` 仅供启动
  /// 默认文档的 CJK 渲染样例（T-012），直接进 Buffer、不进编辑历史、不置脏。
  /// 快照创建失败：启动路径容忍（setupStorage 已提示存储未就绪，窗口照开，
  /// 保存时再报，ADR-004）；用户路径（⌘⇧N）失败必须可见且不建 frame。
  @discardableResult
  func makeFrame(seedContent: String = "", tolerateSnapshotFailure: Bool = false) -> NSWindow? {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered,
      defer: false
    )
    // BUG-017：关闭按钮必须经 windowShouldClose 拦截未决文档决策，
    // 否则窗口先关、提示后弹，取消后无窗口导致终止流程反复重触发。
    window.delegate = self
    let seq: UInt?
    do {
      seq = UInt(try snapshot_create_next(snapshot))
    } catch {
      if tolerateSnapshotFailure {
        NSLog("启动 Frame 快照创建失败（存储未就绪，编辑可继续，保存时再报）：\(error)")
        seq = nil
      } else {
        NSLog("新建 Frame 失败：\(error)")
        presentSaveError("新建 Frame 失败：\(error)")
        return nil
      }
    }
    // Scratch 打开不可失败（无 IO）；兜底 id 1 仅为结构完整性（ADR-004 不静默）。
    let id = (try? document_manager_open_scratch(documentManager)) ?? 1
    let buffer = Buffer(BufferId(UInt64(id)))
    if !seedContent.isEmpty {
      _ = try? buffer_insert(buffer, 0, seedContent)
    }
    let model = makeModel(buffer, in: window)
    let view = MetalView(frame: window.contentLayoutRect, model: model)
    view.onOpenFile = { [weak self] url in self?.open(url) }
    window.contentView = view
    frames.append(window)
    if let seq {
      snapshotSeqByDocId[id] = seq
    }
    committedTextByDocId[id] = ""
    updateWindowTitle(window)
    window.center()
    window.makeKeyAndOrderFront(nil)
    return window
  }
}
