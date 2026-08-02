//! Store / Snapshot 桥接适配（T-045 拆分，Rule 3：bridge.rs 308 行超限）。
//!
//! 决策依据：
//! - 与 bridge.rs 的 Editor / DocumentManager 适配同构：只做机械类型适配
//!   （usize↔UInt 等），业务逻辑仍在 store / snapshot 模块（SRP）。
//! - 本模块私有（lib.rs `mod bridge_store` 不 pub），函数不构成公共 API
//!   （Rule 4 / 12）；bridge.rs `use crate::bridge_store::*` 供 swift-bridge
//!   宏按名解析（同一 crate 内，生成 FFI 胶水不受影响）。
//! - 快照是纯文本文件（ADR-023 v1.4）；缓冲 / 哨兵 / 生命周期是 SQLite
//!   （ADR-013 v1.1 / v1.3）；错误映射为消息字符串（ADR-014 惯例）。

use crate::snapshot::Snapshot;
use crate::store::Store;

/// 建立快照目录句柄（App 持有 opaque）。
pub fn snapshot_new(dir: String) -> Snapshot {
    Snapshot::new(std::path::PathBuf::from(dir))
}

/// Cmd+N：创建当日下一个序号文本快照并返回 seq。
pub fn snapshot_create_next(snapshot: &Snapshot) -> Result<usize, String> {
    snapshot
        .create_next()
        .map(|seq| seq as usize)
        .map_err(|e| format!("{e:?}"))
}

/// Cmd+S：把缓冲文本合并（覆盖写）进指定序号快照（提交 / 固化）。
pub fn snapshot_write(snapshot: &Snapshot, seq: usize, content: String) -> Result<(), String> {
    snapshot
        .write(seq as i64, &content)
        .map_err(|e| format!("{e:?}"))
}

/// 读取快照内容（T-028 恢复 / 测试）。
pub fn snapshot_read(snapshot: &Snapshot, seq: usize) -> Result<String, String> {
    snapshot.read(seq as i64).map_err(|e| format!("{e:?}"))
}

/// 自动保存缓冲文件（崩溃保护；App 启动时打开并保持连接）。
pub fn store_open_buffer(dir: String) -> Result<Store, String> {
    Store::open_buffer(std::path::Path::new(&dir)).map_err(|e| format!("{e:?}"))
}

/// Cmd+S 保存点：把 Buffer 文本 upsert 进 scratch 表。
pub fn store_save_scratch(store: &mut Store, id: usize, content: String) -> Result<(), String> {
    store
        .save_scratch(id as u64, &content)
        .map_err(|e| format!("{e:?}"))
}

/// 读取已保存内容（测试 / T-028 Scratch 接线用）；不存在返回错误。
pub fn store_load_scratch(store: &Store, id: usize) -> Result<String, String> {
    store
        .load_scratch(id as u64)
        .map_err(|e| format!("{e:?}"))?
        .ok_or_else(|| format!("scratch {id} not found"))
}

/// 设置干净退出哨兵（T-043，ADR-013 v1.1：正常退出 true / 启动清 false）。
pub fn store_set_clean_exit(store: &mut Store, clean: bool) -> Result<(), String> {
    store.set_clean_exit(clean).map_err(|e| format!("{e:?}"))
}

/// 读取干净退出哨兵（崩溃检测）。
pub fn store_is_clean_exit(store: &Store) -> Result<bool, String> {
    store.is_clean_exit().map_err(|e| format!("{e:?}"))
}

/// 缓冲文档 id 列表（恢复时取最大 id = 最新文档）。
pub fn store_scratch_ids(store: &Store) -> Vec<usize> {
    store
        .list_scratch()
        .map(|rows| rows.into_iter().map(|(id, _)| id as usize).collect())
        .unwrap_or_default()
}

/// 删除缓冲行（T-045，ADR-013 v1.3 生命周期）：合并成功 / 恢复载入 / 明确丢弃时
/// 调用；返回是否真的删除了行（幂等）。
pub fn store_delete_scratch(store: &mut Store, id: usize) -> Result<bool, String> {
    store
        .delete_scratch(id as u64)
        .map_err(|e| format!("{e:?}"))
}
