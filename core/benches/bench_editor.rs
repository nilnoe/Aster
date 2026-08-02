//! 编辑内核基准组（T-023，ADR-021）。
//!
//! 决策依据：覆盖 ADR-006「数据结构评估框架」的编辑热路径 / 行访问 / 打开成本维度；
//! 文本存储（String / Gap / Rope / Piece Table）的决策数据来自本组基准（Rule 16）。
//! 命名以「10k 次」为单位与 docs/benchmarks.md 指标表对齐；每轮重建状态，
//! 测的是包含状态增长的总耗时（String O(n) 漂移会在多次迭代间自然放大）。

use std::hint::black_box;

use aster_core::{
    Buffer, BufferId, DocumentManager, DocumentSource, EditOp, Editor, History, Layout, Selection,
};
use criterion::{criterion_group, criterion_main, Criterion};

/// 约 1MB 的确定性文本（101 字节行 × 10k 行），用于打开 / Layout 基准。
fn one_mb_text() -> String {
    ("x".repeat(100) + "\n").repeat(10_000)
}

fn buffer_ops(c: &mut Criterion) {
    c.bench_function("buffer_insert_end_10k", |b| {
        b.iter(|| {
            let mut buf = Buffer::new(BufferId::new(1));
            for i in 0..10_000u32 {
                buf.insert(buf.len(), &i.to_string()).unwrap();
            }
            black_box(buf.len())
        })
    });

    c.bench_function("buffer_delete_end_10k", |b| {
        b.iter(|| {
            let mut buf = Buffer::new(BufferId::new(1));
            buf.insert(0, &"x".repeat(10_000)).unwrap();
            for _ in 0..10_000 {
                buf.delete(buf.len() - 1, buf.len()).unwrap();
            }
            black_box(buf.len())
        })
    });
}

fn editor_ops(c: &mut Criterion) {
    c.bench_function("editor_type_text_10k", |b| {
        b.iter(|| {
            let mut ed = Editor::new(Buffer::new(BufferId::new(1)));
            for _ in 0..10_000 {
                ed.type_text("a").unwrap();
            }
            black_box(ed.selection().head())
        })
    });

    c.bench_function("editor_delete_backward_10k", |b| {
        b.iter(|| {
            let mut ed = Editor::new(Buffer::new(BufferId::new(1)));
            ed.type_text(&"a".repeat(10_000)).unwrap();
            for _ in 0..10_000 {
                ed.delete_backward().unwrap();
            }
            black_box(ed.text().len())
        })
    });
}

fn selection_ops(c: &mut Criterion) {
    c.bench_function("selection_move_10k", |b| {
        b.iter(|| {
            let mut sel = Selection::new(0);
            for i in 0..10_000usize {
                sel.set_head(i);
            }
            black_box(sel.head())
        })
    });
}

fn history_ops(c: &mut Criterion) {
    c.bench_function("history_record_10k", |b| {
        b.iter(|| {
            let mut hist = History::new();
            for i in 0..10_000usize {
                hist.record(EditOp::Delete {
                    at: i,
                    text: "x".into(),
                });
            }
            black_box(hist.can_undo())
        })
    });

    c.bench_function("history_undo_10k", |b| {
        b.iter(|| {
            let mut hist = History::new();
            let mut buf = Buffer::new(BufferId::new(1));
            buf.insert(0, &"x".repeat(10_000)).unwrap();
            for i in 0..10_000usize {
                hist.record(EditOp::Delete {
                    at: i,
                    text: "x".into(),
                });
            }
            for _ in 0..10_000 {
                hist.undo(&mut buf).unwrap();
            }
            black_box(buf.len())
        })
    });
}

fn layout_and_open(c: &mut Criterion) {
    let text = one_mb_text();

    c.bench_function("layout_build_1mb", |b| {
        b.iter(|| black_box(Layout::build(black_box(&text))))
    });

    c.bench_function("layout_line_at_10k", |b| {
        let layout = Layout::build(&text);
        let len = text.len();
        b.iter(|| {
            let mut pos = 0usize;
            for i in 0..10_000usize {
                pos = layout.line_at((pos + i * 101) % len).unwrap_or(0);
            }
            black_box(pos)
        })
    });

    c.bench_function("document_open_1mb", |b| {
        let path = std::env::temp_dir().join("aster-bench-open-1mb.txt");
        std::fs::write(&path, &text).unwrap();
        b.iter(|| {
            let mut dm = DocumentManager::new();
            let id = dm.open(DocumentSource::Disk(path.clone())).unwrap();
            black_box(id)
        })
    });
}

criterion_group!(
    benches,
    buffer_ops,
    editor_ops,
    selection_ops,
    history_ops,
    layout_and_open
);
criterion_main!(benches);
