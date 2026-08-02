//! Editor 编辑会话契约测试（T-013，ADR-017）。
//!
//! 覆盖：光标输入、替换选区、删除回退（UTF-8 边界）、移动（字符/行/文档）、
//! Shift 扩展、undo/redo 与选区裁剪。断言行为而非实现（docs/testing.md）。

use aster_core::{Buffer, BufferId, Editor, Movement};

fn editor_with(text: &str) -> Editor {
    let mut buffer = Buffer::new(BufferId::new(1));
    buffer.insert(0, text).unwrap();
    Editor::new(buffer)
}

#[test]
fn editor_type_inserts_and_collapses_cursor() {
    let mut editor = editor_with("");
    editor.type_text("你好").unwrap();
    assert_eq!(editor.text(), "你好");
    assert_eq!(editor.selection().head(), 6);
    editor.type_text("!").unwrap();
    assert_eq!(editor.text(), "你好!");
    assert_eq!(editor.selection().head(), 7);
    // 相邻 Insert 合并（ADR-008）：一次 undo 回到空文本。
    assert!(editor.undo().unwrap());
    assert_eq!(editor.text(), "");
    assert!(editor.redo().unwrap());
    assert_eq!(editor.text(), "你好!");
}

#[test]
fn editor_type_replaces_selection_in_one_undo() {
    let mut editor = editor_with("abcdef");
    editor.select_all();
    editor.type_text("X").unwrap();
    assert_eq!(editor.text(), "X");
    assert!(editor.undo().unwrap());
    assert_eq!(editor.text(), "abcdef");
    assert_eq!(editor.selection().head(), 0);
}

#[test]
fn editor_delete_backward_removes_char_before_cursor() {
    let mut editor = editor_with("你好");
    editor.move_cursor(Movement::DocEnd, false);
    // 光标在末尾（字节 6）；删掉最后一个 CJK 字符。
    let op = editor.delete_backward().unwrap();
    assert!(op.is_some());
    assert_eq!(editor.text(), "你");
    assert_eq!(editor.selection().head(), 3);
    assert!(editor.undo().unwrap());
    assert_eq!(editor.text(), "你好");
}

#[test]
fn editor_delete_backward_deletes_selection() {
    let mut editor = editor_with("abcdef");
    editor.move_cursor(Movement::Right, false);
    editor.move_cursor(Movement::DocStart, true);
    // selection = (0, 1)；删掉选区。
    editor.delete_backward().unwrap();
    assert_eq!(editor.text(), "bcdef");
    assert_eq!(editor.selection().head(), 0);
}

#[test]
fn editor_move_left_right_respects_utf8_boundaries() {
    let mut editor = editor_with("a你好b");
    editor.move_cursor(Movement::Right, false);
    assert_eq!(editor.selection().head(), 1);
    editor.move_cursor(Movement::Right, false);
    assert_eq!(editor.selection().head(), 4);
    editor.move_cursor(Movement::Right, false);
    assert_eq!(editor.selection().head(), 7);
    editor.move_cursor(Movement::Right, false);
    assert_eq!(editor.selection().head(), 8); // 文档末尾钳制
    editor.move_cursor(Movement::Right, false);
    assert_eq!(editor.selection().head(), 8);
    editor.move_cursor(Movement::Left, false);
    assert_eq!(editor.selection().head(), 7);
    editor.move_cursor(Movement::Left, false);
    assert_eq!(editor.selection().head(), 4);
    editor.move_cursor(Movement::Left, false);
    assert_eq!(editor.selection().head(), 1);
}

#[test]
fn editor_move_line_and_document_boundaries() {
    let mut editor = editor_with("ab\ncd\ne");
    editor.move_cursor(Movement::DocEnd, false);
    assert_eq!(editor.selection().head(), 7);
    editor.move_cursor(Movement::LineStart, false);
    assert_eq!(editor.selection().head(), 6);
    editor.move_cursor(Movement::LineEnd, false);
    assert_eq!(editor.selection().head(), 7);
    editor.move_cursor(Movement::DocStart, false);
    assert_eq!(editor.selection().head(), 0);
}

#[test]
fn editor_move_up_down_keeps_byte_column() {
    let mut editor = editor_with("ab\ncd\ne");
    // 光标 2（第 0 行末尾，列 2）→ 下 → 第 1 行末尾 5；上 → 回 2。
    editor.move_cursor(Movement::Right, false);
    editor.move_cursor(Movement::Right, false);
    editor.move_cursor(Movement::Down, false);
    assert_eq!(editor.selection().head(), 5);
    editor.move_cursor(Movement::Up, false);
    assert_eq!(editor.selection().head(), 2);
    // 光标 7（"e" 后，第 2 行列 1）→ 上 → 第 1 行列 1 = 4；再上 → 第 0 行列 1 = 1。
    editor.move_cursor(Movement::DocEnd, false);
    editor.move_cursor(Movement::Up, false);
    assert_eq!(editor.selection().head(), 4);
    editor.move_cursor(Movement::Up, false);
    assert_eq!(editor.selection().head(), 1);
}

#[test]
fn editor_move_extend_selects_and_collapse_resets() {
    let mut editor = editor_with("abcde");
    editor.move_cursor(Movement::Right, true);
    editor.move_cursor(Movement::Right, true);
    let sel = editor.selection();
    assert_eq!((sel.start(), sel.end()), (0, 2));
    editor.move_cursor(Movement::Right, false);
    let sel = editor.selection();
    assert_eq!((sel.start(), sel.end(), sel.head()), (3, 3, 3));
    assert!(sel.collapsed());
}

#[test]
fn editor_movement_clamps_at_edges() {
    let mut editor = editor_with("ab");
    editor.move_cursor(Movement::Left, false);
    assert_eq!(editor.selection().head(), 0);
    editor.move_cursor(Movement::Up, false);
    assert_eq!(editor.selection().head(), 0);
    editor.move_cursor(Movement::DocStart, false);
    assert_eq!(editor.selection().head(), 0);
    editor.move_cursor(Movement::Right, false);
    editor.move_cursor(Movement::Right, false);
    editor.move_cursor(Movement::Right, false);
    assert_eq!(editor.selection().head(), 2);
    editor.move_cursor(Movement::Down, false);
    assert_eq!(editor.selection().head(), 2);
}

#[test]
fn editor_undo_redo_restores_cursor() {
    let mut editor = editor_with("abcdef");
    editor.move_cursor(Movement::DocEnd, false);
    editor.delete_backward().unwrap();
    assert_eq!(editor.text(), "abcde");
    assert_eq!(editor.selection().head(), 5);
    assert!(editor.undo().unwrap());
    assert_eq!(editor.text(), "abcdef");
    assert_eq!(editor.selection().head(), 5);
    assert!(editor.redo().unwrap());
    assert_eq!(editor.text(), "abcde");
    assert_eq!(editor.selection().head(), 5);
}

#[test]
fn editor_set_selection_clamps_and_fixes_boundaries() {
    let mut editor = editor_with("你好abc");
    // 越界 + 非字符边界：anchor 钳到 len（9），head 钳到 0（字节 2 在"你"内部）。
    editor.set_selection(99, 2);
    let sel = editor.selection();
    assert_eq!((sel.start(), sel.end()), (0, 9));
    // 字节 1 在"你"内部 → 0；字节 5 在"好"内部 → 3。
    editor.set_selection(1, 5);
    let sel = editor.selection();
    assert_eq!((sel.anchor(), sel.head()), (0, 3));
    assert_eq!((sel.start(), sel.end()), (0, 3));
}

/// 信息性基准（无断言）：T-013 编辑热路径基线，写入 docs/benchmarks.md；
/// 正式基准在 T-020 用 criterion 建立。
#[test]
fn editor_ops_baseline() {
    let mut editor = editor_with("");
    let start = std::time::Instant::now();
    for _ in 0..10_000 {
        editor.type_text("a").unwrap();
    }
    for _ in 0..10_000 {
        editor.delete_backward().unwrap();
    }
    println!(
        "T-013 baseline: 10k type + 10k delete = {:?}",
        start.elapsed()
    );
}
