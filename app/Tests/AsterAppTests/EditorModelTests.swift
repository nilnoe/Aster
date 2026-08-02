//! EditorModel 契约测试（T-012，ADR-016）。
//!
//! 输入状态机是纯逻辑：ASCII / CJK 插入、IME 组合文本、提交写回 Buffer。
//! 可测逻辑留在 App 模型层，View 层只做事件采集与绘制（docs/testing.md）。

import AsterBridge
import XCTest

@testable import AsterApp

@MainActor
final class EditorModelTests: XCTestCase {
  func testInsertAppendsAtEnd() throws {
    let model = EditorModel(buffer: Buffer(BufferId(1)))
    try model.insertText("Hello")
    XCTAssertEqual(model.bufferText, "Hello")
    XCTAssertEqual(model.insertionOffset, 5)
  }

  func testInsertAfterCJKUsesByteOffsets() throws {
    let model = EditorModel(buffer: Buffer(BufferId(2)))
    try model.insertText("你好")
    XCTAssertEqual(model.insertionOffset, 6)
    try model.insertText("!")
    XCTAssertEqual(model.bufferText, "你好!")
  }

  func testMarkedTextCompositionTracksDisplay() {
    let model = EditorModel(buffer: Buffer(BufferId(3)))
    XCTAssertFalse(model.hasMarkedText)
    model.setMarkedText("nihao")
    XCTAssertTrue(model.hasMarkedText)
    XCTAssertEqual(model.displayText, "nihao")
    model.unmarkText()
    XCTAssertFalse(model.hasMarkedText)
    XCTAssertEqual(model.displayText, "")
  }

  func testCommitCompositionInsertsAndClears() throws {
    let model = EditorModel(buffer: Buffer(BufferId(4)))
    model.setMarkedText("你好")
    try model.commitComposition()
    XCTAssertEqual(model.bufferText, "你好")
    XCTAssertEqual(model.displayText, "你好")
    XCTAssertFalse(model.hasMarkedText)
  }
}
