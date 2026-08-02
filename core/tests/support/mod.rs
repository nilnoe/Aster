//! 属性测试共享支撑（T-035 拆分，Rule 3：property.rs 超 300 行）。
//!
//! 决策依据：差分模型 / 操作生成器被基础属性测试与 fuzz 属性测试两个二进制共用，
//! 提取为 tests 子目录模块（cargo 不把子目录当独立测试二进制）；测试支撑代码不构成
//! 公共 API（Rule 4 不触发），拆分只为守住单文件 ≤300 行（Rule 12 含测试文件）。

use aster_core::{Editor, Movement};

/// 差分测试用的编辑操作（T-035 起含 Up/Down：字节列语义在朴素模型内与 Editor
/// 同算法实现，见 [`apply_model`]）。
#[derive(Debug, Clone)]
pub enum Op {
    Type(String),
    DeleteBackward,
    Left,
    Right,
    Up,
    Down,
    LineStart,
    LineEnd,
    DocStart,
    DocEnd,
}

pub fn apply_editor(ed: &mut Editor, op: &Op) {
    match op {
        Op::Type(s) => {
            ed.type_text(s).unwrap();
        }
        Op::DeleteBackward => {
            ed.delete_backward().unwrap();
        }
        Op::Left => ed.move_cursor(Movement::Left, false),
        Op::Right => ed.move_cursor(Movement::Right, false),
        Op::Up => ed.move_cursor(Movement::Up, false),
        Op::Down => ed.move_cursor(Movement::Down, false),
        Op::LineStart => ed.move_cursor(Movement::LineStart, false),
        Op::LineEnd => ed.move_cursor(Movement::LineEnd, false),
        Op::DocStart => ed.move_cursor(Movement::DocStart, false),
        Op::DocEnd => ed.move_cursor(Movement::DocEnd, false),
    }
}

/// 朴素编辑模型：文本 + 字节光标，语义与 Editor（ADR-017）逐布对齐。
#[derive(Debug, Default)]
pub struct Model {
    pub text: String,
    pub cursor: usize,
}

pub fn apply_model(m: &mut Model, op: &Op) {
    match op {
        Op::Type(s) => {
            m.text.insert_str(m.cursor, s);
            m.cursor += s.len();
        }
        Op::DeleteBackward => {
            let prev = m.text[..m.cursor]
                .char_indices()
                .next_back()
                .map_or(0, |(i, _)| i);
            if prev < m.cursor {
                m.text.replace_range(prev..m.cursor, "");
                m.cursor = prev;
            }
        }
        Op::Left => {
            m.cursor = m.text[..m.cursor]
                .char_indices()
                .next_back()
                .map_or(0, |(i, _)| i);
        }
        Op::Right => {
            m.cursor = m.text[m.cursor..]
                .chars()
                .next()
                .map_or(m.cursor, |c| m.cursor + c.len_utf8());
        }
        // BUG-008：Up/Down 与 Editor 同语义——字节列 + 目标行钳制 + floor 到字符
        // 边界；边界不变量另行显式断言（见属性测试内的 is_char_boundary 检查）。
        Op::Up | Op::Down => {
            let starts = line_starts(&m.text);
            let line = starts.partition_point(|&s| s <= m.cursor) - 1;
            let line_start = starts[line];
            let column = m.cursor - line_start;
            let target_line = match op {
                Op::Up => line.saturating_sub(1),
                _ => (line + 1).min(starts.len() - 1),
            };
            let t_start = starts[target_line];
            let t_end = starts
                .get(target_line + 1)
                .map_or(m.text.len(), |&next| next - 1);
            let target = t_start + column.min(t_end - t_start);
            m.cursor = m.text.floor_char_boundary(target.min(m.text.len()));
        }
        Op::LineStart => {
            m.cursor = m.text[..m.cursor].rfind('\n').map_or(0, |i| i + 1);
        }
        Op::LineEnd => {
            m.cursor = m.text[m.cursor..]
                .find('\n')
                .map_or(m.text.len(), |i| m.cursor + i);
        }
        Op::DocStart => m.cursor = 0,
        Op::DocEnd => m.cursor = m.text.len(),
    }
}

/// 行起始字节偏移（与 Core `Layout` 语义一致：ADR-009）。
pub fn line_starts(text: &str) -> Vec<usize> {
    let mut starts = vec![0];
    for (i, b) in text.bytes().enumerate() {
        if b == b'\n' {
            starts.push(i + 1);
        }
    }
    starts
}
