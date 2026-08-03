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

  /// T-052（BUG-014，SDK NSTextInputClient.h）：setMarkedText 的
  /// replacementRange 必须替换 Buffer 中对应区间（选中文本输入拼音时组合
  /// 直接落在替换位置，不再与选区重叠）。replacementRange 是 UTF-16 语义，
  /// 经 byteRange(fromUTF16:) 换算成字节（ADR-017 备注）。
  func testSetMarkedTextReplacesUTF16SelectionRange() throws {
    let model = EditorModel(buffer: Buffer(BufferId(8)))
    try model.typeText("你好abc")
    // 选中「好a」：UTF-16 [1, 3) → 字节 [3, 7)。
    model.setSelection(anchor: 3, head: 7)

    try model.setMarkedText("n", replacementUTF16: NSRange(location: 1, length: 2))

    XCTAssertEqual(model.bufferText, "你bc", "组合开始必须删除被替换的选区")
    XCTAssertEqual(model.cursorByte, 3, "光标必须折叠到替换起点（「你」之后）")
    XCTAssertTrue(model.hasMarkedText)
    XCTAssertEqual(model.displayText, "你nbc", "组合文本内联在替换位置")
    XCTAssertEqual(model.markedUTF16Range, NSRange(location: 1, length: 1))

    // 提交：组合文本落回 Buffer 的替换位置。
    try model.insertText("你", replacementUTF16: model.markedUTF16Range)
    XCTAssertEqual(model.bufferText, "你你bc")
    XCTAssertFalse(model.hasMarkedText)
  }

  /// T-052（BUG-014）：组合已激活时 replacementRange 为 NSNotFound——
  /// 更新组合只替换组合文本本身，不得再次改动 Buffer。
  func testSetMarkedTextUpdateDoesNotTouchBuffer() throws {
    let model = EditorModel(buffer: Buffer(BufferId(9)))
    try model.typeText("ab")
    try model.setMarkedText("n", replacementUTF16: NSRange(location: NSNotFound, length: 0))
    XCTAssertEqual(model.bufferText, "ab")

    try model.setMarkedText("ni", replacementUTF16: NSRange(location: NSNotFound, length: 0))

    XCTAssertEqual(model.bufferText, "ab", "组合更新不得改动 Buffer")
    XCTAssertEqual(model.composition, "ni")
    XCTAssertEqual(model.displayText, "abni")
  }

  func testUTF16ByteConversions() {
    let text = "你好a"
    XCTAssertEqual(EditorModel.byteOffset(ofUTF16: 0, in: text), 0)
    XCTAssertEqual(EditorModel.byteOffset(ofUTF16: 1, in: text), 3)
    XCTAssertEqual(EditorModel.byteOffset(ofUTF16: 2, in: text), 6)
    XCTAssertEqual(EditorModel.byteOffset(ofUTF16: 3, in: text), 7)
  }

  /// T-072（ADR-026）：行区间语义单一所有者 = Core（layout_line_ranges）；
  /// Swift 只做机械分块，不自行派生「行尾 = 下一行起点 - 1」。
  func testLinesAndRangesSplit() throws {
    let model = EditorModel(buffer: Buffer(BufferId(41)))
    try model.typeText("ab\n你好\n")
    XCTAssertEqual(model.lineByteRanges, [0..<2, 3..<9, 10..<10])
    XCTAssertEqual(model.lines, ["ab", "你好", ""])
  }

  /// T-037（ADR-023 决策 4）：内容变更（type / delete / undo / redo）触发
  /// onChange；光标移动与选区不触发（不置脏）。
  func testOnChangeFiresOnContentMutationOnly() throws {
    let model = EditorModel(buffer: Buffer(BufferId(40)))
    var dirtyCount = 0
    model.onChange = { dirtyCount += 1 }

    try model.typeText("abc")
    XCTAssertEqual(dirtyCount, 1, "输入触发")
    model.move(.right, extend: false)
    model.move(.lineStart, extend: false)
    model.setSelection(anchor: 1, head: 2)
    model.selectAll()
    XCTAssertEqual(dirtyCount, 1, "移动 / 选区不触发")
    try model.deleteBackward()
    XCTAssertEqual(dirtyCount, 2, "退格触发")
    try model.undo()
    XCTAssertEqual(dirtyCount, 3, "undo 触发")
    try model.redo()
    XCTAssertEqual(dirtyCount, 4, "redo 触发")
  }

  /// T-038（I-003）：lineIndex 二分定位在行边界 / 空文本下的语义与线性扫描一致。
  func testLineIndexBinarySearchOnMultilineText() throws {
    let model = EditorModel(buffer: Buffer(BufferId(41)))
    try model.typeText("ab\n你好\n")

    XCTAssertEqual(model.lineIndex(ofByteOffset: 0), 0, "行首")
    XCTAssertEqual(model.lineIndex(ofByteOffset: 2), 0, "\\n 前（行尾）")
    XCTAssertEqual(model.lineIndex(ofByteOffset: 3), 1, "换行后下一行首")
    XCTAssertEqual(model.lineIndex(ofByteOffset: 9), 1, "CJK 行内")
    XCTAssertEqual(model.lineIndex(ofByteOffset: 10), 2, "末行（空行）")
    XCTAssertEqual(model.lineIndex(ofByteOffset: 11), 2, "越界钳制到末行")
  }

  func testLineIndexOnEmptyText() {
    let model = EditorModel(buffer: Buffer(BufferId(42)))
    XCTAssertEqual(model.lineIndex(ofByteOffset: 0), 0, "空文本只有一个空行")
  }

  /// T-038（I-003）：显示缓存随编辑 / 组合变化失效，lineText 反映最新内容。
  func testDisplayCacheTracksEditsAndComposition() throws {
    let model = EditorModel(buffer: Buffer(BufferId(43)))
    try model.typeText("a\nb")

    XCTAssertEqual(model.lineText(0), "a")
    XCTAssertEqual(model.lineText(1), "b")
    XCTAssertEqual(model.lineCount, 2)

    model.setMarkedText("中")
    XCTAssertEqual(model.displayText, "a\nb中", "组合内联在光标处")
    XCTAssertEqual(model.lineText(1), "b中")
    XCTAssertEqual(model.lineCount, 2)

    model.move(.docStart, extend: false)
    XCTAssertEqual(model.displayText, "a\nb", "移动取消组合后缓存必须反映最新显示文本")
    XCTAssertEqual(model.lineText(0), "a")

    try model.typeText("X")
    XCTAssertEqual(model.displayText, "Xa\nb")
    XCTAssertEqual(model.lineText(0), "Xa")
    XCTAssertEqual(model.lineByteRanges.count, 2)
  }

  /// T-040（ADR-023 v1.2）：bufferId 是 Cmd+S 的保存键，与初始 Buffer 一致。
  func testBufferIdExposesInitialBufferIdentity() {
    let model = EditorModel(buffer: Buffer(BufferId(9)))
    XCTAssertEqual(model.bufferIdValue, 9)
  }
}
