//! DocumentManager 公共 API 行为契约测试（ADR-001）。
//!
//! 决策依据：测试断言行为而非实现（docs/testing.md）；公共 API 契约必须覆盖。
//! 磁盘内容的验证在单元测试中完成（内容访问是 pub(crate) 内部通道，不属于公共 API）。

use std::path::PathBuf;
use std::sync::atomic::{AtomicU64, Ordering};

use aster_core::{BufferId, DocumentManager, DocumentManagerError, DocumentSource};

static COUNTER: AtomicU64 = AtomicU64::new(0);

fn temp_file(content: &str) -> PathBuf {
    let mut p = std::env::temp_dir();
    p.push(format!(
        "aster-dm-test-{}-{}.txt",
        std::process::id(),
        COUNTER.fetch_add(1, Ordering::Relaxed)
    ));
    std::fs::write(&p, content).unwrap();
    p
}

#[test]
fn open_scratch_returns_ok() {
    let mut dm = DocumentManager::new();
    assert!(dm.open(DocumentSource::Scratch).is_ok());
}

#[test]
fn open_scratch_allocates_distinct_ids() {
    let mut dm = DocumentManager::new();
    let a = dm.open(DocumentSource::Scratch).unwrap();
    let b = dm.open(DocumentSource::Scratch).unwrap();
    assert_ne!(a, b);
}

#[test]
fn open_disk_existing_file_returns_id() {
    let mut dm = DocumentManager::new();
    let id = dm.open(DocumentSource::Disk(temp_file("hello"))).unwrap();
    assert_eq!(id.as_u64(), 1);
}

#[test]
fn open_missing_disk_file_fails_visibly() {
    let mut dm = DocumentManager::new();
    let err = dm
        .open(DocumentSource::Disk(
            "/nonexistent/aster-no-such-file".into(),
        ))
        .unwrap_err();
    assert!(matches!(err, DocumentManagerError::ReadFailed { .. }));
}

#[test]
fn close_known_buffer_succeeds() {
    let mut dm = DocumentManager::new();
    let id = dm.open(DocumentSource::Scratch).unwrap();
    assert!(dm.close(id).is_ok());
}

#[test]
fn close_unknown_buffer_fails() {
    let mut dm = DocumentManager::new();
    assert_eq!(
        dm.close(BufferId::new(999)),
        Err(DocumentManagerError::UnknownBuffer(BufferId::new(999)))
    );
}

#[test]
fn close_same_buffer_twice_fails_second_time() {
    let mut dm = DocumentManager::new();
    let id = dm.open(DocumentSource::Scratch).unwrap();
    assert!(dm.close(id).is_ok());
    assert_eq!(dm.close(id), Err(DocumentManagerError::UnknownBuffer(id)));
}

#[test]
fn open_after_close_reuses_nothing_and_allocates_new_id() {
    let mut dm = DocumentManager::new();
    let a = dm.open(DocumentSource::Scratch).unwrap();
    dm.close(a).unwrap();
    let b = dm.open(DocumentSource::Scratch).unwrap();
    assert_ne!(a, b);
}

#[test]
fn save_text_writes_back_to_disk_and_updates_registry() {
    let path = temp_file("old");
    let mut dm = DocumentManager::new();
    let id = dm.open(DocumentSource::Disk(path.clone())).unwrap();
    dm.save_text(id, "new content 你好").unwrap();
    // 磁盘文件内容更新（ADR-023 决策 1；注册表副本同步在单元测试验证——
    // text() 是 pub(crate) 内部通道，不属公共 API）。
    assert_eq!(std::fs::read_to_string(&path).unwrap(), "new content 你好");
}

#[test]
fn save_text_unknown_id_fails() {
    let mut dm = DocumentManager::new();
    let err = dm.save_text(BufferId::new(999), "x").unwrap_err();
    assert_eq!(err, DocumentManagerError::UnknownBuffer(BufferId::new(999)));
}

#[test]
fn save_text_scratch_without_path_fails_visibly() {
    let mut dm = DocumentManager::new();
    let id = dm.open(DocumentSource::Scratch).unwrap();
    let err = dm.save_text(id, "x").unwrap_err();
    assert_eq!(err, DocumentManagerError::NoPath(id));
}

#[test]
fn save_text_write_failure_is_visible() {
    // 打开一个文件后把路径换成目录：写入必然失败（IsADirectory），错误必须可见
    // （ADR-004 / ADR-023 决策 2），不能静默吞掉。
    let path = temp_file("old");
    let mut dm = DocumentManager::new();
    let id = dm.open(DocumentSource::Disk(path.clone())).unwrap();
    std::fs::remove_file(&path).unwrap();
    std::fs::create_dir(&path).unwrap();
    let err = dm.save_text(id, "x").unwrap_err();
    assert!(matches!(
        err,
        DocumentManagerError::SaveFailed {
            path: ref p,
            kind: std::io::ErrorKind::IsADirectory,
        } if p == &path
    ));
}
