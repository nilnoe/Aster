//! 属性测试（T-032，ADR-022）。
//!
//! 决策依据：手写契约用例无法穷举边界——UTF-8 非边界偏移、任意操作序列、
//! undo/redo 往返、行结构不变量；proptest 生成任意输入并自动缩小失败用例
//! （Rule 11：proptest 是 Rust 属性测试事实标准，不重复造轮子）。
//! 用例数用默认值（可经 `PROPTEST_CASES` 调整），CI 时长由小策略规模保证。

use proptest::prelude::*;

use aster_core::{Buffer, BufferId, Editor, Layout, Movement};

/// 生成 1..=8 个 ASCII / CJK 字符：同时覆盖 UTF-8 单字节与多字节路径。
fn text_strategy() -> impl Strategy<Value = String> {
    prop::collection::vec(
        prop_oneof![
            prop::char::range('a', 'z'),
            prop::char::range('\u{4e00}', '\u{9fff}'),
        ],
        1..=8,
    )
    .prop_map(|chars| chars.into_iter().collect())
}

proptest! {
    /// Buffer：合法字符边界插入必须成功且保持 UTF-8 安全；非法边界 / 越界
    /// 插入必须失败且不改变文本（ADR-005 底线）。
    #[test]
    fn buffer_insert_respects_char_boundaries(
        text in any::<String>(),
        at in any::<usize>(),
        s in any::<String>(),
    ) {
        let mut buf = Buffer::new(BufferId::new(1));
        buf.insert(0, &text).unwrap();
        let original = buf.text().to_string();
        let valid = at <= original.len() && original.is_char_boundary(at);
        match buf.insert(at, &s) {
            Ok(_) => {
                prop_assert!(valid, "非边界 / 越界插入必须失败");
                prop_assert!(buf.text().is_char_boundary(at + s.len()));
                prop_assert_eq!(&buf.text()[..at], &original[..at]);
                prop_assert_eq!(&buf.text()[at + s.len()..], &original[at..]);
            }
            Err(_) => {
                prop_assert!(!valid, "合法边界插入必须成功");
                prop_assert_eq!(buf.text(), original, "失败的插入不得改动文本");
            }
        }
    }

    /// Buffer：`start > end`、越界或非边界删除必须失败且不改文本；
    /// 合法区间删除后原位插回被删内容必须还原原文（round-trip）。
    #[test]
    fn buffer_delete_insert_roundtrip(
        text in any::<String>(),
        start in any::<usize>(),
        end in any::<usize>(),
    ) {
        let mut buf = Buffer::new(BufferId::new(1));
        buf.insert(0, &text).unwrap();
        let original = buf.text().to_string();
        if start > end {
            prop_assert!(buf.delete(start, end).is_err(), "start > end 必须报错");
            prop_assert_eq!(buf.text(), original, "失败的删除不得改动文本");
        } else {
            let valid = start <= original.len()
                && end <= original.len()
                && original.is_char_boundary(start)
                && original.is_char_boundary(end);
            if valid {
                let deleted = original[start..end].to_string();
                buf.delete(start, end).unwrap();
                buf.insert(start, &deleted).unwrap();
                prop_assert_eq!(buf.text(), original, "delete + insert 必须还原原文");
            } else {
                prop_assert!(buf.delete(start, end).is_err(), "非法区间删除必须失败");
                prop_assert_eq!(buf.text(), original);
            }
        }
    }

    /// Editor：随机操作序列下，Core 行为与朴素模型逐布一致（文本 + 光标）。
    /// Up/Down 视觉列语义依赖渲染度量（ADR-017 备注），差分范围不含二者。
    #[test]
    fn editor_matches_model(ops in prop::collection::vec(any_op(), 0..=60)) {
        let mut ed = Editor::new(Buffer::new(BufferId::new(1)));
        let mut model = Model::default();
        for op in &ops {
            apply_editor(&mut ed, op);
            apply_model(&mut model, op);
            prop_assert_eq!(ed.text(), model.text.as_str(), "文本不一致 {:?}", op);
            prop_assert_eq!(
                ed.selection().head(),
                model.cursor,
                "光标不一致 {:?}",
                op
            );
        }
    }

    /// Editor：任意操作序列后 undo 全部回到空文本，redo 全部还原快照
    /// （ADR-008 逆操作栈契约）。
    #[test]
    fn editor_undo_redo_roundtrip(ops in prop::collection::vec(any_op(), 0..=40)) {
        let mut ed = Editor::new(Buffer::new(BufferId::new(1)));
        for op in &ops {
            apply_editor(&mut ed, op);
        }
        let snapshot = ed.text().to_string();
        while ed.undo().unwrap() {}
        prop_assert_eq!(ed.text(), "", "undo 全部后应回到空文本");
        while ed.redo().unwrap() {}
        prop_assert_eq!(ed.text(), snapshot, "redo 全部后应还原快照");
    }

    /// Layout：任意文本行结构不变量（ADR-009）——行数 == `\n` 分割数、
    /// 每个字节偏移落在所属行的 `[start, end]` 内、行内文本不含 `\n`。
    #[test]
    fn layout_line_invariants(text in any::<String>()) {
        let layout = Layout::build(&text);
        prop_assert_eq!(layout.line_count(), text.split('\n').count());
        for b in 0..=text.len() {
            let line = layout.line_at(b).expect("不越界的偏移必有行");
            let range = layout.line_range(line).expect("返回的行号必有效");
            prop_assert!(
                range.start <= b && b <= range.end,
                "偏移 {b} 不在所属行 {line} 的 {range:?} 内"
            );
            prop_assert!(
                !text[range.clone()].contains('\n'),
                "行内不得包含 \\n（行 {line}）"
            );
        }
    }
}

/// 差分测试用的编辑操作（不含 Up/Down，见 editor_matches_model 注释）。
#[derive(Debug, Clone)]
enum Op {
    Type(String),
    DeleteBackward,
    Left,
    Right,
    LineStart,
    LineEnd,
    DocStart,
    DocEnd,
}

fn any_op() -> impl Strategy<Value = Op> {
    prop_oneof![
        text_strategy().prop_map(Op::Type),
        Just(Op::DeleteBackward),
        Just(Op::Left),
        Just(Op::Right),
        Just(Op::LineStart),
        Just(Op::LineEnd),
        Just(Op::DocStart),
        Just(Op::DocEnd),
    ]
}

fn apply_editor(ed: &mut Editor, op: &Op) {
    match op {
        Op::Type(s) => {
            ed.type_text(s).unwrap();
        }
        Op::DeleteBackward => {
            ed.delete_backward().unwrap();
        }
        Op::Left => ed.move_cursor(Movement::Left, false),
        Op::Right => ed.move_cursor(Movement::Right, false),
        Op::LineStart => ed.move_cursor(Movement::LineStart, false),
        Op::LineEnd => ed.move_cursor(Movement::LineEnd, false),
        Op::DocStart => ed.move_cursor(Movement::DocStart, false),
        Op::DocEnd => ed.move_cursor(Movement::DocEnd, false),
    }
}

/// 朴素编辑模型：文本 + 字节光标，语义与 Editor（ADR-017）逐布对齐。
#[derive(Debug, Default)]
struct Model {
    text: String,
    cursor: usize,
}

fn apply_model(m: &mut Model, op: &Op) {
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
