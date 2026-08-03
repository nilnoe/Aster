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
use std::cell::RefCell;
use std::rc::Rc;

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
    /// 共享缓冲（ADR-027）：注册表（DocumentManager）与编辑会话持有同一 Rc——
    /// 编辑即注册表内容，结构上不存在第二份副本（I-009 双副本消除）。
    buffer: Rc<RefCell<Buffer>>,
    selection: Selection,
    history: History,
    /// 行索引缓存（T-064，ADR-006 v1.1 热点 2）：移动不改变文本，行结构不变
    /// 却每次全量重建（O(n)/次）——缓存编辑失效、移动复用（首建 O(n)，此后
    /// O(log n) 查询；不违反 ADR-006「不可变快照」决策，仅重建时机更优）。
    layout_cache: Option<Layout>,
}

impl Editor {
    pub fn new(buffer: Buffer) -> Self {
        Self {
            buffer: Rc::new(RefCell::new(buffer)),
            selection: Selection::new(0),
            history: History::new(),
            layout_cache: None,
        }
    }

    /// 以共享缓冲构造（ADR-027）：Session 工厂经此把注册表缓冲交给编辑会话。
    /// `pub(crate)` 不构成公共 API（Rule 12）。
    pub(crate) fn from_shared(buffer: Rc<RefCell<Buffer>>) -> Self {
        Self {
            buffer,
            selection: Selection::new(0),
            history: History::new(),
            layout_cache: None,
        }
    }

    /// 当前文本（副本）。
    ///
    /// 决策依据（ADR-027 v1.1）：缓冲经 RefCell 共享，`&str` 无法跨守卫返回，
    /// 返回 `String`；App 侧原本就经 Bridge 拷贝消费（RustString → String），
    /// 无新增成本；Core 内部编辑路径经 `borrow_mut` 零拷贝操作。
    pub fn text(&self) -> String {
        self.buffer.borrow().text().to_string()
    }

    pub fn selection(&self) -> Selection {
        self.selection
    }

    pub fn buffer_id(&self) -> BufferId {
        self.buffer.borrow().id()
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
            self.buffer.borrow_mut().insert(start, s)?;
            EditOp::Insert {
                at: start,
                text: s.to_string(),
            }
        } else {
            let mut buffer = self.buffer.borrow_mut();
            let deleted = buffer.text()[start..end].to_string();
            buffer.delete(start, end)?;
            // 决策依据：start 已由 delete 验证为边界，插入不可能失败（见 apply 同款注释）。
            buffer.insert(start, s)?;
            EditOp::Replace {
                at: start,
                end,
                deleted,
                text: s.to_string(),
            }
        };
        self.history.record(op.clone());
        self.selection.collapse(start + s.len());
        self.layout_cache = None; // 文本变化 → 行索引失效（T-064）
        Ok(Some(op))
    }

    /// 退格：有选区删选区；否则删光标前一个 UTF-8 字符。
    pub fn delete_backward(&mut self) -> Result<Option<EditOp>, BufferError> {
        let start = self.selection.start();
        let end = self.selection.end();
        let (at, deleted) = if start != end {
            let buffer = self.buffer.borrow();
            (start, buffer.text()[start..end].to_string())
        } else if start > 0 {
            let buffer = self.buffer.borrow();
            let prev = prev_char_boundary(buffer.text(), start);
            (prev, buffer.text()[prev..start].to_string())
        } else {
            return Ok(None);
        };
        self.buffer.borrow_mut().delete(at, at + deleted.len())?;
        let op = EditOp::Delete { at, text: deleted };
        self.history.record(op.clone());
        self.selection.collapse(at);
        self.layout_cache = None; // 文本变化 → 行索引失效（T-064）
        Ok(Some(op))
    }

    /// 移动光标；`extend` 为 Shift 扩展语义（保留锚点，ADR-007）。
    pub fn move_cursor(&mut self, movement: Movement, extend: bool) {
        let buffer = self.buffer.borrow();
        let text = buffer.text();
        let len = text.len();
        let head = self.selection.head();
        let new_head = match movement {
            Movement::Left => prev_char_boundary(text, head),
            Movement::Right => next_char_boundary(text, head),
            Movement::DocStart => 0,
            Movement::DocEnd => len,
            Movement::LineStart | Movement::LineEnd | Movement::Up | Movement::Down => {
                // T-064（ADR-006 v1.1 热点 2）：移动不改变文本——行索引缓存
                // 编辑失效、移动复用（基准：1MB 文档 1k 次 Down 309ms → 预期
                // 一个数量级以上下降，Rule 16 前后对比见 benchmarks.md）。
                if self.layout_cache.is_none() {
                    self.layout_cache = Some(Layout::build(text));
                }
                let layout = self.layout_cache.as_ref().unwrap();
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
        // BUG-008：Up/Down 的字节列目标（column.min）可能落在多字节字符内部，
        // 例如 ASCII 列 4 ↓ 进 CJK 行时目标 9 在 "好" 中间。所有移动统一 floor
        // 到字符边界（ADR-005：编辑偏移必须是字符边界）；Left/Right 等本就停在
        // 边界，floor 是恒等，无需分支。
        let new_head = text.floor_char_boundary(new_head.min(len));
        if extend {
            self.selection.set_head(new_head);
        } else {
            self.selection.collapse(new_head);
        }
    }

    pub fn undo(&mut self) -> Result<bool, BufferError> {
        let Some(op) = self.history.undo(&mut self.buffer.borrow_mut())? else {
            return Ok(false);
        };
        self.collapse_after(&op, false);
        self.layout_cache = None; // 文本变化 → 行索引失效（T-064）
        Ok(true)
    }

    pub fn redo(&mut self) -> Result<bool, BufferError> {
        let Some(op) = self.history.redo(&mut self.buffer.borrow_mut())? else {
            return Ok(false);
        };
        self.collapse_after(&op, true);
        self.layout_cache = None; // 文本变化 → 行索引失效（T-064）
        Ok(true)
    }

    pub fn select_all(&mut self) {
        self.selection = Selection::new_range(0, self.buffer.borrow().len());
    }

    /// 直接设置选区（anchor, head）；越界 / 非字符边界输入被钳制。
    ///
    /// 决策依据：IME 替换区间与鼠标定位需要任意区间选择，移动命令无法表达；
    /// 只修几何不产生历史记录（不是编辑操作）。
    pub fn set_selection(&mut self, anchor: usize, head: usize) {
        let buffer = self.buffer.borrow();
        let len = buffer.len();
        let text = buffer.text();
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
        self.selection.collapse(at.min(self.buffer.borrow().len()));
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

// 单元测试（T-064 缓存不变量断言）放 child module（editor/tests.rs），
// 与 session/edit.rs 同款拆分（Rule 3：editor.rs 303 行超限）。
#[cfg(test)]
mod tests;
