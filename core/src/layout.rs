//! Layout 逻辑行模型（ADR-009）。
//!
//! 决策依据：
//! - 不可变快照索引：编辑后由调用方重建（ADR-006 修订），无脏状态与失效 bug。
//! - String 存储下编辑本身 O(n)，行索引不改变渐近复杂度。
//! - `\n` 是唯一行分隔符；`\r` 暂视为行内容（CRLF 归一化留给文件模型切片）。
//! - 视觉 / 像素布局（字体度量、shaping、软换行）属于 T-012，不进入本模块——保持 Core 平台无关。

use std::ops::Range;

/// 逻辑行索引：行号 ↔ 字节区间 ↔ 偏移（字节语义与 Buffer 一致，ADR-005）。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Layout {
    /// 每行起始字节偏移；第一个元素恒为 0。
    line_starts: Vec<usize>,
    /// 构建时的文本长度，用于末行边界。
    text_len: usize,
}

impl Layout {
    /// 从文本快照构建行索引，O(n)。
    pub fn build(text: &str) -> Self {
        let mut line_starts = Vec::new();
        line_starts.push(0);
        for (i, b) in text.bytes().enumerate() {
            if b == b'\n' {
                line_starts.push(i + 1);
            }
        }
        Self {
            line_starts,
            text_len: text.len(),
        }
    }

    pub fn line_count(&self) -> usize {
        self.line_starts.len()
    }

    /// 行号 → 字节区间 `[start, end)`，不含行尾 `\n`。
    ///
    /// 决策依据：`\n` 恰好位于下一行起点减一；末行到文本末尾。
    pub fn line_range(&self, line: usize) -> Option<Range<usize>> {
        let start = *self.line_starts.get(line)?;
        let end = self
            .line_starts
            .get(line + 1)
            .map_or(self.text_len, |&next| next - 1);
        Some(start..end)
    }

    /// 字节偏移 → 行号；`offset > text_len` 时返回 `None`。
    ///
    /// 决策依据：二分查找最后一个 `line_start <= offset`；
    /// 落在 `\n` 上的偏移属于前一行（光标语义：行尾）。
    pub fn line_at(&self, offset: usize) -> Option<usize> {
        if offset > self.text_len {
            return None;
        }
        let idx = self.line_starts.partition_point(|&s| s <= offset);
        Some(idx - 1)
    }

    /// 每行起始字节偏移的只读视图（首元素恒为 0）。
    ///
    /// 决策依据：T-012 渲染切片（ADR-016）经 Bridge 消费，App 按行切分文本做
    /// CoreText shaping；`pub(crate)` 而非 `pub`——不构成公共 API（宪法 Rule 12），
    /// 避免未经 ADR 扩大 Layout 公共面（ADR-009 只承诺四个查询方法）。
    pub(crate) fn line_starts(&self) -> &[usize] {
        &self.line_starts
    }
}

#[cfg(test)]
mod tests {
    use super::Layout;

    /// `line_starts` 是 Bridge 渲染切片（T-012 / ADR-016）的内部访问器：
    /// App 按行切分文本做 CoreText shaping，行结构语义保持 ADR-009。
    #[test]
    fn line_starts_tracks_line_boundaries() {
        let layout = Layout::build("ab\ncd\ne");
        assert_eq!(layout.line_starts(), &[0, 3, 6]);
    }

    #[test]
    fn line_starts_empty_text_is_one_line() {
        let layout = Layout::build("");
        assert_eq!(layout.line_starts(), &[0]);
    }
}
