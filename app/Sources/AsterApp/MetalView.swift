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
  var model: EditorModel
  let renderer: TextRenderer
  /// 视口滚动状态（internal：输入扩展与测试需要读写；App 模块内封装，
  /// Rule 4 / Rule 12 在模块边界内成立）。
  var viewport = Viewport()
  /// 文件拖入回调（T-015，ADR-001）：视图只采集拖放事件，打开逻辑由
  /// AppDelegate 经 DocumentManager 执行（薄 UI；回调而非协议，Rule 2）。
  var onOpenFile: ((URL) -> Void)?
  private var mouseAnchorByte = 0
  /// 光标闪烁相位状态机（T-017 / BUG-018：独立类型，Rule 3 拆分；关闭时由
  /// windowWillClose 调 stop 打断 Timer 保留环）。
  private let blinker = CaretBlinker()
  /// 窗口关闭中（BUG-018 2026-08-03 崩溃报告定位）：关闭放行后禁止再渲染——
  /// 光标定时器每 0.5s 触发一帧绘制，若窗口图层树拆毁时仍有 in-flight drawable，
  /// CA 事务提交会在 autorelease 里双重释放（objc_release 坏指针）。
  /// 只关新建 frame 崩溃（App 继续运行）、关最后窗口不崩（进程退出）与此吻合。
  private(set) var isClosing = false

  init(frame: NSRect, model: EditorModel) {
    guard let device = MTLCreateSystemDefaultDevice() else {
      preconditionFailure("Metal 不可用（T-012，ADR-016）")
    }
    self.model = model
    self.renderer = TextRenderer(device: device)
    super.init(frame: frame, device: device)
    registerForDraggedTypes([.fileURL])
    clearColor = MTLClearColor(red: 0.13, green: 0.13, blue: 0.15, alpha: 1)
    enableSetNeedsDisplay = true
    isPaused = true
    delegate = self
    blinker.onTick = { [weak self] in self?.needsDisplay = true }
    blinker.start()
  }

  @available(*, unavailable)
  required init(coder: NSCoder) {
    fatalError("不支持 nib 创建（T-011 起程序化启动，ADR-015）")
  }

  /// 替换当前编辑会话（T-015 打开文件）：重置视口并重绘。
  ///
  /// 决策依据：打开文件 = 新 Buffer + 新 Editor（undo 历史随文档重置是预期
  /// 行为）；视口回原点避免打开后停留在旧文档的滚动位置。
  func load(_ newModel: EditorModel) {
    model = newModel
    viewport = Viewport()
    needsDisplay = true
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

  // MARK: - 文件拖放（T-015，ADR-001：Disk 源经 DocumentManager 打开）
  //
  // 决策依据：NSView 已内建 NSDraggingDestination 一致性，只 override 两个
  // 方法；拖入文件 = 打开（加载内容，不移动原文件；系统能力，Principle 4）。

  override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
    .copy
  }

  override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
    let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self]) as? [URL]
    guard let url = urls?.first else { return false }
    onOpenFile?(url)
    return true
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
    let lineIndex = min(max(0, Int(contentY / lineHeight)), model.lineCount - 1)
    let lineStart = model.lineByteRanges[lineIndex].lowerBound
    let layout = LineLayout(text: model.lineText(lineIndex), font: renderer.font)
    // T-018：渲染 x = 内容 x - scrollX，鼠标命中换算反向补偿。
    let x = point.x - renderer.leftPadPts + viewport.scrollX
    return lineStart + layout.byteOffset(atX: max(0, x))
  }

  /// 内容尺寸：高度 = 行数 × 行高；宽度 = 可见行最大宽度 + 左右留白
  /// （ADR-019 决策 1，不取全文档最宽行；右留白随 BUG-006：否则行末光标
  /// 滚到最右时被 clamp 吃掉留白，光标仍会贴边消失）。
  private func contentSize() -> CGSize {
    let height = CGFloat(model.lineCount) * renderer.lineHeightPts
    let lineWindow = viewport.visibleLineRange(
      lineCount: model.lineCount,
      viewportHeightPts: bounds.height,
      lineHeightPts: renderer.lineHeightPts
    )
    var width: CGFloat = 0
    for lineIndex in lineWindow {
      width = max(
        width,
        renderer.leftPadPts + LineLayout(text: model.lineText(lineIndex), font: renderer.font).width
      )
    }
    return CGSize(width: width + renderer.rightPadPts, height: height)
  }

  /// 编辑 / 移动后把光标带进视野（internal：IME 扩展 insertText 提交后调用）。
  func scrollCursorIntoView() {
    let line = model.lineIndex(ofByteOffset: model.cursorByte)
    let lineRange = model.lineByteRanges[line]
    let layout = LineLayout(text: model.lineText(line), font: renderer.font)
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

  // MARK: - 光标闪烁（T-017，ADR-018；CaretBlinker 管理相位，frame 关闭时
  // windowWillClose 调用 stop——见 AppDelegate+CloseFlow）

  /// 停止光标闪烁（BUG-018）：Timer 以 target/selector 强持有 target 形成
  /// 保留环，且关闭后的窗口仍被 AppKit 保留，定时器会无限期存活。由
  /// AppDelegate.windowWillClose 在 frame 关闭时调用，确定性打断保留环。
  /// internal：窗口关闭流程（AppDelegate+CloseFlow）调用（模块边界内封装）。
  func stopCaretBlink() {
    blinker.stop()
  }

  /// 关闭放行（windowShouldClose 返回 true）时调用：停笔 + 停定时器，
  /// 确保窗口拆毁期间不再产生新绘制（BUG-018 over-release 修复）。
  func beginClosing() {
    isClosing = true
    blinker.stop()
  }

  /// 光标闪烁是否激活（internal：Frame 关闭回归测试断言用）。
  var isCaretBlinkActive: Bool { blinker.isActive }
}

// MARK: - MTKViewDelegate（自绘：事件驱动，仅变化后重绘）

extension MetalView: MTKViewDelegate {
  func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

  func draw(in view: MTKView) {
    // BUG-018：关闭中禁止渲染——即使有残留 needsDisplay / 定时器竞态，
    // 也不再触碰 currentDrawable（in-flight drawable 是 CA teardown 双重
    // 释放的源头）。
    guard !isClosing else { return }
    renderer.render(in: view, model: model, viewport: viewport, caretVisible: blinker.caretVisible)
  }
}
