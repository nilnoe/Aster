//! 编辑会话（T-013，ADR-017）。
//!
//! 决策依据：
//! - `Editor` 协调 Buffer（文本，ADR-005）+ Selection（选区几何，ADR-007）+
//!   History（逆操作栈，ADR-008），是状态协调者而非抽象层（Rule 1 不触发）。
//! - 编辑语义全部可单测：UTF-8 字符边界移动 / 删除、选区替换、undo/redo 后的
//!   光标裁剪——可测逻辑留在 Core（docs/testing.md）。
//! - Up/Down 保持「字节列」（ADR-017 备注：CJK 视觉列随渲染切片细化）；
//!   行结构按需用 Layout 重建（ADR-009：编辑后重建）。

use crate::buffer::{Buffer, BufferId};
use crate::error::BufferError;
use crate::history::{EditOp, History};
use crate::layout::Layout;
use crate::selection::Selection;

/// 光标移动方向（ADR-017）。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Movement {
    Left,
    Right,
    Up,
    Down,
    LineStart,
    LineEnd,
    DocStart,
    DocEnd,
}

/// 编辑会话：一次编辑操作的完整状态。
pub struct Editor {
    buffer: Buffer,
    selection: Selection,
    history: History,
}

impl Editor {
    pub fn new(buffer: Buffer) -> Self {
        Self {
            buffer,
            selection: Selection::new(0),
            history: History::new(),
        }
    }

    pub fn text(&self) -> &str {
        self.buffer.text()
    }

    pub fn selection(&self) -> Selection {
        self.selection
    }

    pub fn buffer_id(&self) -> BufferId {
        self.buffer.id()
    }

    /// 用 `s` 替换选区；选区折叠时等价于光标处插入。
    ///
    /// 返回 `None` 表示无变化（空文本插入到折叠光标，不污染历史）。
    /// 合并规则：连续相邻 Insert 并入一步（ADR-008），选区替换单独成步（`Replace`）。
    pub fn type_text(&mut self, s: &str) -> Result<Option<EditOp>, BufferError> {
        let start = self.selection.start();
        let end = self.selection.end();
        if s.is_empty() && start == end {
            return Ok(None);
        }
        let op = if start == end {
            self.buffer.insert(start, s)?;
            EditOp::Insert {
                at: start,
                text: s.to_string(),
            }
        } else {
            let deleted = self.buffer.text()[start..end].to_string();
            self.buffer.delete(start, end)?;
            // 决策依据：start 已由 delete 验证为边界，插入不可能失败（见 apply 同款注释）。
            self.buffer.insert(start, s)?;
            EditOp::Replace {
                at: start,
                end,
                deleted,
                text: s.to_string(),
            }
        };
        self.history.record(op.clone());
        self.selection.collapse(start + s.len());
        Ok(Some(op))
    }

    /// 退格：有选区删选区；否则删光标前一个 UTF-8 字符。
    pub fn delete_backward(&mut self) -> Result<Option<EditOp>, BufferError> {
        let start = self.selection.start();
        let end = self.selection.end();
        let (at, deleted) = if start != end {
            (start, self.buffer.text()[start..end].to_string())
        } else if start > 0 {
            let prev = prev_char_boundary(self.buffer.text(), start);
            (prev, self.buffer.text()[prev..start].to_string())
        } else {
            return Ok(None);
        };
        self.buffer.delete(at, at + deleted.len())?;
        let op = EditOp::Delete { at, text: deleted };
        self.history.record(op.clone());
        self.selection.collapse(at);
        Ok(Some(op))
    }

    /// 移动光标；`extend` 为 Shift 扩展语义（保留锚点，ADR-007）。
    pub fn move_cursor(&mut self, movement: Movement, extend: bool) {
        let text = self.buffer.text();
        let len = text.len();
        let head = self.selection.head();
        let new_head = match movement {
            Movement::Left => prev_char_boundary(text, head),
            Movement::Right => next_char_boundary(text, head),
            Movement::DocStart => 0,
            Movement::DocEnd => len,
            Movement::LineStart | Movement::LineEnd | Movement::Up | Movement::Down => {
                let layout = Layout::build(text);
                let line = layout.line_at(head).unwrap_or(0);
                let (line_start, line_end) = layout
                    .line_range(line)
                    .map(|r| (r.start, r.end))
                    .unwrap_or((0, len));
                match movement {
                    Movement::LineStart => line_start,
                    Movement::LineEnd => line_end,
                    _ => {
                        // 列 = head 相对行首的字节偏移；目标行按列钳制（ADR-017 列语义）。
                        let column = head - line_start;
                        let target = match movement {
                            Movement::Up => line.saturating_sub(1),
                            _ => (line + 1).min(layout.line_count() - 1),
                        };
                        let (t_start, t_end) = layout
                            .line_range(target)
                            .map(|r| (r.start, r.end))
                            .unwrap_or((0, len));
                        t_start + column.min(t_end - t_start)
                    }
                }
            }
        };
        if extend {
            self.selection.set_head(new_head);
        } else {
            self.selection.collapse(new_head);
        }
    }

    pub fn undo(&mut self) -> Result<bool, BufferError> {
        let Some(op) = self.history.undo(&mut self.buffer)? else {
            return Ok(false);
        };
        self.collapse_after(&op, false);
        Ok(true)
    }

    pub fn redo(&mut self) -> Result<bool, BufferError> {
        let Some(op) = self.history.redo(&mut self.buffer)? else {
            return Ok(false);
        };
        self.collapse_after(&op, true);
        Ok(true)
    }

    pub fn select_all(&mut self) {
        self.selection = Selection::new_range(0, self.buffer.len());
    }

    /// 直接设置选区（anchor, head）；越界 / 非字符边界输入被钳制。
    ///
    /// 决策依据：IME 替换区间与鼠标定位需要任意区间选择，移动命令无法表达；
    /// 只修几何不产生历史记录（不是编辑操作）。
    pub fn set_selection(&mut self, anchor: usize, head: usize) {
        let len = self.buffer.len();
        let text = self.buffer.text();
        let anchor = text.floor_char_boundary(anchor.min(len));
        let head = text.floor_char_boundary(head.min(len));
        self.selection = Selection::new_range(anchor, head);
    }

    /// undo/redo 后光标折叠到操作位置并钳制（ADR-017）。
    fn collapse_after(&mut self, op: &EditOp, is_redo: bool) {
        let at = match op {
            EditOp::Insert { at, text } => {
                if is_redo {
                    at + text.len()
                } else {
                    *at
                }
            }
            EditOp::Delete { at, .. } => *at,
            EditOp::Replace { at, text, .. } => {
                if is_redo {
                    at + text.len()
                } else {
                    *at
                }
            }
        };
        self.selection.collapse(at.min(self.buffer.len()));
    }
}

/// `idx` 前一个 UTF-8 字符边界；`idx` 已在边界时返回它本身。
///
/// 决策依据：光标移动必须停在字符边界（ADR-005 UTF-8 安全底线）；
/// `floor_char_boundary` 防御非边界输入（外部构造 Selection 的兜底）。
fn prev_char_boundary(text: &str, idx: usize) -> usize {
    if idx == 0 {
        return 0;
    }
    let idx = text.floor_char_boundary(idx);
    text[..idx]
        .chars()
        .next_back()
        .map_or(0, |c| idx - c.len_utf8())
}

/// `idx` 后一个 UTF-8 字符边界；已到文本末尾返回 `len`。
fn next_char_boundary(text: &str, idx: usize) -> usize {
    if idx >= text.len() {
        return text.len();
    }
    let idx = text.floor_char_boundary(idx);
    text[idx..]
        .chars()
        .next()
        .map_or(text.len(), |c| idx + c.len_utf8())
}
