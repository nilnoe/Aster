//! Session 集成测试（T-070，ADR-025）。
//!
//! 决策依据：状态收拢后的不变量（未决 ⟺ 缓冲行、未决必有快照序号、序号唯一、
//! 保存失败保全缓冲）经公共 API 验证——这是 App 集成测试（SaveStateInvariant
//! Tests）的 Core 层对应；变异门禁 M1 / M2 / M5 变异点落在本层实现
//! （scripts/mutations.json），以下用例是它们的捕获网。

use std::path::PathBuf;
use std::sync::atomic::{AtomicU64, Ordering};

use aster_core::Session;

static COUNTER: AtomicU64 = AtomicU64::new(0);

fn temp_dir(label: &str) -> PathBuf {
    let dir = std::env::temp_dir().join(format!(
        "aster-session-{}-{}-{}",
        label,
        std::process::id(),
        COUNTER.fetch_add(1, Ordering::Relaxed)
    ));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    dir
}

/// 快照文件名列表（`aster-YYYY-MM-DD-<seq>.txt`，升序）。
fn snapshot_names(dir: &PathBuf) -> Vec<String> {
    let mut names = std::fs::read_dir(dir)
        .unwrap()
        .map(|e| e.unwrap().file_name().into_string().unwrap())
        .filter(|n| n.starts_with("aster-") && n.ends_with(".txt"))
        .collect::<Vec<_>>();
    names.sort();
    names
}

/// 把指定 seq 的快照文件替换为同名目录，强制 `snapshot_write` 失败
/// （Is a directory）——SaveFailurePathTests 的 Core 层等价（T-051 盲区修复）。
fn replace_snapshot_with_dir(dir: &PathBuf, seq: i64) {
    let target = snapshot_names(dir)
        .into_iter()
        .find(|n| n.ends_with(&format!("-{seq:03}.txt")))
        .expect("快照文件必须存在");
    std::fs::remove_file(dir.join(&target)).unwrap();
    std::fs::create_dir(dir.join(target)).unwrap();
}

#[test]
fn open_scratch_assigns_unique_snapshot_and_stays_clean() {
    let dir = temp_dir("scratch");
    let mut s = Session::open(&dir);
    let a = s.open_scratch().unwrap();
    let b = s.open_scratch().unwrap();
    assert_eq!(s.snapshot_seq(a).unwrap(), 1);
    assert_eq!(s.snapshot_seq(b).unwrap(), 2);
    assert!(s.pending_ids().is_empty(), "新文档不置脏");
    assert!(snapshot_names(&dir).len() == 2, "每个文档一个快照文件");
}

#[test]
fn content_changed_marks_pending_and_writes_buffer_row() {
    let dir = temp_dir("dirty");
    let mut s = Session::open(&dir);
    let id = s.open_scratch().unwrap();
    s.content_changed(id, "编辑内容").unwrap();
    assert_eq!(s.pending_ids(), vec![id], "编辑后必须未决");
    assert_eq!(s.buffered_ids(), vec![id], "不变量：未决 ⟺ 缓冲行");
    assert_eq!(s.load_buffered(id).unwrap(), "编辑内容");
}

#[test]
fn content_changed_back_to_committed_clears_pending_and_row() {
    let dir = temp_dir("undo");
    let mut s = Session::open(&dir);
    let id = s.open_scratch().unwrap();
    s.content_changed(id, "X").unwrap();
    // undo 回到与快照一致的 ""（BUG-012：内容 == 基线 → 不置脏）。
    s.content_changed(id, "").unwrap();
    assert!(s.pending_ids().is_empty(), "回到基线不得假 dirty");
    assert!(s.buffered_ids().is_empty(), "冗余缓冲行必须删除");
}

#[test]
fn save_merges_buffer_into_snapshot_and_clears_state() {
    let dir = temp_dir("save");
    let mut s = Session::open(&dir);
    let id = s.open_scratch().unwrap();
    s.content_changed(id, "保存的内容").unwrap();
    s.save(id).unwrap();
    assert!(s.pending_ids().is_empty());
    assert!(s.buffered_ids().is_empty());
    let names = snapshot_names(&dir);
    assert_eq!(names.len(), 1);
    assert_eq!(
        std::fs::read_to_string(dir.join(&names[0])).unwrap(),
        "保存的内容",
        "Cmd+S 合并缓冲 → 快照"
    );
}

#[test]
fn save_failure_preserves_buffer_row_and_pending() {
    let dir = temp_dir("savefail");
    let mut s = Session::open(&dir);
    let id = s.open_scratch().unwrap();
    s.content_changed(id, "必须不丢").unwrap();
    let seq = s.snapshot_seq(id).unwrap() as i64;
    replace_snapshot_with_dir(&dir, seq);

    assert!(s.save(id).is_err(), "写失败必须可见");
    assert_eq!(s.pending_ids(), vec![id], "保存失败不得清未决");
    assert_eq!(s.load_buffered(id).unwrap(), "必须不丢", "缓冲行必须保全");
}

#[test]
fn save_all_merges_multiple_docs_in_id_order() {
    let dir = temp_dir("saveall");
    let mut s = Session::open(&dir);
    let a = s.open_scratch().unwrap();
    let b = s.open_scratch().unwrap();
    s.content_changed(a, "文档A").unwrap();
    s.content_changed(b, "文档B").unwrap();
    s.save_all().unwrap();
    assert!(s.pending_ids().is_empty());
    assert!(s.buffered_ids().is_empty());
    let names = snapshot_names(&dir);
    assert_eq!(names.len(), 2);
    assert!(std::fs::read_to_string(dir.join(&names[0])).unwrap() == "文档A");
    assert!(std::fs::read_to_string(dir.join(&names[1])).unwrap() == "文档B");
}

#[test]
fn discard_removes_row_and_pending() {
    let dir = temp_dir("discard");
    let mut s = Session::open(&dir);
    let id = s.open_scratch().unwrap();
    s.content_changed(id, "丢弃内容").unwrap();
    s.discard(id).unwrap();
    assert!(s.pending_ids().is_empty());
    assert!(
        s.buffered_ids().is_empty(),
        "丢弃必须删缓冲行（删除时机 3）"
    );
}

#[test]
fn discard_all_clears_every_doc() {
    let dir = temp_dir("discardall");
    let mut s = Session::open(&dir);
    for i in 0..3 {
        let id = s.open_scratch().unwrap();
        s.content_changed(id, &format!("内容{i}")).unwrap();
    }
    s.discard_all().unwrap();
    assert!(s.pending_ids().is_empty());
    assert!(s.buffered_ids().is_empty());
}

#[test]
fn open_disk_uses_file_content_as_committed_baseline() {
    let dir = temp_dir("disk");
    let file = dir.join("doc.txt");
    std::fs::write(&file, "磁盘原文").unwrap();
    let mut s = Session::open(&dir);
    let id = s.open_disk(file.to_str().unwrap()).unwrap();
    assert_eq!(s.text(id).unwrap(), "磁盘原文");
    // 编辑后回到原文 = undo 到基线 → 不置脏（T-070 修正：旧基线 "" 会假 dirty）。
    s.content_changed(id, "改动").unwrap();
    assert_eq!(s.pending_ids(), vec![id]);
    s.content_changed(id, "磁盘原文").unwrap();
    assert!(s.pending_ids().is_empty(), "undo 回磁盘原文不得置脏");
}

#[test]
fn open_disk_nonexistent_path_fails_visible() {
    let dir = temp_dir("diskfail");
    let mut s = Session::open(&dir);
    let missing = dir.join("missing.txt");
    assert!(s.open_disk(missing.to_str().unwrap()).is_err());
    assert!(s.text(1).is_err(), "未登记 id 必须显式报错");
}

#[test]
fn recovery_register_buffered_assigns_seq_pending_and_is_idempotent() {
    let dir = temp_dir("recover");
    let mut s = Session::open(&dir);
    // 崩溃遗留行（未登记文档）：register_buffered 分配序号 + 置未决。
    let seq = s.register_buffered(42).unwrap();
    assert!(s.is_pending(42));
    assert_eq!(s.snapshot_seq(42).unwrap(), seq);
    assert_eq!(s.register_buffered(42).unwrap(), seq, "已登记保留原序号");
}

#[test]
fn crash_recovery_roundtrip_via_new_session() {
    let dir = temp_dir("crash");
    {
        let mut s = Session::open(&dir);
        let a = s.open_scratch().unwrap();
        s.content_changed(a, "旧文档").unwrap();
        let b = s.open_scratch().unwrap();
        s.content_changed(b, "最新文档").unwrap();
        s.set_clean_exit(false).unwrap();
    } // 丢弃 session = 模拟崩溃（缓冲行与哨兵落盘）

    let mut s2 = Session::open(&dir);
    assert!(!s2.is_clean_exit().unwrap(), "非干净哨兵 = 异常退出");
    let ids = s2.buffered_ids();
    assert_eq!(ids.len(), 2);
    let latest = *ids.last().unwrap();
    assert_eq!(s2.load_buffered(latest).unwrap(), "最新文档");
    // 恢复语义（ADR-013 v1.3 删除时机 2）：最新内容载入新文档（此处省略视图
    // 层），被恢复的旧行删除；其余行登记为未决（BUG-011 / 016 泛化）。
    assert!(s2.delete_buffered(latest).unwrap());
    for other in ids.iter().filter(|&&x| x != latest) {
        s2.register_buffered(*other).unwrap();
    }
    s2.save_all().unwrap();
    assert!(s2.pending_ids().is_empty());
    assert!(s2.buffered_ids().is_empty(), "保存全部后缓冲清空");
}

#[test]
fn clean_exit_sentinel_roundtrip() {
    let dir = temp_dir("sentinel");
    let mut s = Session::open(&dir);
    assert!(!s.is_clean_exit().unwrap(), "缺省 = 异常退出语义");
    s.set_clean_exit(true).unwrap();
    assert!(s.is_clean_exit().unwrap());
}

#[test]
fn close_document_removes_doc_from_registry() {
    let dir = temp_dir("close");
    let mut s = Session::open(&dir);
    let id = s.open_scratch().unwrap();
    s.close_document(id).unwrap();
    assert!(!s.is_pending(id));
    assert!(s.text(id).is_err(), "关闭后文档不可再访问");
    assert!(s.close_document(id).is_err(), "重复关闭必须报错");
}

#[test]
fn storage_broken_still_allows_editing_but_save_reports_unready() {
    let dir = temp_dir("broken");
    let blocker = dir.join("buffer.sqlite");
    std::fs::write(&blocker, "不是目录").unwrap();
    let mut s = Session::open(&dir);
    assert!(s.store_error().is_some(), "启动必须携带失败消息（T-054）");
    let id = s.open_scratch().unwrap(); // 快照创建失败容忍：seq 为 None
    s.content_changed(id, "可编辑").unwrap();
    assert!(s.pending_ids() == vec![id], "存储故障下编辑仍置脏");
    assert!(s.buffered_ids().is_empty(), "无缓冲可写");
    assert!(matches!(
        s.save(id),
        Err(aster_core::SessionError::StoreNotReady)
    ));
}

#[test]
fn save_requires_pending_doc_to_have_snapshot_seq() {
    let dir = temp_dir("noseq");
    let mut s = Session::open(&dir);
    let id = s.open_scratch().unwrap();
    s.content_changed(id, "内容").unwrap();
    assert!(s.snapshot_seq(id).is_ok());
    assert!(s.snapshot_seq(999).is_err(), "未知文档显式报错");
}
