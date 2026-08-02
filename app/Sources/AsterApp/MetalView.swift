//! Metal 渲染视图（T-012 ADR-016 + T-013 ADR-017 扩展）。
//!
//! 决策依据：
//! - 键盘 / 鼠标 / 滚轮只做事件采集与坐标换算，编辑决策全部进 Core `Editor`
//!   （薄 UI，docs/testing.md）；方向键 / 退格按 keyCode 直连（比 selector 名字
//!   可靠），普通字符与 IME 走 `interpretKeyEvents`（系统能力，Principle 4）。
//! - 滚动是视图状态（ADR-017）：`scrollY` 点值，编辑 / 移动后滚到光标可见。
//! - 菜单动作（撤销 / 重做 / 全选）经响应链到本视图（ADR-015 菜单接线）。
//! - IME 区间（UTF-16）经 EditorModel 换算成字节后进 Core（ADR-017 备注）。

import AppKit
import MetalKit

@MainActor
// 隔离 conformance：协议非主 actor 隔离，实现访问主 actor 状态（Swift 6.2
// #ConformanceIsolation；AppKit 仅在主线程回调，ADR-016 备注）。
final class MetalView: MTKView, @MainActor NSTextInputClient {
  private let model: EditorModel
  private let renderer: TextRenderer
  private var scrollY: CGFloat = 0
  private var mouseAnchorByte = 0
  /// 光标闪烁相位（T-017）：Timer 每 0.5s 翻转，渲染层按相位决定是否画光标。
  private var caretVisible = true
  /// 仅 deinit 停表使用；实际读写都在主 RunLoop（nonisolated(unsafe) 规避 Swift 6
  /// deinit 的主 actor 隔离限制，引用不跨线程逃逸）。
  nonisolated(unsafe) private var blinkTimer: Timer?

  init(frame: NSRect, model: EditorModel) {
    guard let device = MTLCreateSystemDefaultDevice() else {
      preconditionFailure("Metal 不可用（T-012，ADR-016）")
    }
    self.model = model
    self.renderer = TextRenderer(device: device)
    super.init(frame: frame, device: device)
    clearColor = MTLClearColor(red: 0.13, green: 0.13, blue: 0.15, alpha: 1)
    enableSetNeedsDisplay = true
    isPaused = true
    delegate = self
    startCaretBlink()
  }

  @available(*, unavailable)
  required init(coder: NSCoder) {
    fatalError("不支持 nib 创建（T-011 起程序化启动，ADR-015）")
  }

  // MARK: - NSTextInputClient

  func insertText(_ string: Any, replacementRange: NSRange) {
    guard let text = Self.text(from: string) else { return }
    do {
      try model.insertText(text, replacementUTF16: replacementRange)
    } catch {
      NSLog("insertText 写入 Core 失败：\(error)")
    }
    scrollCursorIntoView()
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
    if model.hasMarkedText {
      // 组合期间光标在组合文本之后（UTF-16）。
      return NSRange(
        location: model.markedUTF16Range.location + model.composition.utf16.count, length: 0)
    }
    return model.utf16Range(fromByteRange: model.selectionStartByte..<model.selectionEndByte)
  }

  func markedRange() -> NSRange {
    model.markedUTF16Range
  }

  func hasMarkedText() -> Bool { model.hasMarkedText }

  func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?)
    -> NSAttributedString?
  {
    nil  // 无选区文本访问需求（T-013 选择渲染经 Core 选区，不读 attributed text）
  }

  func validAttributesForMarkedText() -> [NSAttributedString.Key] {
    []
  }

  func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
    actualRange?.pointee = range
    // 组合候选框跟随光标行（spike 近似：行首到行中；T-013 后按字符精确化）。
    let line = model.lineIndex(ofByteOffset: model.cursorByte)
    let lineTop = CGFloat(line) * renderer.lineHeightPts - scrollY
    let caret = NSRect(
      x: bounds.midX,
      y: bounds.maxY - lineTop - renderer.lineHeightPts * 0.5,
      width: 2,
      height: renderer.lineHeightPts * 0.8
    )
    return window?.convertToScreen(convert(caret, to: nil)) ?? caret
  }

  func characterIndex(for point: NSPoint) -> Int {
    byteOffset(at: point)
  }

  override func doCommand(by selector: Selector) {
    // 移动 / 删除已在 keyDown 直连；其余命令（如完整移动族）本切片不接。
  }

  // MARK: - 键盘（方向 / 退格 / 回车直连，其余走系统输入管线）

  override func keyDown(with event: NSEvent) {
    // BUG-003：组合文本激活期间所有按键（回车 / 方向 / Esc…）必须交还系统输入法
    // （interpretKeyEvents），否则 IME 无法提交组合；回车直连会插入换行并丢弃
    // 组合内容。数字键选词此前正常，正是因为走了默认分支 → interpretKeyEvents。
    if model.hasMarkedText {
      interpretKeyEvents([event])
      needsDisplay = true
      return
    }
    let modifiers = event.modifierFlags
    let shift = modifiers.contains(.shift)
    let command = modifiers.contains(.command)
    switch event.keyCode {
    case 123:  // ←
      model.move(command ? .lineStart : .left, extend: shift)
    case 124:  // →
      model.move(command ? .lineEnd : .right, extend: shift)
    case 125:  // ↓
      model.move(command ? .docEnd : .down, extend: shift)
    case 126:  // ↑
      model.move(command ? .docStart : .up, extend: shift)
    case 51:  // delete（退格）
      do {
        try model.deleteBackward()
      } catch {
        NSLog("deleteBackward 失败：\(error)")
      }
    case 36:  // 回车
      do {
        try model.typeText("\n")
      } catch {
        NSLog("insertNewline 失败：\(error)")
      }
    case 53:  // Esc：取消组合
      model.unmarkText()
    default:
      interpretKeyEvents([event])
      needsDisplay = true
      return
    }
    scrollCursorIntoView()
    needsDisplay = true
  }

  // MARK: - 鼠标（点击定位 / 拖选）

  override func mouseDown(with event: NSEvent) {
    window?.makeFirstResponder(self)
    mouseAnchorByte = byteOffset(at: convert(event.locationInWindow, from: nil))
    model.setSelection(anchor: mouseAnchorByte, head: mouseAnchorByte)
    needsDisplay = true
  }

  override func mouseDragged(with event: NSEvent) {
    let head = byteOffset(at: convert(event.locationInWindow, from: nil))
    model.setSelection(anchor: mouseAnchorByte, head: head)
    scrollCursorIntoView()
    needsDisplay = true
  }

  // MARK: - 滚动

  override func scrollWheel(with event: NSEvent) {
    scrollY -= event.scrollingDeltaY
    clampScroll()
    needsDisplay = true
  }

  // MARK: - 菜单动作（Edit 菜单经响应链，ADR-015 接线）

  @objc func undo(_ sender: Any?) {
    do {
      try model.undo()
    } catch {
      NSLog("undo 失败：\(error)")
    }
    scrollCursorIntoView()
    needsDisplay = true
  }

  @objc func redo(_ sender: Any?) {
    do {
      try model.redo()
    } catch {
      NSLog("redo 失败：\(error)")
    }
    scrollCursorIntoView()
    needsDisplay = true
  }

  @objc override func selectAll(_ sender: Any?) {
    model.selectAll()
    needsDisplay = true
  }

  // MARK: - 坐标换算

  private func byteOffset(at point: NSPoint) -> Int {
    let lineHeight = renderer.lineHeightPts
    let contentY = scrollY + (bounds.height - point.y)
    let lineIndex = min(max(0, Int(contentY / lineHeight)), model.lines.count - 1)
    let lineStart = model.lineByteRanges[lineIndex].lowerBound
    let layout = LineLayout(text: model.lines[lineIndex], font: renderer.font)
    let x = point.x - renderer.leftPadPts
    return lineStart + layout.byteOffset(atX: max(0, x))
  }

  private func clampScroll() {
    let contentHeight = CGFloat(model.lines.count) * renderer.lineHeightPts
    let maxScroll = max(0, contentHeight - bounds.height)
    scrollY = min(max(0, scrollY), maxScroll)
  }

  private func scrollCursorIntoView() {
    let line = model.lineIndex(ofByteOffset: model.cursorByte)
    let lineTop = CGFloat(line) * renderer.lineHeightPts
    let lineBottom = lineTop + renderer.lineHeightPts
    if lineTop < scrollY {
      scrollY = lineTop
    }
    if lineBottom > scrollY + bounds.height {
      scrollY = lineBottom - bounds.height
    }
    clampScroll()
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

  // MARK: - 光标闪烁（T-017，ADR-018）

  deinit {
    blinkTimer?.invalidate()
  }

  private func startCaretBlink() {
    // target/selector 走 ObjC 派发，避免 Timer block 的 @Sendable 捕获问题；
    // 计时器必然运行在主 RunLoop（Swift 6 主 actor 安全）。视图生命周期即窗口
    // 生命周期（关闭最后窗口即退出，ADR-015），deinit 停表。
    let timer = Timer(
      timeInterval: 0.5,
      target: self,
      selector: #selector(blinkTick),
      userInfo: nil,
      repeats: true
    )
    RunLoop.main.add(timer, forMode: .common)
    blinkTimer = timer
  }

  @objc private func blinkTick() {
    caretVisible.toggle()
    needsDisplay = true
  }
}

// MARK: - MTKViewDelegate（自绘：事件驱动，仅变化后重绘）

extension MetalView: MTKViewDelegate {
  func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

  func draw(in view: MTKView) {
    renderer.render(in: view, model: model, scrollY: scrollY, caretVisible: caretVisible)
  }
}
