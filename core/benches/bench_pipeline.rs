//! 管线组基准（T-023，ADR-021）。
//!
//! 决策依据：为已交付 Core 模块建立稳定基线——Theme DSL 解析、Command 分发 +
//! Event 广播、Lua 命令分发、SQLite Scratch 保存 / 加载；这些模块的接线切片
//! （T-024 / T-028 等）上线前必须有可对照的基线（Rule 16）。

use std::cell::RefCell;
use std::hint::black_box;

use aster_core::{
    BufferId, CommandContext, CommandRegistry, Event, EventBus, LuaRuntime, Store, Theme,
};
use criterion::{criterion_group, criterion_main, Criterion};

fn theme_parse(c: &mut Criterion) {
    let dsl = "editor {
        background: rgba(13,13,15,255)
        foreground: rgba(255,255,255,255)
        selection: rgba(61,115,243,89)
        cursor: rgba(255,255,255,255)
    }";
    c.bench_function("theme_parse_10k", |b| {
        b.iter(|| {
            for _ in 0..10_000 {
                black_box(Theme::parse(dsl).unwrap());
            }
        })
    });
}

fn command_event(c: &mut Criterion) {
    let mut registry = CommandRegistry::new();
    registry.register("noop", |_| Ok(())).unwrap();
    // RefCell：EventBus 被两个基准闭包共享（command 需要 &mut 建 ctx，
    // emit 只读），共享可变借用用 RefCell 表达（不引入并发复杂度，Rule 9）。
    let bus = RefCell::new(EventBus::new());
    bus.borrow_mut().subscribe(|_: &Event| {});
    let event = Event::BufferEdited {
        id: BufferId::new(1),
    };

    c.bench_function("command_execute_10k", |b| {
        b.iter(|| {
            let mut bus_borrow = bus.borrow_mut();
            let mut ctx = CommandContext::new(&mut bus_borrow);
            for _ in 0..10_000 {
                registry.execute("noop", &mut ctx).unwrap();
            }
        })
    });

    c.bench_function("event_emit_10k", |b| {
        b.iter(|| {
            for _ in 0..10_000 {
                bus.borrow().emit(&event);
            }
        })
    });
}

fn lua_dispatch(c: &mut Criterion) {
    c.bench_function("lua_state_new", |b| {
        b.iter(|| black_box(LuaRuntime::new().unwrap()))
    });

    let mut runtime = LuaRuntime::new().unwrap();
    runtime
        .load("aster.register_command(\"hello\", function() end)")
        .unwrap();
    let mut registry = CommandRegistry::new();
    runtime.export_commands(&mut registry).unwrap();
    let bus = RefCell::new(EventBus::new());

    c.bench_function("lua_command_dispatch_10k", |b| {
        b.iter(|| {
            let mut bus_borrow = bus.borrow_mut();
            let mut ctx = CommandContext::new(&mut bus_borrow);
            for _ in 0..10_000 {
                registry.execute("hello", &mut ctx).unwrap();
            }
        })
    });
}

fn store_scratch(c: &mut Criterion) {
    let store = RefCell::new(Store::in_memory().unwrap());

    c.bench_function("store_scratch_save_10k", |b| {
        b.iter(|| {
            for i in 0..10_000u64 {
                store.borrow_mut().save_scratch(i, "content").unwrap();
            }
        })
    });

    c.bench_function("store_scratch_load_10k", |b| {
        b.iter(|| {
            for i in 0..10_000u64 {
                black_box(store.borrow().load_scratch(i).unwrap());
            }
        })
    });
}

fn store_file(c: &mut Criterion) {
    // T-063 余项 + T-066（ADR-006 v1.1 缺口 / WAL 评估）：内存库测不出 journal /
    // WAL 差异——文件库才是生产形态（buffer.sqlite）。新增文件基准（新名，
    // CI 对无基线项跳过，ADR-021 脚本行为）；1s 短测量控制总时长。WAL 落地
    // 前后同配置对比（Rule 16）。
    let dir = std::env::temp_dir().join(format!("aster-bench-store-{}", std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();

    let mut group = c.benchmark_group("store_file");
    group.measurement_time(std::time::Duration::from_secs(1));
    group.sample_size(10);

    group.bench_function("store_file_save_10k", |b| {
        let store = RefCell::new(Store::open(&dir.join("save.sqlite")).unwrap());
        b.iter(|| {
            for i in 0..10_000u64 {
                store.borrow_mut().save_scratch(i, "content").unwrap();
            }
        })
    });

    group.bench_function("store_file_big_blob_1mb", |b| {
        let mut store = Store::open(&dir.join("blob.sqlite")).unwrap();
        let blob = "x".repeat(1024 * 1024);
        b.iter(|| {
            store.save_scratch(1, &blob).unwrap();
        })
    });
}

criterion_group!(
    benches,
    theme_parse,
    command_event,
    lua_dispatch,
    store_scratch,
    store_file
);
criterion_main!(benches);
