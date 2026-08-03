//! AppDelegate 退出 / 关闭决策扩展（BUG-017 拆分，Rule 3：AppDelegate 311 行超限）。
//!
//! 决策依据：
//! - 与 AppDelegate+Storage 同一拆分模式（T-045）：壳（生命周期 / 窗口 / 菜单
//!   动作）留在 AppDelegate.swift，本文件只承载「未决文档的退出 / 关闭决策」。
//! - BUG-017：关闭按钮路径必须**先决策后关窗**——旧实现关闭事件直接
//!   关窗、未决提示在系统终止流程里才弹，取消后应用无窗口导致终止反复重触发
//!   （死循环，独立 repro 实测）；windowShouldClose 拦截后决策在窗口仍打开时
//!   进行，Cmd+Q 与关闭按钮共用 resolvePendingDocs，行为一致。

import AppKit

@MainActor
extension AppDelegate {
  /// 系统退出（Cmd+Q / 关闭最后窗口后）路径的未决决策。
  ///
  /// 决策依据（BUG-017）：与窗口关闭共用 resolvePendingDocs。Cmd+Q /
  /// 系统退出时窗口仍在，弹提示正常；关闭按钮路径先经 windowShouldClose 决策
  /// （未决时不关窗），因此到这里的 pendingDocs 已清空或用户已明确取消——
  /// 不再出现「窗口已关、终止被取消、反复重触发」的死循环。
  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    resolvePendingDocs() ? .terminateNow : .terminateCancel
  }

  /// 未决文档决策（窗口关闭 / 退出共用，BUG-017）：返回 true = 可以
  /// 继续（无未决，或已保存 / 丢弃全部成功）；false = 用户取消。
  ///
  /// 决策依据：旧实现把这段逻辑放在 applicationShouldTerminate——关闭按钮路径
  /// 先关窗后决策，取消后应用无窗口，`applicationShouldTerminateAfterLastWindow
  /// Closed` 恒为 true，AppKit 反复重触发终止 = 弹窗死循环（独立 repro 实测）。
  /// 标准 macOS 模式：窗口关闭前经 windowShouldClose 决策，取消则窗口保持。
  func resolvePendingDocs() -> Bool {
    guard !pendingDocs.isEmpty else { return true }
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

  /// 关闭按钮 / ⌘W 拦截（BUG-017）：未决文档存在时**先决策后关窗**。
  ///
  /// 决策依据：见 resolvePendingDocs——close 由 AppKit 在本方法返回 true 后
  /// 执行；取消返回 false 时窗口保持打开，未决状态与缓冲行原样保留。
  func windowShouldClose(_ sender: NSWindow) -> Bool {
    resolvePendingDocs()
  }

  /// Frame 关闭后从登记移除（T-069）：closed 窗口不再参与 currentFrame 回退
  /// 与标题刷新；最后一个 frame 关闭仍由 shouldTerminateAfterLastWindowClosed
  /// 走既有退出流程。
  func windowWillClose(_ notification: Notification) {
    guard let frame = notification.object as? NSWindow else { return }
    // BUG-018：关闭 frame 时停止其 MetalView 光标闪烁——Timer 强持有 view
    // （保留环）且关闭后的窗口仍被 AppKit 保留，不停止则定时器无限期存活。
    (frame.contentView as? MetalView)?.stopCaretBlink()
    frames.removeAll { $0 === frame }
    frameFileName.removeValue(forKey: frame)
  }
}
