//! 文档会话状态机（T-070，ADR-025）。
//!
//! 决策依据：T-070 前文档生命周期状态（未决 / 快照序号 / 已固化基线 / 失败
//! 提示）散落在 AppDelegate 三张平行账本 + 全局布尔，6+ 条路径手工同步，每次
//! 新功能（Frame / 恢复 / 关闭流）踩坏一条就是 BUG-010~018 中的一串（ADR-025
//! 证据）。本模块是这些状态的**唯一所有者**；不变量（未决 ⟺ 缓冲行、未决必有
//! 快照序号、序号唯一）由方法保证。边界：不管窗口 / 视图（frame 属 App 层）、
//! 不管文本编辑语义（Editor）；存储未就绪不阻止会话（保存时再报，T-054）。

use std::collections::HashMap;
use std::path::Path;

use crate::buffer::BufferId;
use crate::document_manager::{DocumentManager, DocumentSource};
use crate::editor::Editor;
use crate::session_error::SessionError;
use crate::snapshot::Snapshot;
use crate::store::Store;

// 编辑 / 保存 / 恢复编排（T-075 拆分，Rule 3：session.rs 316 行超限——T-045
// 同款模式）：同一 struct 的 impl 块放 child module，可访问私有字段，封装
// 边界不变（Rule 12）。
mod edit;

/// 单个文档的会话状态（替代旧 App 三张平行账本）。
#[derive(Debug)]
struct DocState {
    /// 快照序号（⌘S 合并目标）；存储故障时 None，保存时报「没有可合并的快照」。
    snapshot_seq: Option<i64>,
    /// 已固化文本基线（BUG-012）：内容 == 基线 → 不置脏并删冗余缓冲行。
    committed_text: String,
    /// 未决标记（ADR-013 v1.4）；不变量 pending ⟺ 缓冲行存在（本模块唯一写入口）。
    pending: bool,
    /// 失败提示状态（T-054）：同段落只提示一次、成功复位；按文档隔离（T-070）。
    save_error_visible: bool,
}

impl DocState {
    fn new(snapshot_seq: Option<i64>, committed_text: String) -> Self {
        Self {
            snapshot_seq,
            committed_text,
            pending: false,
            save_error_visible: false,
        }
    }
}

/// 文档会话：注册表 + 缓冲 + 快照的统一所有者（ADR-025）。
pub struct Session {
    /// 文档注册表（ADR-001）：id 分配与磁盘内容读取的唯一入口。
    dm: DocumentManager,
    /// 缓冲（崩溃保护）；启动失败为 None。
    store: Option<Store>,
    /// 纯文本快照目录句柄（ADR-023 v1.4）。
    snapshot: Snapshot,
    /// 文档 id → 会话状态（唯一状态来源）。
    docs: HashMap<u64, DocState>,
    /// 启动时缓冲打开失败的消息（T-054：启动即提示，ADR-004）。
    store_error: Option<String>,
}

impl Session {
    /// 打开（或创建）会话。缓冲打开失败**不**阻止会话（T-054：可继续编辑）。
    pub fn open(dir: &Path) -> Self {
        let (store, store_error) = match Store::open_buffer(dir) {
            Ok(store) => (Some(store), None),
            Err(e) => (None, Some(format!("{e:?}"))),
        };
        // BUG-023：DM id 每进程从 1 重新分配，会与崩溃遗留行 id 碰撞——打开时
        // 把分配游标推进到超过最大遗留行 id。
        let mut dm = DocumentManager::new();
        if let Some(store) = &store {
            let max_buffered = store
                .list_scratch()
                .ok()
                .and_then(|rows| rows.into_iter().map(|(id, _)| id).max())
                .unwrap_or(0);
            dm.advance_next_id(max_buffered);
        }
        Self {
            dm,
            store,
            snapshot: Snapshot::new(dir.to_path_buf()),
            docs: HashMap::new(),
            store_error,
        }
    }

    /// 启动时缓冲打开失败的消息（None = 存储就绪）。
    pub fn store_error(&self) -> Option<&str> {
        self.store_error.as_deref()
    }

    pub fn is_clean_exit(&self) -> Result<bool, SessionError> {
        let store = self.store.as_ref().ok_or(SessionError::StoreNotReady)?;
        Ok(store.is_clean_exit()?)
    }

    pub fn set_clean_exit(&mut self, clean: bool) -> Result<(), SessionError> {
        let store = self.store.as_mut().ok_or(SessionError::StoreNotReady)?;
        store.set_clean_exit(clean)?;
        Ok(())
    }

    pub fn buffered_ids(&self) -> Vec<u64> {
        self.store
            .as_ref()
            .and_then(|s| s.list_scratch().ok())
            .map(|rows| rows.into_iter().map(|(id, _)| id).collect())
            .unwrap_or_default()
    }

    /// Cmd+N / 新 Frame / 恢复：注册 Scratch 并分配快照序号（快照失败容忍）。
    /// `seed` 为启动样例文本（ADR-027：Core 注入共享缓冲，不进历史 / 不置脏）。
    pub fn open_scratch(&mut self, seed: &str) -> Result<u64, SessionError> {
        let id = self.dm.open(DocumentSource::Scratch)?;
        let id = id.as_u64();
        if !seed.is_empty() {
            self.dm.seed_text(BufferId::new(id), seed);
        }
        let seq = self.snapshot.create_next().ok();
        self.docs.insert(id, DocState::new(seq, String::new()));
        Ok(id)
    }

    /// 打开磁盘文件并登记。基线 = **文件内容**（T-070 修正：undo 回原文不置脏）。
    pub fn open_disk(&mut self, path: &str) -> Result<u64, SessionError> {
        let id = self.dm.open(DocumentSource::Disk(path.into()))?;
        let id = id.as_u64();
        let text = self.text(id)?;
        let seq = self.snapshot.create_next().ok();
        self.docs.insert(id, DocState::new(seq, text));
        Ok(id)
    }

    /// 返回文档的编辑会话句柄（ADR-027）：与注册表共享同一 Buffer——编辑即
    /// 注册表内容（I-009 双副本消除）；未知 id 显式报错（ADR-004）。
    pub fn editor(&self, id: u64) -> Result<Editor, SessionError> {
        self.dm
            .shared_buffer(BufferId::new(id))
            .map(Editor::from_shared)
            .ok_or(SessionError::UnknownDoc(id))
    }

    pub fn text(&self, id: u64) -> Result<String, SessionError> {
        self.dm
            .text(BufferId::new(id))
            .ok_or(SessionError::UnknownDoc(id))
    }
}
