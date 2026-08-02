//! CommandRegistry 公共契约测试（ADR-011）。
//!
//! 策略：公共契约走集成测试；垂直线程测试覆盖
//! 注册 → 执行 → 经 context 广播事件 → 订阅者收到 的完整链路。

use std::cell::RefCell;
use std::rc::Rc;

use aster_core::{BufferId, CommandContext, CommandError, CommandRegistry, Event, EventBus};

#[test]
fn command_execute_vertical_thread_dispatch_to_event() {
    let mut bus = EventBus::new();
    let received = Rc::new(RefCell::new(Vec::new()));
    let sink = received.clone();
    bus.subscribe(move |e: &Event| sink.borrow_mut().push(e.clone()));

    let mut registry = CommandRegistry::new();
    registry
        .register("demo.announce", |ctx: &mut CommandContext| {
            ctx.events().emit(&Event::BufferEdited {
                id: BufferId::new(5),
            });
        })
        .unwrap();

    let mut ctx = CommandContext::new(&mut bus);
    registry.execute("demo.announce", &mut ctx).unwrap();

    assert_eq!(
        *received.borrow(),
        vec![Event::BufferEdited {
            id: BufferId::new(5),
        }]
    );
}

#[test]
fn command_execute_unknown_name_fails() {
    let mut bus = EventBus::new();
    let registry = CommandRegistry::new();
    let mut ctx = CommandContext::new(&mut bus);

    let err = registry.execute("no.such", &mut ctx).unwrap_err();
    assert_eq!(err, CommandError::UnknownCommand("no.such".to_string()));
}

#[test]
fn command_register_duplicate_name_fails() {
    let mut registry = CommandRegistry::new();
    registry
        .register("dup", |_: &mut CommandContext| {})
        .unwrap();

    let err = registry
        .register("dup", |_: &mut CommandContext| {})
        .unwrap_err();
    assert_eq!(err, CommandError::AlreadyRegistered("dup".to_string()));
}

#[test]
fn command_register_distinct_names_dispatch_independently() {
    let mut registry = CommandRegistry::new();
    let calls = Rc::new(RefCell::new(Vec::new()));
    let sink_a = calls.clone();
    registry
        .register("a", move |_| sink_a.borrow_mut().push("a"))
        .unwrap();
    let sink_b = calls.clone();
    registry
        .register("b", move |_| sink_b.borrow_mut().push("b"))
        .unwrap();

    let mut bus = EventBus::new();
    let mut ctx = CommandContext::new(&mut bus);
    registry.execute("a", &mut ctx).unwrap();
    registry.execute("b", &mut ctx).unwrap();
    registry.execute("a", &mut ctx).unwrap();

    assert_eq!(*calls.borrow(), vec!["a", "b", "a"]);
}
