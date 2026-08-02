//! fuzz 属性测试（T-033，ADR-022 v1.1；T-035 拆分，Rule 3）。
//!
//! 决策依据：fuzz 语义 = 扩展属性空间（emoji / CJK / 换行 / 组合附加符号），
//! 与基础属性测试共用 `support` 差分模型；CI 以 `PROPTEST_CASES=3000` 专项运行。

use proptest::prelude::*;

use aster_core::{Buffer, BufferId, Editor};

mod support;

use support::{apply_editor, apply_model, Model, Op};

/// fuzz 输入空间（T-033，ADR-022 v1.1）：emoji（UTF-8 4 字节）、CJK、
/// 换行、组合附加符号——在真实多语言多行文本下验证 Editor 不变量。
fn fuzz_text_strategy() -> impl Strategy<Value = String> {
    prop::collection::vec(
        prop_oneof![
            prop::char::range('a', 'z'),
            prop::char::range('\u{4e00}', '\u{9fff}'),
            prop::char::range('\u{1f300}', '\u{1f9ff}'), // emoji（代理对）
            prop::char::range('\u{300}', '\u{36f}'),     // 组合附加符号
            Just('\n'),
        ],
        1..=12,
    )
    .prop_map(|chars| chars.into_iter().collect())
}

/// fuzz 操作序列：与 `any_op` 同构，但输入来自 fuzz 文本空间。
fn any_op_fuzz() -> impl Strategy<Value = Op> {
    prop_oneof![
        fuzz_text_strategy().prop_map(Op::Type),
        Just(Op::DeleteBackward),
        Just(Op::Left),
        Just(Op::Right),
        Just(Op::Up),
        Just(Op::Down),
        Just(Op::LineStart),
        Just(Op::LineEnd),
        Just(Op::DocStart),
        Just(Op::DocEnd),
    ]
}

proptest! {
    /// fuzz 差分（T-033）：多行 + 多字节输入空间下，Editor 与朴素模型逐布一致
    /// （文本 + 光标）；序列更长（≤80 步）以暴露跨行移动 / 组合字符边界问题。
    #[test]
    fn editor_matches_model_fuzz_unicode(
        ops in prop::collection::vec(any_op_fuzz(), 0..=80)
    ) {
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
            // BUG-008 不变量：多行 + 多字节输入下光标必须始终是字符边界。
            prop_assert!(
                ed.text().is_char_boundary(ed.selection().head()),
                "光标落在非字符边界 (head={}) after {:?}",
                ed.selection().head(),
                op
            );
        }
    }

    /// fuzz undo/redo 往返（T-033）：多行 + 多字节输入下逆操作栈契约
    /// （ADR-008）；原用例只覆盖 ASCII/CJK 单行文本。
    #[test]
    fn editor_undo_redo_fuzz_multiline(
        ops in prop::collection::vec(any_op_fuzz(), 0..=60)
    ) {
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
}
