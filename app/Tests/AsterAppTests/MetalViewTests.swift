//! MetalView 键盘 / 滚动路由契约测试（BUG-003 回归；T-018 水平滚动）。
//!
//! 组合文本激活期间，所有按键（尤其回车）必须交还系统输入法，否则 IME 无法提交
//! （Principle 4：不实现输入法，不绕过输入管线）；滚轮事件必须驱动 Viewport
//! 横向 / 纵向平移（ADR-019）。

import AppKit
import AsterBridge
import CoreGraphics
import XCTest

@testable import AsterApp

@MainActor
final class MetalViewTests: XCTestCase {
  /// 像素单位的滚轮事件（precise delta）：wheel1 纵向、wheel2 横向。
  /// 符号方向受系统「自然滚动」偏好影响（NSEvent 已在事件层按偏好反转，
  /// isDirectionInvertedFromDevice），断言只验证量级与轴映射，不依赖方向。
  private func makeScrollEvent(deltaX: CGFloat, deltaY: CGFloat) -> NSEvent? {
    guard
      let cgEvent = CGEvent(
        scrollWheelEvent2Source: nil,
        units: .pixel,
        wheelCount: 2,
        wheel1: Int32(deltaY),
        wheel2: Int32(deltaX),
        wheel3: 0
      )
    else { return nil }
    return NSEvent(cgEvent: cgEvent)
  }

  private func makeReturnEvent() -> NSEvent? {
    NSEvent.keyEvent(
      with: .keyDown,
      location: .zero,
      modifierFlags: [],
      timestamp: 0,
      windowNumber: 0,
      context: nil,
      characters: "\r",
      charactersIgnoringModifiers: "\r",
      isARepeat: false,
      keyCode: 36
    )
  }

  func testReturnDuringCompositionYieldsToInputMethod() throws {
    guard MTLCreateSystemDefaultDevice() != nil else {
      throw XCTSkip("Metal 不可用（CI 无 GPU 时跳过）")
    }
    let model = EditorModel(buffer: Buffer(BufferId(30)))
    try model.typeText("ab")
    model.move(.docEnd, extend: false)
    model.setMarkedText("你好")
    let view = MetalView(frame: NSRect(x: 0, y: 0, width: 400, height: 300), model: model)
    let event = try XCTUnwrap(makeReturnEvent())

    view.keyDown(with: event)

    // BUG-003 回归：组合期间回车必须交还输入法——组合保留、Buffer 无换行。
    XCTAssertTrue(model.hasMarkedText, "组合期间回车不应清空组合文本")
    XCTAssertEqual(model.bufferText, "ab", "组合期间回车不应向 Buffer 插入换行")
  }

  /// T-018（ADR-019）：滚轮横向 delta 必须驱动 scrollX。
  /// 方向符号受系统「自然滚动」偏好影响（NSEvent 在事件层已按偏好反转，
  /// isDirectionInvertedFromDevice）；视图沿用纵向同款 `-delta` 约定，方向
  /// 语义与系统偏好一致，本测试只验证轴映射与量级——先平移到可视区中部，
  /// 正 / 负 delta 都不会被钳制。
  func testScrollWheelHorizontalDeltaPansViewport() throws {
    guard MTLCreateSystemDefaultDevice() != nil else {
      throw XCTSkip("Metal 不可用（CI 无 GPU 时跳过）")
    }
    let model = EditorModel(buffer: Buffer(BufferId(31)))
    // 100 字符 ≈ 880pt ≫ 视口 400pt，横向滚动有钳制空间。
    try model.typeText(String(repeating: "abcdefghij", count: 10))
    let view = MetalView(frame: NSRect(x: 0, y: 0, width: 400, height: 300), model: model)
    view.viewport = Viewport(scrollX: 240)
    let event = try XCTUnwrap(makeScrollEvent(deltaX: 50, deltaY: 0))

    view.scrollWheel(with: event)

    XCTAssertEqual(
      abs(view.viewport.scrollX - 240), 50, accuracy: 1, "横向 delta 必须驱动 scrollX"
    )
    XCTAssertEqual(view.viewport.scrollY, 0, accuracy: 1)
  }

  /// T-018（ADR-019）：纵向滚轮行为与原实现一致（回归）。
  func testScrollWheelVerticalDeltaStillScrollsVertically() throws {
    guard MTLCreateSystemDefaultDevice() != nil else {
      throw XCTSkip("Metal 不可用（CI 无 GPU 时跳过）")
    }
    let model = EditorModel(buffer: Buffer(BufferId(32)))
    // 40 行 ≈ 840pt 内容 > 300pt 视口，纵向有钳制空间。
    try model.typeText((1...40).map { "line\($0)" }.joined(separator: "\n"))
    let view = MetalView(frame: NSRect(x: 0, y: 0, width: 400, height: 300), model: model)
    view.viewport = Viewport(scrollY: 270)
    let event = try XCTUnwrap(makeScrollEvent(deltaX: 0, deltaY: 100))

    view.scrollWheel(with: event)

    XCTAssertEqual(
      abs(view.viewport.scrollY - 270), 100, accuracy: 1, "纵向 delta 必须驱动 scrollY"
    )
    XCTAssertEqual(view.viewport.scrollX, 0, accuracy: 1)
  }

  /// BUG-006 回归（接线）：行末光标经 scrollCursorIntoView 后必须停在右缘
  /// 12pt 留白内，scrollCursorIntoView 必须把 rightPad 传给 Viewport。
  func testCursorAtLineEndStaysInsideRightMargin() throws {
    guard MTLCreateSystemDefaultDevice() != nil else {
      throw XCTSkip("Metal 不可用（CI 无 GPU 时跳过）")
    }
    let model = EditorModel(buffer: Buffer(BufferId(33)))
    // 78 字符 ≈ 690pt ≫ 视口 600pt，横向滚动有钳制空间。
    try model.typeText(String(repeating: "abcdefghijklmnopqrstuvwxyz", count: 3))
    let view = MetalView(frame: NSRect(x: 0, y: 0, width: 600, height: 300), model: model)
    model.move(.docEnd, extend: false)

    view.scrollCursorIntoView()

    let layout = LineLayout(text: model.lines[0], font: view.renderer.font)
    let caretX = view.renderer.leftPadPts + layout.width - view.viewport.scrollX
    XCTAssertLessThanOrEqual(
      caretX, view.bounds.width - view.renderer.rightPadPts + 0.5,
      "末尾光标必须停在右缘留白内（BUG-006）"
    )
    XCTAssertGreaterThanOrEqual(caretX, 0)
  }

  /// BUG-006 回归（用户场景）：横向滚动到行末后按回车，新行行首光标必须停在
  /// 左留白处（scrollX 归零，左侧边距恢复），而不是贴 x=0 把边距滚出视口。
  func testReturnAfterHorizontalScrollRestoresLeftMargin() throws {
    guard MTLCreateSystemDefaultDevice() != nil else {
      throw XCTSkip("Metal 不可用（CI 无 GPU 时跳过）")
    }
    let model = EditorModel(buffer: Buffer(BufferId(34)))
    try model.typeText(String(repeating: "abcdefghijklmnopqrstuvwxyz", count: 3))
    let view = MetalView(frame: NSRect(x: 0, y: 0, width: 600, height: 300), model: model)
    model.move(.docEnd, extend: false)
    view.scrollCursorIntoView()
    XCTAssertGreaterThan(view.viewport.scrollX, 0, "前置：行末必须已横向滚动")

    let enter = try XCTUnwrap(makeReturnEvent())
    view.keyDown(with: enter)

    XCTAssertEqual(view.viewport.scrollX, 0, "回车到行首后 scrollX 必须归零（BUG-006）")
    XCTAssertEqual(
      view.renderer.leftPadPts - view.viewport.scrollX, 12,
      "行首光标必须停在左留白 12pt 处"
    )
  }
}
