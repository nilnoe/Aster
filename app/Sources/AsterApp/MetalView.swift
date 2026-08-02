//! Metal 渲染视图（T-012 ADR-016 + T-013 ADR-017 + T-018 ADR-019）。
//!
//! 决策依据：
//! - 键盘 / 鼠标 / 滚轮只做事件采集与坐标换算，编辑决策全部进 Core `Editor`
//!   （薄 UI，docs/testing.md）；方向键 / 退格按 keyCode 直连（比 selector 名字
//!   可靠），普通字符与 IME 走 `interpretKeyEvents`（系统能力，Principle 4）。
//! - 滚动是视图状态（ADR-017 / ADR-019）：`Viewport` 持有 scrollX / scrollY，
//!   编辑 / 移动后滚到光标可见（含横向，ADR-019 决策 1）；内容宽度按可见行
//!   最大宽度测量（ADR-019）。
//! - 菜单动作（撤销 / 重做 / 全选）经响应链到本视图（ADR-015 菜单接线）。
//! - 本文件是视图骨架；IME 客户端在 `MetalView+Input.swift`（Rule 3 拆分，
//!   T-018）；IME 区间（UTF-16）经 EditorModel 换算成字节后进 Core
//!   （ADR-017 备注）。

import AppKit
import MetalKit

@MainActor
// 隔离 conformance（NSTextInputClient）声明在 MetalView+Input.swift：协议非主
// actor 隔离，实现访问主 actor 状态（Swift 6.2 #ConformanceIsolation；AppKit
// 仅在主线程回调，ADR-016 备注）。
final class MetalView: MTKView {
  let model: EditorModel
  let renderer: TextRenderer
  /// 视口滚动状态（internal：输入扩展与测试需要读写；App 模块内封装，
  /// Rule 4 / Rule 12 在模块边界内成立）。
  var viewport = Viewport()
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

  // MARK: - 光标外观

  override func resetCursorRects() {
    super.resetCursorRects()
    // BUG-005：文本编辑区必须显示 I 型光标（系统能力，Principle 4）。
    addCursorRect(bounds, cursor: .iBeam)
  }

  // MARK: - 滚动（T-018：横向 + 纵向平移，ADR-019）

  override func scrollWheel(with event: NSEvent) {
    // Shift+滚轮：macOS 在事件层已把纵向滚轮交换成横向 delta（Mozilla Bug
    // 143038 / mpv commit b726f1e 印证），直接读 scrollingDeltaX 即可，不手写
    // Shift 分支（系统能力，Principle 4）。符号与纵向一致：内容随手势反向移动
    // （与 NSScrollView 默认一致）。
    viewport.pan(
      deltaX: -event.scrollingDeltaX,
      deltaY: -event.scrollingDeltaY,
      contentSize: contentSize(),
      viewportSize: bounds.size
    )
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

  /// 点 → 字节偏移（鼠标命中；internal：IME 扩展 firstRect 需要，模块内封装）。
  func byteOffset(at point: NSPoint) -> Int {
    let lineHeight = renderer.lineHeightPts
    let contentY = viewport.scrollY + (bounds.height - point.y)
    let lineIndex = min(max(0, Int(contentY / lineHeight)), model.lines.count - 1)
    let lineStart = model.lineByteRanges[lineIndex].lowerBound
    let layout = LineLayout(text: model.lines[lineIndex], font: renderer.font)
    // T-018：渲染 x = 内容 x - scrollX，鼠标命中换算反向补偿。
    let x = point.x - renderer.leftPadPts + viewport.scrollX
    return lineStart + layout.byteOffset(atX: max(0, x))
  }

  /// 内容尺寸：高度 = 行数 × 行高；宽度 = 可见行最大宽度 + 左右留白
  /// （ADR-019 决策 1，不取全文档最宽行；右留白随 BUG-006：否则行末光标
  /// 滚到最右时被 clamp 吃掉留白，光标仍会贴边消失）。
  private func contentSize() -> CGSize {
    let height = CGFloat(model.lines.count) * renderer.lineHeightPts
    let lineWindow = viewport.visibleLineRange(
      lineCount: model.lines.count,
      viewportHeightPts: bounds.height,
      lineHeightPts: renderer.lineHeightPts
    )
    var width: CGFloat = 0
    for lineIndex in lineWindow {
      width = max(
        width,
        renderer.leftPadPts + LineLayout(text: model.lines[lineIndex], font: renderer.font).width
      )
    }
    return CGSize(width: width + renderer.rightPadPts, height: height)
  }

  /// 编辑 / 移动后把光标带进视野（internal：IME 扩展 insertText 提交后调用）。
  func scrollCursorIntoView() {
    let line = model.lineIndex(ofByteOffset: model.cursorByte)
    let lineRange = model.lineByteRanges[line]
    let layout = LineLayout(text: model.lines[line], font: renderer.font)
    // BUG-004：组合期间光标在组合文本末尾（显示文本内联），横向可见性用同一位置。
    let caretByte = model.cursorByte + (model.hasMarkedText ? model.composition.utf8.count : 0)
    let cursorX =
      renderer.leftPadPts + layout.xOffset(atByteOffset: caretByte - lineRange.lowerBound)
    let lineTop = CGFloat(line) * renderer.lineHeightPts
    viewport.ensureCursorVisible(
      cursorX: cursorX,
      lineTop: lineTop,
      lineHeightPts: renderer.lineHeightPts,
      leftPadPts: renderer.leftPadPts,
      rightPadPts: renderer.rightPadPts,
      contentSize: contentSize(),
      viewportSize: bounds.size
    )
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
    renderer.render(in: view, model: model, viewport: viewport, caretVisible: caretVisible)
  }
}
