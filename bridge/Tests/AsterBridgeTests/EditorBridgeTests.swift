//! Editor 桥接契约测试（T-013，ADR-017）。
//!
//! 验证 Swift → Rust → Swift 的编辑闭环：输入、光标、选区替换、undo/redo、
//! UTF-8 边界删除、方向移动（含 Shift 扩展）。

import XCTest

@testable import AsterBridge

final class EditorBridgeTests: XCTestCase {
  func testEditorTypeAndCursorRoundTrip() throws {
    let editor = editor_new(Buffer(BufferId(10)))
    _ = try editor_type_text(editor, "你好")
    XCTAssertEqual(editor_text(editor).toString(), "你好")
    XCTAssertEqual(editor_selection_head(editor), 6)
    _ = try editor_type_text(editor, "!")
    XCTAssertEqual(editor_text(editor).toString(), "你好!")
    XCTAssertEqual(editor_selection_head(editor), 7)
  }

  func testEditorSelectAllReplaceAndUndoRedo() throws {
    let editor = editor_new(Buffer(BufferId(11)))
    _ = try editor_type_text(editor, "abcdef")
    editor_select_all(editor)
    XCTAssertEqual(editor_selection_start(editor), 0)
    XCTAssertEqual(editor_selection_end(editor), 6)
    _ = try editor_type_text(editor, "X")
    XCTAssertEqual(editor_text(editor).toString(), "X")
    XCTAssertTrue(try editor_undo(editor))
    XCTAssertEqual(editor_text(editor).toString(), "abcdef")
    XCTAssertTrue(try editor_redo(editor))
    XCTAssertEqual(editor_text(editor).toString(), "X")
  }

  func testEditorMovementRespectsUTF8AndExtend() throws {
    let editor = editor_new(Buffer(BufferId(12)))
    _ = try editor_type_text(editor, "a你好b")
    editor_move_doc_start(editor, false)
    editor_move_right(editor, false)
    editor_move_right(editor, false)
    XCTAssertEqual(editor_selection_head(editor), 4)
    editor_move_doc_end(editor, false)
    XCTAssertEqual(editor_selection_head(editor), 8)
    editor_move_left(editor, true)  // Shift+Left 扩展选区
    XCTAssertEqual(editor_selection_start(editor), 7)
    XCTAssertEqual(editor_selection_end(editor), 8)
  }

  func testEditorDeleteBackwardCJK() throws {
    let editor = editor_new(Buffer(BufferId(13)))
    _ = try editor_type_text(editor, "你好")
    editor_move_doc_end(editor, false)
    _ = try editor_delete_backward(editor)
    XCTAssertEqual(editor_text(editor).toString(), "你")
    XCTAssertEqual(editor_selection_head(editor), 3)
  }

  func testEditorSetSelectionForIMEReplacement() throws {
    let editor = editor_new(Buffer(BufferId(14)))
    _ = try editor_type_text(editor, "你好abc")
    // 替换 [3, 7)（"好a" 的 UTF-8 区间）→ 等价于 IME 替换区间。
    editor_set_selection(editor, 3, 7)
    _ = try editor_type_text(editor, "X")
    XCTAssertEqual(editor_text(editor).toString(), "你Xbc")
    XCTAssertEqual(editor_selection_head(editor), 4)
  }
}
