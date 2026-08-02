//! Buffer 最小模型（ADR-005）。
//!
//! 决策依据：
//! - Buffer 是编辑器第一公民，但生命周期属于 DocumentManager（ADR-001），本模块只持有文本与编辑操作。
//! - 第一阶段用 `String` 存储：最简实现（宪法 Rule 9）；Rope 等结构留给基准数据驱动的性能切片（T-020）。
//! - 所有编辑偏移必须是 UTF-8 字符边界，保证不产生非法字符串（UTF-8 安全是编辑器的底线）。

use crate::error::BufferError;

/// Buffer 的唯一标识。
///
/// 决策依据：新类型（newtype）隐藏内部表示，避免与 usize / 内存地址混淆；
/// 当前无抽象需求，不引入 Trait（宪法 Rule 2）。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct BufferId(u64);

impl BufferId {
    pub fn new(id: u64) -> Self {
        Self(id)
    }

    pub fn as_u64(&self) -> u64 {
        self.0
    }
}

/// 文本 Buffer。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Buffer {
    id: BufferId,
    text: String,
}

impl Buffer {
    pub fn new(id: BufferId) -> Self {
        Self {
            id,
            text: String::new(),
        }
    }

    pub fn id(&self) -> BufferId {
        self.id
    }

    pub fn text(&self) -> &str {
        &self.text
    }

    pub fn len(&self) -> usize {
        self.text.len()
    }

    pub fn is_empty(&self) -> bool {
        self.text.is_empty()
    }

    /// 在字节偏移 `at` 处插入 `s`，返回插入后的字节长度。
    ///
    /// 决策依据：`at` 必须是字符边界，否则会产生非法 UTF-8；越界直接拒绝，
    /// 由调用方（Command / IME）负责校正，Core 不猜测调用方意图。
    pub fn insert(&mut self, at: usize, s: &str) -> Result<usize, BufferError> {
        if at > self.text.len() {
            return Err(BufferError::RangeOutOfBounds {
                start: at,
                end: at,
                len: self.text.len(),
            });
        }
        if !self.text.is_char_boundary(at) {
            return Err(BufferError::InvalidCharBoundary(at));
        }
        self.text.insert_str(at, s);
        Ok(self.text.len())
    }

    /// 删除 `[start, end)` 字节区间，返回删除后的字节长度。
    ///
    /// 决策依据：区间两端都必须是字符边界，避免产生非法 UTF-8；
    /// `start > end` 视为非法区间而非空操作，错误要可见（ADR-004）。
    pub fn delete(&mut self, start: usize, end: usize) -> Result<usize, BufferError> {
        if start > end || end > self.text.len() {
            return Err(BufferError::RangeOutOfBounds {
                start,
                end,
                len: self.text.len(),
            });
        }
        if !self.text.is_char_boundary(start) {
            return Err(BufferError::InvalidCharBoundary(start));
        }
        if !self.text.is_char_boundary(end) {
            return Err(BufferError::InvalidCharBoundary(end));
        }
        self.text.replace_range(start..end, "");
        Ok(self.text.len())
    }
}
