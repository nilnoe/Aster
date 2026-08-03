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

// T-043（ADR-013 v1.1）：崩溃恢复原语——clean_exit 哨兵 + 缓冲文档枚举。

#[test]
fn clean_exit_marker_defaults_false_and_roundtrips() {
    let mut store = Store::in_memory().unwrap();
    // 缺省 = 异常退出（哨兵缺失即视为崩溃，ADR-013 v1.1）。
    assert!(!store.is_clean_exit().unwrap(), "初始必须是异常退出语义");
    store.set_clean_exit(true).unwrap();
    assert!(store.is_clean_exit().unwrap());
    store.set_clean_exit(false).unwrap();
    assert!(!store.is_clean_exit().unwrap(), "启动时清哨兵后不得为干净");
}

#[test]
fn list_scratch_enumerates_buffered_documents() {
    let mut store = Store::in_memory().unwrap();
    assert!(store.list_scratch().unwrap().is_empty(), "无缓冲文档");
    store.save_scratch(3, "doc 3").unwrap();
    store.save_scratch(1, "doc 1").unwrap();
    store.save_scratch(2, "doc 2").unwrap();
    // 按 id 升序返回（恢复时取最新 = 最大 id）。
    assert_eq!(
        store.list_scratch().unwrap(),
        vec![
            (1, "doc 1".to_string()),
            (2, "doc 2".to_string()),
            (3, "doc 3".to_string())
        ]
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

// T-056（2026-08-03）：存储损坏与迁移——损坏缓冲启动不崩、旧 schema 迁移、
// 只读目录、多实例并发同一 buffer.sqlite。

#[test]
fn corrupt_buffer_file_open_returns_error_not_panic() {
    let path = temp_db();
    std::fs::write(&path, "这不是 SQLite 数据库文件".as_bytes()).unwrap();
    let err = Store::open(&path).unwrap_err();
    assert!(
        matches!(err, StoreError::Sqlite(_)),
        "乱字节数据库必须返回 Sqlite 错误而非 panic（启动不崩底线）"
    );
}

#[test]
fn truncated_sqlite_header_open_returns_error_not_panic() {
    let path = temp_db();
    // 合法 SQLite 文件头 + 截断体（模拟写入中途崩溃的残缺文件）。
    let mut bytes = b"SQLite format 3\0".to_vec();
    bytes.extend_from_slice(&[0u8; 64]);
    std::fs::write(&path, &bytes).unwrap();
    let err = Store::open(&path).unwrap_err();
    assert!(
        matches!(err, StoreError::Sqlite(_)),
        "截断文件必须返回 Sqlite 错误而非 panic"
    );
}

#[test]
fn old_schema_user_version_zero_migrates_to_v1() {
    use rusqlite::Connection;
    let path = temp_db();
    {
        // 模拟旧版本数据库：user_version=0 + 旧表（无 meta 表——哨兵表是后加
        // 的，ADR-013 v1.1）。
        let conn = Connection::open(&path).unwrap();
        conn.execute_batch(
            "CREATE TABLE scratch (id INTEGER PRIMARY KEY, content TEXT NOT NULL);
             CREATE TABLE session (position INTEGER PRIMARY KEY, id INTEGER NOT NULL, path TEXT);
             PRAGMA user_version = 0;",
        )
        .unwrap();
    }

    let mut store = Store::open(&path).unwrap();
    store.save_scratch(7, "迁移后可写").unwrap();
    assert_eq!(
        store.load_scratch(7).unwrap().as_deref(),
        Some("迁移后可写"),
        "v0 schema 打开后必须补齐表并可读写"
    );
    let conn = Connection::open(&path).unwrap();
    let version: i64 = conn
        .query_row("PRAGMA user_version", [], |r| r.get(0))
        .unwrap();
    assert_eq!(version, 1, "迁移锚点必须推进到 v1");
}

#[test]
fn readonly_directory_open_buffer_fails_cleanly() {
    use std::os::unix::fs::PermissionsExt;
    let dir = temp_dir("readonly");
    std::fs::create_dir_all(&dir).unwrap();
    std::fs::set_permissions(&dir, std::fs::Permissions::from_mode(0o555)).unwrap();
    let is_root = std::process::Command::new("id")
        .arg("-u")
        .output()
        .map(|o| String::from_utf8_lossy(&o.stdout).trim() == "0")
        .unwrap_or(false);
    if !is_root {
        // root 不受权限位约束（CI 与本地均非 root；本机 euid=501 实测），
        // 非 root 才断言失败契约。
        let err = Store::open_buffer(&dir).unwrap_err();
        assert!(
            matches!(err, StoreError::Sqlite(_)),
            "只读目录必须返回错误而非 panic"
        );
    }
    std::fs::set_permissions(&dir, std::fs::Permissions::from_mode(0o755)).unwrap();
}

#[test]
fn two_connections_same_buffer_share_committed_rows() {
    // 多实例（两个连接）打开同一 buffer.sqlite：SQLite 文件锁串行化写入，
    // 已提交行跨连接可见（App 单线程主 actor 顺序操作，ADR-015）。
    let dir = temp_dir("multi");
    let mut a = Store::open_buffer(&dir).unwrap();
    let mut b = Store::open_buffer(&dir).unwrap();

    a.save_scratch(1, "A 写入").unwrap();
    assert_eq!(
        b.load_scratch(1).unwrap().as_deref(),
        Some("A 写入"),
        "B 必须看到 A 已提交的行"
    );
    b.save_scratch(2, "B 写入").unwrap();
    assert_eq!(a.load_scratch(2).unwrap().as_deref(), Some("B 写入"));
    a.delete_scratch(1).unwrap();
    assert_eq!(b.load_scratch(1).unwrap(), None, "删除跨连接可见");
}
