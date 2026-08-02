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

criterion_group!(
    benches,
    theme_parse,
    command_event,
    lua_dispatch,
    store_scratch
);
criterion_main!(benches);
