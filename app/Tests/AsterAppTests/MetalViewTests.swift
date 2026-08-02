//! MetalView 键盘路由契约测试（BUG-003 回归）。
//!
//! 组合文本激活期间，所有按键（尤其回车）必须交还系统输入法，否则 IME 无法提交
//! （Principle 4：不实现输入法，不绕过输入管线）。

import AppKit
import AsterBridge
import XCTest

@testable import AsterApp

@MainActor
final class MetalViewTests: XCTestCase {
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
}
