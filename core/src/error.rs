//! Buffer 操作错误（ADR-005）。
//!
//! 决策依据：错误必须精确表达失败原因（ADR-004：失败要可见）；
//! 越界与非法边界分开表达，调用方才能决定如何校正。

/// Buffer 操作的失败类型。
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BufferError {
    /// 偏移量不是 UTF-8 字符边界。
    InvalidCharBoundary(usize),
    /// 区间非法（`start > end`）或越界。
    RangeOutOfBounds {
        start: usize,
        end: usize,
        len: usize,
    },
}
