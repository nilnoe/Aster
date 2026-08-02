//! LuaRuntime 与 Plugin API 的公共契约测试（ADR-012）。
//!
//! 策略：公共契约走集成测试；垂直线程覆盖
//! Lua 脚本注册命令 → 桥入共享 CommandRegistry → 执行 → 回调 Lua 生效，
//! 以及 Rust 发出事件 → Lua 订阅函数收到。

use aster_core::{
    BufferId, CommandContext, CommandError, CommandRegistry, Event, EventBus, LuaError, LuaRuntime,
};

#[test]
fn lua_runtime_load_runs_script_and_reads_global() {
    let mut runtime = LuaRuntime::new().unwrap();
    runtime.load("answer = 42").unwrap();
    assert_eq!(runtime.get_global::<i64>("answer").unwrap(), 42);
}

#[test]
fn lua_command_registered_then_executed_via_shared_registry() {
    let mut runtime = LuaRuntime::new().unwrap();
    runtime
        .load(
            r#"
                count = 0
                aster.register_command("demo.count", function()
                    count = count + 1
                end)
            "#,
        )
        .unwrap();
    assert!(runtime.has_command("demo.count"));

    let mut registry = CommandRegistry::new();
    runtime.export_commands(&mut registry).unwrap();

    let mut bus = EventBus::new();
    let mut ctx = CommandContext::new(&mut bus);
    registry.execute("demo.count", &mut ctx).unwrap();
    registry.execute("demo.count", &mut ctx).unwrap();

    assert_eq!(runtime.get_global::<i64>("count").unwrap(), 2);
}

#[test]
fn lua_command_failure_propagates() {
    let mut runtime = LuaRuntime::new().unwrap();
    runtime
        .load(
            r#"
                aster.register_command("demo.fail", function()
                    error("boom")
                end)
            "#,
        )
        .unwrap();

    let mut registry = CommandRegistry::new();
    runtime.export_commands(&mut registry).unwrap();

    let mut bus = EventBus::new();
    let mut ctx = CommandContext::new(&mut bus);
    let err = registry.execute("demo.fail", &mut ctx).unwrap_err();
    assert!(
        matches!(&err, CommandError::HandlerFailed(msg) if msg.contains("boom")),
        "got: {err:?}"
    );
}

#[test]
fn lua_duplicate_command_export_fails() {
    let mut runtime = LuaRuntime::new().unwrap();
    runtime
        .load(r#"aster.register_command("shared.name", function() end)"#)
        .unwrap();
    let mut registry = CommandRegistry::new();
    runtime.export_commands(&mut registry).unwrap();

    // 第二个插件脚本注册同名命令：桥入时必须失败且可见（ADR-004）。
    runtime
        .load(r#"aster.register_command("shared.name", function() end)"#)
        .unwrap();
    let err = runtime.export_commands(&mut registry).unwrap_err();
    assert!(matches!(
        err,
        LuaError::Command(CommandError::AlreadyRegistered(_))
    ));
}

#[test]
fn lua_subscriber_receives_buffer_edited_event() {
    let mut runtime = LuaRuntime::new().unwrap();
    runtime
        .load(
            r#"
                seen = -1
                aster.subscribe(function(id)
                    seen = id
                end)
            "#,
        )
        .unwrap();

    let mut bus = EventBus::new();
    runtime.export_subscribers(&mut bus).unwrap();

    bus.emit(&Event::BufferEdited {
        id: BufferId::new(9),
    });
    assert_eq!(runtime.get_global::<i64>("seen").unwrap(), 9);
}

#[test]
fn lua_script_error_on_load_fails() {
    let mut runtime = LuaRuntime::new().unwrap();
    let err = runtime.load("this is not lua").unwrap_err();
    assert!(matches!(err, LuaError::Lua(_)));
}
