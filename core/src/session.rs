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
use crate::session_error::SessionError;
use crate::snapshot::Snapshot;
use crate::store::Store;

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
    pub fn open_scratch(&mut self) -> Result<u64, SessionError> {
        let id = self.dm.open(DocumentSource::Scratch)?;
        let id = id.as_u64();
        let seq = self.snapshot.create_next().ok();
        self.docs.insert(id, DocState::new(seq, String::new()));
        Ok(id)
    }

    /// 打开磁盘文件并登记。基线 = **文件内容**（T-070 修正：undo 回原文不置脏）。
    pub fn open_disk(&mut self, path: &str) -> Result<u64, SessionError> {
        let id = self.dm.open(DocumentSource::Disk(path.into()))?;
        let id = id.as_u64();
        let text = self.text(id)?.to_string();
        let seq = self.snapshot.create_next().ok();
        self.docs.insert(id, DocState::new(seq, text));
        Ok(id)
    }

    pub fn text(&self, id: u64) -> Result<&str, SessionError> {
        self.dm
            .text(BufferId::new(id))
            .ok_or(SessionError::UnknownDoc(id))
    }

    /// 内容变更（onChange 唯一入口）：== 基线 → 不置脏并删冗余行（BUG-012）；
    /// != 基线 → 置脏 + 写缓冲，写失败按文档只提示一次（T-054）；未就绪只置脏。
    pub fn content_changed(&mut self, id: u64, content: &str) -> Result<(), SessionError> {
        let clean = {
            let state = self.docs.get(&id).ok_or(SessionError::UnknownDoc(id))?;
            content == state.committed_text
        };
        if clean {
            if let Some(store) = self.store.as_mut() {
                let _ = store.delete_scratch(id);
            }
            let state = self.docs.get_mut(&id).ok_or(SessionError::UnknownDoc(id))?;
            state.pending = false;
            return Ok(());
        }
        match self.store.as_mut() {
            Some(store) => match store.save_scratch(id, content) {
                Ok(()) => {
                    let state = self.docs.get_mut(&id).ok_or(SessionError::UnknownDoc(id))?;
                    state.pending = true;
                    state.save_error_visible = false;
                    Ok(())
                }
                Err(e) => {
                    let state = self.docs.get_mut(&id).ok_or(SessionError::UnknownDoc(id))?;
                    state.pending = true;
                    if !state.save_error_visible {
                        state.save_error_visible = true;
                        Err(SessionError::Store(e))
                    } else {
                        Ok(())
                    }
                }
            },
            None => {
                let state = self.docs.get_mut(&id).ok_or(SessionError::UnknownDoc(id))?;
                state.pending = true;
                Ok(())
            }
        }
    }

    /// Cmd+S：合并缓冲 → 快照（ADR-023 v1.3）。顺序（变异 M1 保护点）：读缓冲
    /// → 写快照 → 更新基线 → 删缓冲行——写失败时缓冲与未决原样保留。
    pub fn save(&mut self, id: u64) -> Result<(), SessionError> {
        let (seq, text) = {
            let store = self.store.as_mut().ok_or(SessionError::StoreNotReady)?;
            let state = self.docs.get(&id).ok_or(SessionError::UnknownDoc(id))?;
            let seq = state.snapshot_seq.ok_or(SessionError::NoSnapshot(id))?;
            if !state.pending {
                return Ok(()); // 无未提交更改时 ⌘S 是空操作（App 既有语义）
            }
            let text = store
                .load_scratch(id)?
                .ok_or(SessionError::MissingBuffer(id))?;
            (seq, text)
        };
        self.snapshot.write(seq, &text)?;
        if let Some(store) = self.store.as_mut() {
            // 删除失败容忍：内容已固化，残留下次编辑自愈（与内容一致分支同策略）。
            let _ = store.delete_scratch(id);
        }
        let state = self.docs.get_mut(&id).ok_or(SessionError::UnknownDoc(id))?;
        state.committed_text = text;
        state.pending = false;
        state.save_error_visible = false;
        Ok(())
    }

    /// 退出「保存全部」：按 id 升序逐个合并，任一失败即中止（ADR-004 失败可见）。
    pub fn save_all(&mut self) -> Result<(), SessionError> {
        for id in self.pending_ids() {
            self.save(id)?;
        }
        Ok(())
    }

    /// 丢弃单个文档（窗口关闭「不保存」）：删缓冲行 + 清未决（删除时机 3）。
    pub fn discard(&mut self, id: u64) -> Result<(), SessionError> {
        if let Some(store) = self.store.as_mut() {
            let _ = store.delete_scratch(id);
        }
        let state = self.docs.get_mut(&id).ok_or(SessionError::UnknownDoc(id))?;
        state.pending = false;
        Ok(())
    }

    /// 退出「全部不保存」：丢弃所有未决文档。
    pub fn discard_all(&mut self) -> Result<(), SessionError> {
        for id in self.pending_ids() {
            self.discard(id)?;
        }
        Ok(())
    }

    pub fn pending_ids(&self) -> Vec<u64> {
        let mut ids: Vec<u64> = self
            .docs
            .iter()
            .filter(|(_, state)| state.pending)
            .map(|(id, _)| *id)
            .collect();
        ids.sort_unstable();
        ids
    }

    pub fn is_pending(&self, id: u64) -> bool {
        self.docs
            .get(&id)
            .map(|state| state.pending)
            .unwrap_or(false)
    }

    /// 快照序号（测试 / 审计断言）；未登记显式报错。
    pub fn snapshot_seq(&self, id: u64) -> Result<u64, SessionError> {
        self.docs
            .get(&id)
            .and_then(|state| state.snapshot_seq)
            .map(|seq| seq as u64)
            .ok_or_else(|| {
                if self.docs.contains_key(&id) {
                    SessionError::NoSnapshot(id)
                } else {
                    SessionError::UnknownDoc(id)
                }
            })
    }

    /// 读取缓冲内容（崩溃恢复载入）；行缺失显式报错。
    pub fn load_buffered(&self, id: u64) -> Result<String, SessionError> {
        let store = self.store.as_ref().ok_or(SessionError::StoreNotReady)?;
        store
            .load_scratch(id)?
            .ok_or(SessionError::MissingBuffer(id))
    }

    /// 删除缓冲行（恢复载入后清理被恢复的旧行，ADR-013 v1.3 删除时机 2）。
    pub fn delete_buffered(&mut self, id: u64) -> Result<bool, SessionError> {
        let store = self.store.as_mut().ok_or(SessionError::StoreNotReady)?;
        Ok(store.delete_scratch(id)?)
    }

    /// 崩溃遗留行登记：分配序号（保留原序号）+ 置未决（BUG-011 / 016）。
    pub fn register_buffered(&mut self, id: u64) -> Result<u64, SessionError> {
        let state = self
            .docs
            .entry(id)
            .or_insert_with(|| DocState::new(None, String::new()));
        if state.snapshot_seq.is_none() {
            let seq = self.snapshot.create_next()?;
            state.snapshot_seq = Some(seq);
        }
        state.pending = true;
        Ok(state.snapshot_seq.unwrap() as u64)
    }

    pub fn prune_empty(&self) -> Result<usize, SessionError> {
        Ok(self.snapshot.prune_empty()?)
    }

    /// 关闭文档：注册表移除（ADR-001 生命周期；T-070 修正注册表永不关闭的泄漏）。
    pub fn close_document(&mut self, id: u64) -> Result<(), SessionError> {
        self.dm.close(BufferId::new(id))?;
        self.docs.remove(&id);
        Ok(())
    }
}
