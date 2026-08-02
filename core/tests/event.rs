//! EventBus 公共契约测试（ADR-011）。
//!
//! 策略：公共契约走集成测试（docs/testing.md）；订阅者通过共享收集器
//! 断言事件到达，不依赖总线内部结构。

use std::cell::RefCell;
use std::rc::Rc;

use aster_core::{BufferId, Event, EventBus};

#[test]
fn event_bus_emit_reaches_all_subscribers() {
    let mut bus = EventBus::new();
    let seen = Rc::new(RefCell::new(Vec::new()));
    let a = seen.clone();
    bus.subscribe(move |e: &Event| a.borrow_mut().push(e.clone()));
    let b = seen.clone();
    bus.subscribe(move |e: &Event| b.borrow_mut().push(e.clone()));

    let event = Event::BufferEdited {
        id: BufferId::new(7),
    };
    bus.emit(&event);

    assert_eq!(seen.borrow().len(), 2);
    assert_eq!(seen.borrow()[0], event);
    assert_eq!(seen.borrow()[1], event);
}

#[test]
fn event_bus_unsubscribe_stops_delivery() {
    let mut bus = EventBus::new();
    let calls = Rc::new(RefCell::new(0usize));
    let sink = calls.clone();
    let id = bus.subscribe(move |_: &Event| *sink.borrow_mut() += 1);

    assert!(bus.unsubscribe(id));
    bus.emit(&Event::BufferEdited {
        id: BufferId::new(1),
    });
    assert_eq!(*calls.borrow(), 0);
}

#[test]
fn event_bus_subscription_ids_are_unique() {
    let mut bus = EventBus::new();
    let a = bus.subscribe(|_| {});
    let b = bus.subscribe(|_| {});
    assert_ne!(a, b);
}

#[test]
fn event_bus_unsubscribe_unknown_id_returns_false() {
    let mut bus = EventBus::new();
    let id = bus.subscribe(|_| {});
    assert!(bus.unsubscribe(id));
    // 已退订的 id 再次退订为幂等 false（ADR-011：UI 销毁路径不 panic）。
    assert!(!bus.unsubscribe(id));
}

#[test]
fn event_bus_emit_without_subscribers_is_noop() {
    let bus = EventBus::new();
    bus.emit(&Event::BufferEdited {
        id: BufferId::new(1),
    });
}
