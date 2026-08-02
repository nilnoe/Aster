//! Buffer 公共 API 行为契约测试（ADR-005）。
//!
//! 决策依据：测试断言行为而非实现（docs/testing.md）；Public API 契约必须覆盖。

use aster_core::{Buffer, BufferError, BufferId};

fn buf(id: u64) -> Buffer {
    Buffer::new(BufferId::new(id))
}

#[test]
fn new_buffer_is_empty() {
    let b = buf(1);
    assert!(b.is_empty());
    assert_eq!(b.len(), 0);
    assert_eq!(b.text(), "");
}

#[test]
fn buffer_keeps_its_id() {
    let b = buf(42);
    assert_eq!(b.id(), BufferId::new(42));
    assert_eq!(b.id().as_u64(), 42);
}

#[test]
fn insert_at_zero_places_text_at_start() {
    let mut b = buf(1);
    assert_eq!(b.insert(0, "abc").unwrap(), 3);
    assert_eq!(b.text(), "abc");
}

#[test]
fn insert_at_end_appends() {
    let mut b = buf(1);
    b.insert(0, "ab").unwrap();
    assert_eq!(b.insert(2, "cd").unwrap(), 4);
    assert_eq!(b.text(), "abcd");
}

#[test]
fn insert_mid_text() {
    let mut b = buf(1);
    b.insert(0, "ac").unwrap();
    b.insert(1, "b").unwrap();
    assert_eq!(b.text(), "abc");
}

#[test]
fn insert_beyond_end_rejected() {
    let mut b = buf(1);
    b.insert(0, "ab").unwrap();
    assert_eq!(
        b.insert(3, "x"),
        Err(BufferError::RangeOutOfBounds {
            start: 3,
            end: 3,
            len: 2
        })
    );
}

#[test]
fn insert_at_non_char_boundary_rejected() {
    let mut b = buf(1);
    b.insert(0, "你好").unwrap();
    // 1 位于“你”（3 字节）的 UTF-8 编码中间，不是字符边界。
    assert_eq!(b.insert(1, "x"), Err(BufferError::InvalidCharBoundary(1)));
}

#[test]
fn delete_range_removes_text() {
    let mut b = buf(1);
    b.insert(0, "hello").unwrap();
    assert_eq!(b.delete(1, 3).unwrap(), 3);
    assert_eq!(b.text(), "hlo");
}

#[test]
fn delete_whole_text_empties_buffer() {
    let mut b = buf(1);
    b.insert(0, "abc").unwrap();
    assert_eq!(b.delete(0, 3).unwrap(), 0);
    assert!(b.is_empty());
}

#[test]
fn delete_reversed_range_rejected() {
    let mut b = buf(1);
    b.insert(0, "abc").unwrap();
    assert_eq!(
        b.delete(2, 1),
        Err(BufferError::RangeOutOfBounds {
            start: 2,
            end: 1,
            len: 3
        })
    );
}

#[test]
fn delete_beyond_end_rejected() {
    let mut b = buf(1);
    b.insert(0, "abc").unwrap();
    assert_eq!(
        b.delete(1, 4),
        Err(BufferError::RangeOutOfBounds {
            start: 1,
            end: 4,
            len: 3
        })
    );
}

#[test]
fn delete_at_non_char_boundary_rejected() {
    let mut b = buf(1);
    b.insert(0, "你好世界").unwrap();
    assert_eq!(b.delete(1, 6), Err(BufferError::InvalidCharBoundary(1)));
}

#[test]
fn utf8_content_roundtrips() {
    let mut b = buf(1);
    b.insert(0, "你好，世界 🌍").unwrap();
    assert_eq!(b.text(), "你好，世界 🌍");
    // “你好，”占 9 字节；删除后剩余“世界 🌍”共 11 字节。
    assert_eq!(b.delete(0, 9).unwrap(), 11);
    assert_eq!(b.text(), "世界 🌍");
}
