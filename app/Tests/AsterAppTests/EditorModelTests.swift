//! EditorModel 契约测试（T-013，ADR-017）。
//!
//! 覆盖：光标输入与合并撤销、选区替换、UTF-16 区间替换（IME）、CJK 退格、
//! Shift 扩展与组合取消、组合文本内联显示与区间、UTF-16 ↔ UTF-8 换算、行切分。

import AsterBridge
import XCTest

@testable import AsterApp

@MainActor
final class EditorModelTests: XCTestCase {
  func testTypeInsertsAtCursorAndMergesUndo() throws {
    let model = EditorModel(buffer: Buffer(BufferId(1)))
    try model.typeText("你好")
    XCTAssertEqual(model.bufferText, "你好")
    XCTAssertEqual(model.cursorByte, 6)
    try model.typeText("!")
    XCTAssertEqual(model.bufferText, "你好!")
    XCTAssertEqual(model.cursorByte, 7)
    try model.undo()
    XCTAssertEqual(model.bufferText, "")
    try model.redo()
    XCTAssertEqual(model.bufferText, "你好!")
  }

  func testSelectionReplaceViaInsertText() throws {
    let model = EditorModel(buffer: Buffer(BufferId(2)))
    try model.typeText("abcdef")
    model.selectAll()
    XCTAssertEqual(model.selectionStartByte, 0)
    XCTAssertEqual(model.selectionEndByte, 6)
    try model.insertText("X", replacementUTF16: nil)
    XCTAssertEqual(model.bufferText, "X")
    try model.undo()
    XCTAssertEqual(model.bufferText, "abcdef")
  }

  func testInsertTextReplacesUTF16Range() throws {
    let model = EditorModel(buffer: Buffer(BufferId(3)))
    try model.typeText("你好abc")
    // "好a" 的 UTF-16 区间 [1, 3) → 字节 [3, 7)。
    try model.insertText("X", replacementUTF16: NSRange(location: 1, length: 2))
    XCTAssertEqual(model.bufferText, "你Xbc")
    XCTAssertEqual(model.cursorByte, 4)
  }

  func testDeleteBackwardCJK() throws {
    let model = EditorModel(buffer: Buffer(BufferId(4)))
    try model.typeText("你好")
    model.move(.docEnd, extend: false)
    try model.deleteBackward()
    XCTAssertEqual(model.bufferText, "你")
    XCTAssertEqual(model.cursorByte, 3)
  }

  func testMoveExtendsSelectionAndClearsComposition() throws {
    let model = EditorModel(buffer: Buffer(BufferId(5)))
    try model.typeText("abcde")
    model.move(.docStart, extend: false)
    model.move(.right, extend: true)
    model.move(.right, extend: true)
    XCTAssertEqual(model.selectionStartByte, 0)
    XCTAssertEqual(model.selectionEndByte, 2)
    model.setMarkedText("中")
    XCTAssertTrue(model.hasMarkedText)
    model.move(.right, extend: false)
    XCTAssertFalse(model.hasMarkedText)
    XCTAssertEqual(model.cursorByte, 3)
  }

  func testMarkedTextInlineDisplayAndUTF16Range() throws {
    let model = EditorModel(buffer: Buffer(BufferId(6)))
    try model.typeText("ab")
    model.setMarkedText("你")
    XCTAssertEqual(model.displayText, "ab你")
    XCTAssertEqual(model.markedByteRange, 2..<5)
    XCTAssertEqual(model.markedUTF16Range, NSRange(location: 2, length: 1))
    model.unmarkText()
    XCTAssertEqual(model.displayText, "ab")
  }

  func testCommitCompositionInsertsAtCursor() throws {
    let model = EditorModel(buffer: Buffer(BufferId(7)))
    try model.typeText("ab")
    model.move(.docStart, extend: false)
    model.setMarkedText("中")
    try model.insertText("中", replacementUTF16: model.markedUTF16Range)
    XCTAssertEqual(model.bufferText, "中ab")
    XCTAssertFalse(model.hasMarkedText)
  }

  func testUTF16ByteConversions() {
    let text = "你好a"
    XCTAssertEqual(EditorModel.byteOffset(ofUTF16: 0, in: text), 0)
    XCTAssertEqual(EditorModel.byteOffset(ofUTF16: 1, in: text), 3)
    XCTAssertEqual(EditorModel.byteOffset(ofUTF16: 2, in: text), 6)
    XCTAssertEqual(EditorModel.byteOffset(ofUTF16: 3, in: text), 7)
  }

  func testLinesAndRangesSplit() {
    let text = "ab\n你好\n"
    XCTAssertEqual(EditorModel.splitLines(text), ["ab", "你好", ""])
    XCTAssertEqual(EditorModel.lineRanges(of: text), [0..<2, 3..<9, 10..<10])
  }
}
