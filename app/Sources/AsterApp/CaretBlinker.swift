//! 光标闪烁相位管理（T-017 拆分，Rule 3：MetalView 305 行超限）。
//!
//! 决策依据：
//! - 闪烁 = 0.5s 翻转相位的独立状态机（T-017），从 MetalView 抽出保持单一职责
//!   （与 MetalPipeline / VertexBuilder 同款拆分模式，Rule 3）。
//! - BUG-018：Timer 以 target/selector 强持有 target，形成「timer → blinker →
//!   timer」保留环；且关闭后的窗口仍被 AppKit 保留（ARC 下 isReleasedWhenClosed
//!   不生效）。`stop()` 由 AppDelegate.windowWillClose 在 frame 关闭时确定性
//!   调用，打断保留环并停止无限期定时；MetalView.deinit 兜底。

import AppKit

/// 光标闪烁相位（每 0.5s 翻转 visible；渲染层按相位决定是否画光标，T-017）。
final class CaretBlinker {
  private var timer: Timer?
  private(set) var caretVisible = true
  /// 相位翻转回调（MetalView 置 needsDisplay 触发重绘；闭包而非协议，
  /// Rule 2：无多实现方）。
  var onTick: (() -> Void)?

  /// 启动闪烁：target/selector 走 ObjC 派发，避免 Timer block 的 @Sendable
  /// 捕获问题（Swift 6 主 actor 安全；计时器必然运行在主 RunLoop）。
  func start() {
    guard timer == nil else { return }
    let timer = Timer(
      timeInterval: 0.5,
      target: self,
      selector: #selector(tick),
      userInfo: nil,
      repeats: true
    )
    RunLoop.main.add(timer, forMode: .common)
    self.timer = timer
  }

  /// 停止闪烁（BUG-018：frame 关闭时由 windowWillClose 调用；幂等）。
  func stop() {
    timer?.invalidate()
    timer = nil
  }

  var isActive: Bool { timer != nil }

  @objc private func tick() {
    caretVisible.toggle()
    onTick?()
  }
}
