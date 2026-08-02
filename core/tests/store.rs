//! Store 公共契约测试（ADR-013）。
//!
//! 策略：公共契约走集成测试；文件持久化用系统临时目录的唯一文件
//! （与其他集成测试相同的 temp 模式）。

use std::path::PathBuf;
use std::sync::atomic::{AtomicU64, Ordering};

use aster_core::{SessionDocument, Store, StoreError};

static COUNTER: AtomicU64 = AtomicU64::new(0);

fn temp_db() -> PathBuf {
    let mut p = std::env::temp_dir();
    p.push(format!(
        "aster-store-{}-{}.sqlite",
        std::process::id(),
        COUNTER.fetch_add(1, Ordering::Relaxed)
    ));
    p
}

#[test]
fn store_scratch_save_then_load_roundtrip() {
    let mut store = Store::in_memory().unwrap();
    store.save_scratch(1, "你好，世界").unwrap();
    assert_eq!(
        store.load_scratch(1).unwrap().as_deref(),
        Some("你好，世界")
    );
}

#[test]
fn store_scratch_upsert_overwrites() {
    let mut store = Store::in_memory().unwrap();
    store.save_scratch(1, "first").unwrap();
    store.save_scratch(1, "second").unwrap();
    assert_eq!(store.load_scratch(1).unwrap().as_deref(), Some("second"));
}

#[test]
fn store_scratch_load_missing_returns_none() {
    let store = Store::in_memory().unwrap();
    assert_eq!(store.load_scratch(99).unwrap(), None);
}

#[test]
fn store_scratch_delete_removes_and_reports() {
    let mut store = Store::in_memory().unwrap();
    store.save_scratch(1, "x").unwrap();
    assert!(store.delete_scratch(1).unwrap());
    assert_eq!(store.load_scratch(1).unwrap(), None);
    // 已删除的 id 再次删除为幂等 false（ADR-013）。
    assert!(!store.delete_scratch(1).unwrap());
}

#[test]
fn store_session_roundtrip_preserves_order_and_kind() {
    let mut store = Store::in_memory().unwrap();
    let docs = vec![
        SessionDocument { id: 1, path: None },
        SessionDocument {
            id: 2,
            path: Some("/tmp/a.txt".to_string()),
        },
        SessionDocument { id: 3, path: None },
    ];
    store.save_session(&docs).unwrap();
    assert_eq!(store.load_session().unwrap(), docs);
}

#[test]
fn store_session_save_replaces_previous() {
    let mut store = Store::in_memory().unwrap();
    store
        .save_session(&[SessionDocument { id: 1, path: None }])
        .unwrap();
    store
        .save_session(&[SessionDocument { id: 2, path: None }])
        .unwrap();
    assert_eq!(
        store.load_session().unwrap(),
        vec![SessionDocument { id: 2, path: None }]
    );
}

#[test]
fn store_empty_session_roundtrip() {
    let mut store = Store::in_memory().unwrap();
    store.save_session(&[]).unwrap();
    assert_eq!(store.load_session().unwrap(), Vec::<SessionDocument>::new());
}

#[test]
fn store_file_persists_across_reopen() {
    let path = temp_db();
    {
        let mut store = Store::open(&path).unwrap();
        store.save_scratch(7, "persisted").unwrap();
        store
            .save_session(&[SessionDocument { id: 7, path: None }])
            .unwrap();
    }
    let store = Store::open(&path).unwrap();
    assert_eq!(store.load_scratch(7).unwrap().as_deref(), Some("persisted"));
    assert_eq!(
        store.load_session().unwrap(),
        vec![SessionDocument { id: 7, path: None }]
    );
}

// T-042（ADR-023 v1.4）：Store 只保留 SQLite 缓冲（快照纯文本移入 snapshot 模块）。

#[test]
fn open_buffer_creates_buffer_file_and_roundtrip() {
    let dir = temp_dir("buffer");
    {
        let mut buffer = Store::open_buffer(&dir).unwrap();
        buffer.save_scratch(7, "自动保存内容").unwrap();
    }
    // 缓冲文件名固定 buffer.sqlite（崩溃保护工作区）。
    assert!(dir.join("buffer.sqlite").exists());
    let reopened = Store::open_buffer(&dir).unwrap();
    assert_eq!(
        reopened.load_scratch(7).unwrap().as_deref(),
        Some("自动保存内容")
    );
}

fn temp_dir(label: &str) -> std::path::PathBuf {
    let dir = std::env::temp_dir().join(format!(
        "aster-store-{}-{}-{}",
        label,
        std::process::id(),
        COUNTER.fetch_add(1, Ordering::Relaxed)
    ));
    // 清理历史残留，保证 read_dir 断言只看到本次文件。
    let _ = std::fs::remove_dir_all(&dir);
    dir
}

#[test]
fn store_open_invalid_directory_fails() {
    let mut p = std::env::temp_dir();
    p.push("aster-store-no-such-dir");
    p.push("db.sqlite");
    let err = Store::open(&p).unwrap_err();
    assert!(matches!(err, StoreError::Sqlite(_)));
}
