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

// T-040（ADR-023 v1.2）：按日期 + 序号轮转——单日内多个快照文件，目录自动创建。

#[test]
fn open_next_creates_dir_and_sequenced_files() {
    let dir = temp_dir("next");
    let _s1 = Store::open_next(&dir).unwrap();
    let _s2 = Store::open_next(&dir).unwrap();

    let names = daily_file_names(&dir);
    assert_eq!(names.len(), 2, "两次保存 = 两个文件");
    assert!(
        names[0].ends_with("-001.sqlite") && names[1].ends_with("-002.sqlite"),
        "序号必须递增：{names:?}"
    );
}

#[test]
fn open_next_nested_missing_directory_is_created() {
    let base = std::env::temp_dir();
    let dir = base.join(format!(
        "aster-daily-nested-{}-{}",
        std::process::id(),
        COUNTER.fetch_add(1, Ordering::Relaxed)
    ));
    let nested = dir.join("a").join("b");
    assert!(
        Store::open_next(&nested).is_ok(),
        "嵌套缺失目录必须自动创建"
    );
    drop(std::fs::remove_dir_all(&dir));
}

#[test]
fn open_next_seq_jumps_over_gaps() {
    // 手工制造缺号（-001 与 -003），open_next 必须取最大序号 + 1 = -004。
    let dir = temp_dir("gaps");
    // 先生成两个文件得到真实日期前缀，再改名制造缺口。
    let _s1 = Store::open_next(&dir).unwrap();
    let _s2 = Store::open_next(&dir).unwrap();
    let mut names = daily_file_names(&dir);
    names.sort();
    let gap_name = names[0].replace("-001.sqlite", "-003.sqlite");
    std::fs::rename(dir.join(&names[0]), dir.join(&gap_name)).unwrap();
    let _s3 = Store::open_next(&dir).unwrap();
    let final_names = daily_file_names(&dir);
    assert!(
        final_names.iter().any(|n| n.ends_with("-004.sqlite")),
        "缺号后下一个必须是最大序号 + 1：{final_names:?}"
    );
}

#[test]
fn open_latest_returns_highest_seq_and_roundtrip() {
    let dir = temp_dir("daily-roundtrip");
    {
        let mut first = Store::open_next(&dir).unwrap();
        first.save_scratch(7, "v1").unwrap();
        let mut second = Store::open_next(&dir).unwrap();
        second.save_scratch(7, "v2 你好").unwrap();
    }
    // open_latest 必须返回最高序号文件（v2）。
    let latest = Store::open_latest(&dir).unwrap().expect("当日应有快照");
    assert_eq!(latest.load_scratch(7).unwrap().as_deref(), Some("v2 你好"));
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
