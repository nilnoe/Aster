//! Layout 公共 API 行为契约测试（ADR-009）。
//!
//! 决策依据：测试断言行为而非实现（docs/testing.md）；公共 API 契约必须覆盖。
//! 字节偏移语义与 Buffer 一致（ADR-005）。

use aster_core::Layout;

fn layout_of(text: &str) -> Layout {
    Layout::build(text)
}

#[test]
fn empty_text_has_one_empty_line() {
    let l = layout_of("");
    assert_eq!(l.line_count(), 1);
    assert_eq!(l.line_range(0), Some(0..0));
    assert_eq!(l.line_at(0), Some(0));
}

#[test]
fn single_line_without_newline() {
    let l = layout_of("abc");
    assert_eq!(l.line_count(), 1);
    assert_eq!(l.line_range(0), Some(0..3));
    assert_eq!(l.line_at(0), Some(0));
    assert_eq!(l.line_at(3), Some(0));
}

#[test]
fn two_lines_split_by_newline() {
    let l = layout_of("a\nb");
    assert_eq!(l.line_count(), 2);
    assert_eq!(l.line_range(0), Some(0..1));
    assert_eq!(l.line_range(1), Some(2..3));
    assert_eq!(l.line_at(0), Some(0));
    assert_eq!(l.line_at(1), Some(0));
    assert_eq!(l.line_at(2), Some(1));
}

#[test]
fn line_range_excludes_newline() {
    let l = layout_of("a\nb");
    assert_eq!(l.line_range(0), Some(0..1));
}

#[test]
fn trailing_newline_creates_empty_last_line() {
    let l = layout_of("a\nb\n");
    assert_eq!(l.line_count(), 3);
    assert_eq!(l.line_range(0), Some(0..1));
    assert_eq!(l.line_range(1), Some(2..3));
    assert_eq!(l.line_range(2), Some(4..4));
}

#[test]
fn consecutive_newlines_are_empty_lines() {
    let l = layout_of("a\n\nb");
    assert_eq!(l.line_count(), 3);
    assert_eq!(l.line_range(1), Some(2..2));
    assert_eq!(l.line_range(2), Some(3..4));
}

#[test]
fn unicode_lines_use_byte_offsets() {
    // “你好”= 6 字节，\n 在 6，“世界”= 6 字节（7..13）。
    let l = layout_of("你好\n世界");
    assert_eq!(l.line_count(), 2);
    assert_eq!(l.line_range(0), Some(0..6));
    assert_eq!(l.line_range(1), Some(7..13));
    assert_eq!(l.line_at(3), Some(0));
    assert_eq!(l.line_at(7), Some(1));
}

#[test]
fn offset_inside_newline_belongs_to_previous_line() {
    let l = layout_of("a\nb");
    assert_eq!(l.line_at(1), Some(0));
}

#[test]
fn line_at_beyond_text_returns_none() {
    let l = layout_of("abc");
    assert_eq!(l.line_at(4), None);
}

#[test]
fn line_range_out_of_bounds_returns_none() {
    let l = layout_of("a\nb");
    assert_eq!(l.line_range(2), None);
    assert_eq!(l.line_range(99), None);
}
