//! Session 编辑 / 保存 / 恢复编排（T-075 拆分，Rule 3：session.rs 316 行超限）。
//!
//! 决策依据：会话生命周期（打开 / 登记 / 查询 / 编辑句柄）留在 session.rs，
//! 本文件承载内容变更、保存 / 丢弃、恢复原语——同一 struct 的 impl 块放
//! child module，可访问私有字段（封装边界不变，Rule 12；与 bridge / bridge_
//! session 的拆分同模式）。不变量（未决 ⟺ 缓冲行、未决必有快照序号、序号
//! 唯一）仍由本组方法保证（Rule 18）。

use super::{DocState, Session};
use crate::buffer::BufferId;
use crate::session_error::SessionError;

impl Session {
    /// 内容变更（onChange 唯一入口）：== 基线 → 不置脏并删冗余行（BUG-012）；
    /// != 基线 → 置脏 + 写缓冲，写失败按文档只提示一次（T-054）；未就绪只置脏。
    /// ADR-027：不再接收文本参数——内容直接读注册表活文（共享 Buffer），
    /// App 每次按键不再把全文推过 Bridge（消除 ADR-006 热点 1 的 O(n)/键拷贝）。
    pub fn content_changed(&mut self, id: u64) -> Result<(), SessionError> {
        let clean = {
            let state = self.docs.get(&id).ok_or(SessionError::UnknownDoc(id))?;
            self.text(id)? == state.committed_text
        };
        if clean {
            if let Some(store) = self.store.as_mut() {
                let _ = store.delete_scratch(id);
            }
            let state = self.docs.get_mut(&id).ok_or(SessionError::UnknownDoc(id))?;
            state.pending = false;
            return Ok(());
        }
        let content = self.text(id)?;
        match self.store.as_mut() {
            Some(store) => match store.save_scratch(id, &content) {
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
