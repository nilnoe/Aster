//! Selection 公共 API 行为契约测试（ADR-007）。
//!
//! 决策依据：测试断言行为而非实现；公共 API 契约必须覆盖（docs/testing.md）。

use aster_core::Selection;

#[test]
fn new_creates_collapsed_selection() {
    let s = Selection::new(5);
    assert_eq!(s.anchor(), 5);
    assert_eq!(s.head(), 5);
    assert!(s.collapsed());
}

#[test]
fn new_range_preserves_anchor_and_head() {
    let s = Selection::new_range(2, 7);
    assert_eq!(s.anchor(), 2);
    assert_eq!(s.head(), 7);
    assert!(!s.collapsed());
}

#[test]
fn start_and_end_normalize_forward_selection() {
    let s = Selection::new_range(2, 7);
    assert_eq!(s.start(), 2);
    assert_eq!(s.end(), 7);
}

#[test]
fn start_and_end_normalize_reversed_selection() {
    let s = Selection::new_range(7, 2);
    assert_eq!(s.start(), 2);
    assert_eq!(s.end(), 7);
    assert_eq!(s.anchor(), 7);
    assert_eq!(s.head(), 2);
}

#[test]
fn set_head_moves_cursor_keeps_anchor() {
    let mut s = Selection::new(3);
    s.set_head(9);
    assert_eq!(s.anchor(), 3);
    assert_eq!(s.head(), 9);
    assert!(!s.collapsed());
}

#[test]
fn collapse_clears_selection() {
    let mut s = Selection::new_range(2, 7);
    s.collapse(4);
    assert_eq!(s.anchor(), 4);
    assert_eq!(s.head(), 4);
    assert!(s.collapsed());
}

#[test]
fn selection_is_a_copy_value_type() {
    // 决策依据：Selection 是纯值类型；副本修改不影响原值（无共享状态）。
    let s = Selection::new(1);
    let mut t = s;
    t.set_head(6);
    assert_eq!(s.head(), 1);
    assert_eq!(t.head(), 6);
}
