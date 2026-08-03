//! AppDelegate 退出 / 关闭决策扩展（BUG-017 拆分，Rule 3；T-070 per-frame 修正）。
//!
//! 决策依据：
//! - 与 AppDelegate+Storage 同一拆分模式（T-045）：壳（生命周期 / 窗口 / 菜单
//!   动作）留在 AppDelegate.swift，本文件只承载「未决文档的退出 / 关闭决策」。
//! - BUG-017：关闭按钮路径必须**先决策后关窗**——windowShouldClose 拦截时
//!   决策在窗口仍打开时进行，Cmd+Q 与关闭按钮行为一致。
//! - T-070（ADR-025）修正：关闭决策**按窗口文档**——关 frame B 只问 B；旧实现
//!   全局 resolvePendingDocs，关 B 会弹 frame A 的未决提示（Frame × 关闭流的
//!   既有冲突，BUG-018 用户报告卡死的疑似根因之一）。

import AppKit
import AsterBridge

@MainActor
extension AppDelegate {
  /// 系统退出（Cmd+Q / 关闭最后窗口后）路径的未决决策。
  ///
  /// 决策依据（BUG-017）：与窗口关闭共用决策入口。Cmd+Q / 系统退出时窗口仍在，
  /// 弹提示正常；关闭按钮路径先经 windowShouldClose 决策（未决时不关窗），因此
  /// 到这里未决已清空或用户已取消——不再出现「窗口已关、终止被取消、反复重
  /// 触发」的死循环。
  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    resolvePendingDocs() ? .terminateNow : .terminateCancel
  }

  /// 未决文档决策（退出路径，全局）：返回 true = 可以继续（无未决，或已保存 /
  /// 丢弃全部成功）；false = 用户取消。
  func resolvePendingDocs() -> Bool {
    // T-065：防抖窗口内的编辑必须先落地，退出决策才看得到未决文档——否则
    // 刚输入后立即 Cmd+Q 会带着未冲刷编辑直接终止（静默丢失）。
    flushAutosave()
    guard let session, !session_pending_ids(session).isEmpty else { return true }
    switch presentPendingDocsAlert() {
    case 1:
      return saveAllPending()
    case 0:
      discardAllPending()
      return true
    default:
      return false
    }
  }

  /// 关闭按钮 / ⌘W 拦截（BUG-017）：**该窗口**文档未决时先决策后关窗。
  ///
  /// 决策依据：close 由 AppKit 在本方法返回 true 后执行；取消返回 false 时窗口
  /// 保持打开，未决状态与缓冲行原样保留。
  /// - 非最后窗口（T-070，BUG-019）：只决策该窗口的文档（closeDocumentId
  ///   显式参数，T-074），其他 frame 的未决不受本窗口关闭影响（关 B 只问 B）。
  /// - **最后窗口（BUG-018 修复，2026-08-03）**：关最后一个窗口 = 退出，走
  ///   **全局**未决决策（含无窗口的孤儿未决——⌘N / ⌘O 替换当前模型后遗留、
  ///   崩溃忽略登记）。旧实现只检查该窗口文档，孤儿漏过：窗口先关 → 终止流程
  ///   再弹提示 → 取消后无窗口，`applicationShouldTerminateAfterLastWindowClosed`
  ///   恒 true → AppKit 反复重触发终止 = 弹窗循环 / 菊花旋转（用户确认症状，
  ///   BUG-017 同机制）。全局决策在关窗前完成：取消保窗（不进循环），保存 /
  ///   丢弃成功则关窗后终止流程无未决可弹（干净 terminateNow）。
  func windowShouldClose(_ sender: NSWindow) -> Bool {
    // T-065：关窗决策前先冲刷——防抖窗口内的编辑先落盘，未决才可见
    // （否则编辑后立即关窗会漏过未决决策，直接放行丢编辑）。
    flushAutosave()
    guard let session else { return true }
    let allow: Bool
    if frameDocs.count <= 1 {
      allow = resolvePendingDocs()
    } else {
      guard let id = frameDocumentId(for: sender) else { return true }
      if session_is_pending(session, id) {
        switch presentPendingDocsAlert(closeDocumentId: id) {
        case 1:
          allow = mergePendingDoc(id)
        case 0:
          discardPendingDoc(id)
          allow = true
        default:
          allow = false
        }
      } else {
        allow = true
      }
    }
    // BUG-018（2026-08-03 崩溃报告）：关窗放行时立即「停笔」——停光标定时器
    // 并禁止后续绘制。窗口图层树拆毁期间不得再有 in-flight drawable
    // （CA 事务提交在 autorelease 里双重释放 = objc_release 坏指针崩溃）。
    if allow {
      (sender.contentView as? MetalView)?.beginClosing()
    }
    return allow
  }

  /// Frame 关闭后从登记移除（T-069）：closed 窗口不再参与 currentFrame 回退
  /// 与标题刷新；最后一个 frame 关闭仍由 shouldTerminateAfterLastWindowClosed
  /// 走既有退出流程。
  func windowWillClose(_ notification: Notification) {
    guard let frame = notification.object as? NSWindow else { return }
    // T-074（I-013）：先取关闭文档 id 再移除登记（登记不变量由方法保证）。
    let closingId = frameDocumentId(for: frame)
    // BUG-018：关闭 frame 时停止其 MetalView 光标闪烁——Timer 强持有 view
    // （保留环）且关闭后的窗口仍被 AppKit 保留，不停止则定时器无限期存活。
    (frame.contentView as? MetalView)?.stopCaretBlink()
    frameDocs.removeAll { $0.window === frame }
    // T-070（ADR-025）：关闭 frame = 文档生命周期结束——从 Session 注册表移除
    // （旧实现 DM 注册表随每次新建 / 打开永久增长，从不关闭）。
    if let closingId, let session {
      _ = try? session_close_document(session, closingId)
    }
  }
}
