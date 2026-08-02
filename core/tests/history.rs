//! History 公共 API 行为契约测试（ADR-008）。
//!
//! 决策依据：测试断言行为而非实现（docs/testing.md）；公共 API 契约必须覆盖。

use aster_core::{Buffer, BufferId, EditOp, History};

fn buffer_with(text: &str) -> Buffer {
    let mut b = Buffer::new(BufferId::new(1));
    if !text.is_empty() {
        b.insert(0, text).unwrap();
    }
    b
}

/// 模拟调用方流程（T-007 Command 将封装）：先应用到 Buffer，再记录。
fn apply_and_record(b: &mut Buffer, h: &mut History, op: EditOp) {
    match &op {
        EditOp::Insert { at, text } => {
            b.insert(*at, text).unwrap();
        }
        EditOp::Delete { at, text } => {
            b.delete(*at, *at + text.len()).unwrap();
        }
    }
    h.record(op);
}

#[test]
fn undo_insert_restores_previous_text() {
    let mut b = buffer_with("");
    let mut h = History::new();
    apply_and_record(
        &mut b,
        &mut h,
        EditOp::Insert {
            at: 0,
            text: "ab".into(),
        },
    );
    assert!(h.undo(&mut b).unwrap().is_some());
    assert_eq!(b.text(), "");
}

#[test]
fn undo_reverses_multiple_ops_lifo() {
    let mut b = buffer_with("");
    let mut h = History::new();
    apply_and_record(
        &mut b,
        &mut h,
        EditOp::Insert {
            at: 0,
            text: "a".into(),
        },
    );
    // 前插到 0：prev.at + prev.text.len() = 1 ≠ 0，不触发合并，LIFO 语义独立可验证。
    apply_and_record(
        &mut b,
        &mut h,
        EditOp::Insert {
            at: 0,
            text: "b".into(),
        },
    );
    assert_eq!(b.text(), "ba");
    h.undo(&mut b).unwrap();
    assert_eq!(b.text(), "a");
    h.undo(&mut b).unwrap();
    assert_eq!(b.text(), "");
}

#[test]
fn redo_reapplies_after_undo() {
    let mut b = buffer_with("");
    let mut h = History::new();
    apply_and_record(
        &mut b,
        &mut h,
        EditOp::Insert {
            at: 0,
            text: "ab".into(),
        },
    );
    h.undo(&mut b).unwrap();
    assert_eq!(b.text(), "");
    assert!(h.redo(&mut b).unwrap().is_some());
    assert_eq!(b.text(), "ab");
}

#[test]
fn redo_is_cleared_by_new_edit() {
    let mut b = buffer_with("");
    let mut h = History::new();
    apply_and_record(
        &mut b,
        &mut h,
        EditOp::Insert {
            at: 0,
            text: "a".into(),
        },
    );
    h.undo(&mut b).unwrap();
    assert!(h.can_redo());
    apply_and_record(
        &mut b,
        &mut h,
        EditOp::Insert {
            at: 0,
            text: "x".into(),
        },
    );
    assert!(!h.can_redo());
    assert!(h.redo(&mut b).unwrap().is_none());
}

#[test]
fn can_undo_can_redo_flags() {
    let mut b = buffer_with("");
    let mut h = History::default();
    assert!(!h.can_undo());
    assert!(!h.can_redo());
    apply_and_record(
        &mut b,
        &mut h,
        EditOp::Insert {
            at: 0,
            text: "a".into(),
        },
    );
    assert!(h.can_undo());
}

#[test]
fn undo_empty_history_returns_none() {
    let mut b = buffer_with("abc");
    let mut h = History::new();
    assert!(h.undo(&mut b).unwrap().is_none());
    assert_eq!(b.text(), "abc");
}

#[test]
fn undo_delete_restores_deleted_text() {
    let mut b = buffer_with("ab");
    let mut h = History::new();
    apply_and_record(
        &mut b,
        &mut h,
        EditOp::Delete {
            at: 0,
            text: "ab".into(),
        },
    );
    assert_eq!(b.text(), "");
    h.undo(&mut b).unwrap();
    assert_eq!(b.text(), "ab");
}

#[test]
fn merge_contiguous_inserts_undo_once() {
    let mut b = buffer_with("");
    let mut h = History::new();
    apply_and_record(
        &mut b,
        &mut h,
        EditOp::Insert {
            at: 0,
            text: "a".into(),
        },
    );
    apply_and_record(
        &mut b,
        &mut h,
        EditOp::Insert {
            at: 1,
            text: "b".into(),
        },
    );
    apply_and_record(
        &mut b,
        &mut h,
        EditOp::Insert {
            at: 2,
            text: "c".into(),
        },
    );
    assert_eq!(b.text(), "abc");
    h.undo(&mut b).unwrap();
    assert_eq!(b.text(), "");
    assert!(!h.can_undo());
}

#[test]
fn non_contiguous_inserts_are_not_merged() {
    let mut b = buffer_with("");
    let mut h = History::new();
    apply_and_record(
        &mut b,
        &mut h,
        EditOp::Insert {
            at: 0,
            text: "ab".into(),
        },
    );
    // 前插到 0：prev.at + prev.text.len() = 2 ≠ 0，不合并。
    apply_and_record(
        &mut b,
        &mut h,
        EditOp::Insert {
            at: 0,
            text: "X".into(),
        },
    );
    assert_eq!(b.text(), "Xab");
    h.undo(&mut b).unwrap();
    assert_eq!(b.text(), "ab");
    assert!(h.can_undo());
}

#[test]
fn undo_failure_keeps_stack_and_buffer() {
    let mut b = buffer_with("");
    let mut h = History::new();
    // 记录一个从未应用到 Buffer 的 op：状态不一致。
    h.record(EditOp::Insert {
        at: 0,
        text: "ab".into(),
    });
    assert!(h.undo(&mut b).is_err());
    assert!(h.can_undo());
    assert_eq!(b.text(), "");
}

#[test]
fn undo_redo_undo_roundtrip() {
    let mut b = buffer_with("");
    let mut h = History::new();
    apply_and_record(
        &mut b,
        &mut h,
        EditOp::Insert {
            at: 0,
            text: "ab".into(),
        },
    );
    h.undo(&mut b).unwrap();
    h.redo(&mut b).unwrap();
    assert_eq!(b.text(), "ab");
    h.undo(&mut b).unwrap();
    assert_eq!(b.text(), "");
}
