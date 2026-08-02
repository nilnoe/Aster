//! Undo / Redo 历史（ADR-008）。
//!
//! 决策依据：
//! - 内存内 inverse-operation 栈（ADR-006）：不做快照，内存只随编辑量增长。
//! - op 在记录时固化逆操作信息：`Delete` 保存被删文本，undo 不依赖 Buffer 历史内容。
//! - 应用失败时栈保持不变（ADR-004：失败可见，历史绝不因失败丢失）。

use crate::buffer::Buffer;
use crate::error::BufferError;

/// 一次编辑操作。
///
/// 公开字段（ADR-008）：调用方保证 op 与 Buffer 状态一致；
/// 不一致时 `undo` / `redo` 返回错误且栈不变。
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum EditOp {
    /// 在字节偏移 `at` 处插入 `text`。
    Insert { at: usize, text: String },
    /// 删除从字节偏移 `at` 开始的 `text.len()` 个字节。
    Delete { at: usize, text: String },
}

impl EditOp {
    /// 逆操作：Insert 的逆是删除对应区间，Delete 的逆是原位重插。
    fn inverse(&self) -> EditOp {
        match self {
            EditOp::Insert { at, text } => EditOp::Delete {
                at: *at,
                text: text.clone(),
            },
            EditOp::Delete { at, text } => EditOp::Insert {
                at: *at,
                text: text.clone(),
            },
        }
    }

    /// 把本操作应用到 Buffer（undo 用逆操作，redo 用原操作）。
    fn apply(&self, buffer: &mut Buffer) -> Result<(), BufferError> {
        match self {
            EditOp::Insert { at, text } => buffer.insert(*at, text).map(|_| ()),
            EditOp::Delete { at, text } => buffer.delete(*at, *at + text.len()).map(|_| ()),
        }
    }
}

/// 编辑历史：undo / redo 两个操作栈。
#[derive(Debug, Default)]
pub struct History {
    undo_stack: Vec<EditOp>,
    redo_stack: Vec<EditOp>,
}

impl History {
    pub fn new() -> Self {
        Self::default()
    }

    /// 记录一次已应用的操作；新记录使 redo 失效。
    ///
    /// 合并规则（ADR-008）：仅相邻追加的 `Insert` 合并
    /// （`prev.at + prev.text.len() == at`），连续输入一次 undo 回退。
    pub fn record(&mut self, op: EditOp) {
        self.redo_stack.clear();
        if let (
            Some(EditOp::Insert {
                at: prev_at,
                text: prev_text,
            }),
            EditOp::Insert { at, text },
        ) = (self.undo_stack.last_mut(), &op)
        {
            if *prev_at + prev_text.len() == *at {
                prev_text.push_str(text);
                return;
            }
        }
        self.undo_stack.push(op);
    }

    /// 撤销最近一次操作，返回被撤销的 op。
    ///
    /// 失败语义：先验证可应用再弹出——任何失败都保持栈不变。
    pub fn undo(&mut self, buffer: &mut Buffer) -> Result<Option<EditOp>, BufferError> {
        let Some(op) = self.undo_stack.last() else {
            return Ok(None);
        };
        op.inverse().apply(buffer)?;
        let op = self
            .undo_stack
            .pop()
            .expect("last() 与 pop() 之间栈未被修改，结构性不变量成立");
        // 决策依据：返回被撤销的 op 供 UI / 状态使用；undo 非热路径，
        // 克隆一次换取不破坏栈所有权的清晰语义（宪法 Rule 9：不为零拷贝优化引入复杂度）。
        self.redo_stack.push(op.clone());
        Ok(Some(op))
    }

    /// 重做最近一次被撤销的操作。
    ///
    /// 失败语义：先验证可应用再弹出——任何失败都保持栈不变。
    pub fn redo(&mut self, buffer: &mut Buffer) -> Result<Option<EditOp>, BufferError> {
        let Some(op) = self.redo_stack.last() else {
            return Ok(None);
        };
        op.apply(buffer)?;
        let op = self
            .redo_stack
            .pop()
            .expect("last() 与 pop() 之间栈未被修改，结构性不变量成立");
        // 决策依据：同 undo——返回被重做的 op；redo 非热路径，克隆可接受。
        self.undo_stack.push(op.clone());
        Ok(Some(op))
    }

    pub fn can_undo(&self) -> bool {
        !self.undo_stack.is_empty()
    }

    pub fn can_redo(&self) -> bool {
        !self.redo_stack.is_empty()
    }
}
