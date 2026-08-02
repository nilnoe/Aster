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

// T-041（ADR-023 v1.3）：快照（Cmd+N 创建，日期+序号）+ 缓冲（自动保存）模型。

#[test]
fn next_snapshot_creates_dir_and_sequenced_files() {
    let dir = temp_dir("next");
    let seq1 = Store::next_snapshot(&dir).unwrap();
    let seq2 = Store::next_snapshot(&dir).unwrap();
    assert_eq!(seq2, seq1 + 1, "序号必须递增");

    let names = daily_file_names(&dir);
    assert_eq!(names.len(), 2, "两次保存 = 两个文件");
    assert!(
        names[0].ends_with("-001.sqlite") && names[1].ends_with("-002.sqlite"),
        "序号必须递增：{names:?}"
    );
}

#[test]
fn next_snapshot_nested_missing_directory_is_created() {
    let base = std::env::temp_dir();
    let dir = base.join(format!(
        "aster-daily-nested-{}-{}",
        std::process::id(),
        COUNTER.fetch_add(1, Ordering::Relaxed)
    ));
    let nested = dir.join("a").join("b");
    assert!(
        Store::next_snapshot(&nested).is_ok(),
        "嵌套缺失目录必须自动创建"
    );
    drop(std::fs::remove_dir_all(&dir));
}

#[test]
fn next_snapshot_seq_jumps_over_gaps() {
    // 手工制造缺号（-001 与 -003），next_snapshot 必须取最大序号 + 1 = -004。
    let dir = temp_dir("gaps");
    // 先生成两个文件得到真实日期前缀，再改名制造缺口。
    let _s1 = Store::next_snapshot(&dir).unwrap();
    let _s2 = Store::next_snapshot(&dir).unwrap();
    let mut names = daily_file_names(&dir);
    names.sort();
    let gap_name = names[0].replace("-001.sqlite", "-003.sqlite");
    std::fs::rename(dir.join(&names[0]), dir.join(&gap_name)).unwrap();
    let seq3 = Store::next_snapshot(&dir).unwrap();
    let final_names = daily_file_names(&dir);
    assert_eq!(seq3, 4, "缺号后下一个必须是最大序号 + 1");
    assert!(
        final_names.iter().any(|n| n.ends_with("-004.sqlite")),
        "缺号后下一个必须是最大序号 + 1：{final_names:?}"
    );
}

#[test]
fn open_snapshot_roundtrip_persists_committed_content() {
    let dir = temp_dir("snapshot-roundtrip");
    let seq = Store::next_snapshot(&dir).unwrap();
    {
        let mut snapshot = Store::open_snapshot(&dir, seq).unwrap();
        snapshot.save_scratch(7, "v2 你好").unwrap();
    }
    let reopened = Store::open_snapshot(&dir, seq).unwrap();
    assert_eq!(
        reopened.load_scratch(7).unwrap().as_deref(),
        Some("v2 你好")
    );
}

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

#[test]
fn open_latest_returns_highest_seq() {
    let dir = temp_dir("latest");
    let seq1 = Store::next_snapshot(&dir).unwrap();
    let seq2 = Store::next_snapshot(&dir).unwrap();
    let _ = seq1;
    let mut s1 = Store::open_snapshot(&dir, seq1).unwrap();
    s1.save_scratch(7, "v1").unwrap();
    let mut s2 = Store::open_snapshot(&dir, seq2).unwrap();
    s2.save_scratch(7, "v2").unwrap();

    let latest = Store::open_latest(&dir).unwrap().expect("当日应有快照");
    assert_eq!(latest.load_scratch(7).unwrap().as_deref(), Some("v2"));
}

#[test]
fn open_latest_no_files_today_returns_none() {
    let dir = temp_dir("none");
    assert!(Store::open_latest(&dir).unwrap().is_none());
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

fn daily_file_names(dir: &std::path::Path) -> Vec<String> {
    let mut names = std::fs::read_dir(dir)
        .unwrap()
        .map(|e| e.unwrap().file_name().into_string().unwrap())
        .filter(|n| n.starts_with("aster-") && n.ends_with(".sqlite"))
        .collect::<Vec<_>>();
    names.sort();
    names
}

#[test]
fn store_open_invalid_directory_fails() {
    let mut p = std::env::temp_dir();
    p.push("aster-store-no-such-dir");
    p.push("db.sqlite");
    let err = Store::open(&p).unwrap_err();
    assert!(matches!(err, StoreError::Sqlite(_)));
}
