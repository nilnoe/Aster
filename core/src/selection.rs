//! Selection 模型（ADR-007）。
//!
//! 决策依据：
//! - anchor + head 字节偏移（ADR-006）：head 即光标，方向由 anchor 记录。
//! - 纯值类型、不依赖文本：字符边界校验由 Buffer 负责（ADR-005），Selection 只做几何运算。
//! - 不引入独立 Cursor 类型：光标就是 head，避免两套表示同一概念的 API（宪法 Rule 9）。

/// 文本选区：`anchor`（锚点）与 `head`（光标）。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Selection {
    anchor: usize,
    head: usize,
}

impl Selection {
    /// 折叠选择：光标在 `at`，anchor 与 head 重合。
    pub fn new(at: usize) -> Self {
        Self {
            anchor: at,
            head: at,
        }
    }

    /// 创建区域；两端顺序不重要，`start` / `end` 负责归一化。
    pub fn new_range(anchor: usize, head: usize) -> Self {
        Self { anchor, head }
    }

    pub fn anchor(&self) -> usize {
        self.anchor
    }

    /// 光标位置（选区折叠时与 anchor 相同）。
    pub fn head(&self) -> usize {
        self.head
    }

    /// 有序左端。
    pub fn start(&self) -> usize {
        self.anchor.min(self.head)
    }

    /// 有序右端。
    pub fn end(&self) -> usize {
        self.anchor.max(self.head)
    }

    /// 是否折叠（无选区，仅光标）。
    pub fn collapsed(&self) -> bool {
        self.anchor == self.head
    }

    /// 移动光标、保留锚点。
    ///
    /// 决策依据：这是 Shift + 方向键扩展选区的语义；光标移动不改变锚点。
    pub fn set_head(&mut self, at: usize) {
        self.head = at;
    }

    /// 折叠到 `at`，取消选区。
    pub fn collapse(&mut self, at: usize) {
        self.anchor = at;
        self.head = at;
    }
}
