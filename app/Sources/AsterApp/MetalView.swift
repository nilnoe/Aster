//! Metal 渲染视图（T-012，ADR-016）。
//!
//! 决策依据：
//! - IME 用系统 `NSTextInputClient`（Principle 4：不实现输入法）：`keyDown` →
//!   `interpretKeyEvents`，系统回调 `setMarkedText` / `insertText`；组合文本渲染 +
//!   提交写回 Core 是本切片闭环，光标 / 替换区间状态机属 T-013。
//! - 事件驱动刷新：文本变化置 `needsDisplay`（`enableSetNeedsDisplay` + 暂停自绘循环），
//!   无轮询（ADR Performance Goals）。
//! - `insertText` 错误经 NSLog 可见（ADR-004：失败要可见）。

import AppKit
import MetalKit

@MainActor
// `@MainActor NSTextInputClient`：隔离 conformance——协议本身非主 actor 隔离，
// 而实现必须访问主 actor 状态（模型 / 视图），显式把该 conformance 钉在主 actor 上
// （Swift 6.2 #ConformanceIsolation；AppKit 仅在主线程回调这些方法）。
final class MetalView: MTKView, @MainActor NSTextInputClient {
  private let model: EditorModel
  private let renderer: TextRenderer

  init(frame: NSRect, model: EditorModel) {
    guard let device = MTLCreateSystemDefaultDevice() else {
      preconditionFailure("Metal 不可用（T-012，ADR-016）")
    }
    self.model = model
    self.renderer = TextRenderer(device: device, model: model)
    super.init(frame: frame, device: device)
    clearColor = MTLClearColor(red: 0.13, green: 0.13, blue: 0.15, alpha: 1)
    enableSetNeedsDisplay = true
    isPaused = true
    delegate = renderer
  }

  @available(*, unavailable)
  required init(coder: NSCoder) {
    fatalError("不支持 nib 创建（T-011 起程序化启动，ADR-015）")
  }

  // MARK: - NSTextInputClient

  func insertText(_ string: Any, replacementRange: NSRange) {
    guard let text = Self.text(from: string) else { return }
    do {
      try model.insertText(text)
    } catch {
      NSLog("insertText 写入 Core 失败：\(error)")
    }
    needsDisplay = true
  }

  func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
    model.setMarkedText(Self.text(from: string) ?? "")
    needsDisplay = true
  }

  func unmarkText() {
    model.unmarkText()
    needsDisplay = true
  }

  func selectedRange() -> NSRange {
    // spike：插入点恒在文本末尾（UTF-16 长度供系统输入上下文定位）。
    NSRange(location: (model.displayText as NSString).length, length: 0)
  }

  func markedRange() -> NSRange {
    guard model.hasMarkedText else { return NSRange(location: NSNotFound, length: 0) }
    let location = (model.bufferText as NSString).length
    return NSRange(location: location, length: (model.composition as NSString).length)
  }

  func hasMarkedText() -> Bool { model.hasMarkedText }

  func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?)
    -> NSAttributedString?
  {
    nil  // spike：无选区文本访问需求（T-013 实现）
  }

  func validAttributesForMarkedText() -> [NSAttributedString.Key] {
    []
  }

  func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
    actualRange?.pointee = range
    // spike：插入点在文本末尾——返回末行基线附近的窗口坐标矩形（T-013 精确化）。
    let caret = NSRect(x: bounds.maxX - 2, y: bounds.maxY - 40, width: 2, height: 20)
    return window?.convertToScreen(convert(caret, to: nil)) ?? caret
  }

  func characterIndex(for point: NSPoint) -> Int {
    (model.displayText as NSString).length  // spike：全部输入落在末尾
  }

  override func doCommand(by selector: Selector) {
    // 光标移动 / 删除等编辑命令属 T-013 编辑循环（ADR-016 备注）。
  }

  // MARK: - 键盘与焦点

  override func keyDown(with event: NSEvent) {
    interpretKeyEvents([event])
  }

  override var acceptsFirstResponder: Bool { true }

  override func becomeFirstResponder() -> Bool { true }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    window?.makeFirstResponder(self)
  }

  private static func text(from value: Any) -> String? {
    if let string = value as? String {
      return string
    }
    if let attributed = value as? NSAttributedString {
      return attributed.string
    }
    return nil
  }
}
