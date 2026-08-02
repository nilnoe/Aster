//! Lua Runtime 与 Plugin API（ADR-012）。
//!
//! 决策依据：
//! - mlua 是 rlua 的活跃维护 fork（宪法 Rule 11 复用优先；rlua 已停更），
//!   `vendored` 从源码编译捆绑 Lua 5.4，构建封闭、版本锁定（ADR-012）。
//! - 脚本先经 `aster.*` API 把命令 / 订阅写进 Lua Table，Rust 侧再显式桥入
//!   共享 CommandRegistry / EventBus：mlua 回调是 `'static` 且禁止在 Lua
//!   回调栈内重入 Lua，这种"先存后桥"避免借用冲突与重入风险（Rule 9）。
//! - 命令错误经 `CommandError::HandlerFailed` 上抛（ADR-004）；事件订阅者
//!   错误不传播（观察者语义，v1 静默丢弃，tracing 日志切片落地后呈现）。

use std::fmt;

use mlua::{Function, Lua, Table};

use crate::command::{CommandContext, CommandError, CommandRegistry};
use crate::event::{Event, EventBus};

/// Lua 运行时错误。
#[derive(Debug)]
pub enum LuaError {
    /// Lua 执行 / API 调用错误。
    Lua(mlua::Error),
    /// 命令桥接错误（来自 CommandRegistry，如同名冲突）。
    Command(CommandError),
}

/// Lua 5.4 宿主与 v1 Plugin API（ADR-012）。
pub struct LuaRuntime {
    lua: Lua,
    /// 插件命令表：命令名 → Lua 函数（脚本经 `aster.register_command` 写入）。
    commands: Table,
    /// 插件订阅表：数字索引 → Lua 事件处理函数（脚本经 `aster.subscribe` 写入）。
    subscribers: Table,
}

impl LuaRuntime {
    /// 创建 Lua 状态并安装 `aster` API 表。
    pub fn new() -> Result<Self, LuaError> {
        let lua = Lua::new();
        let commands = lua.create_table().map_err(LuaError::Lua)?;
        let subscribers = lua.create_table().map_err(LuaError::Lua)?;

        let aster = lua.create_table().map_err(LuaError::Lua)?;
        {
            let commands = commands.clone();
            let register_command = lua
                .create_function(move |_lua: &Lua, (name, func): (String, Function)| {
                    commands.set(name, func)
                })
                .map_err(LuaError::Lua)?;
            aster
                .set("register_command", register_command)
                .map_err(LuaError::Lua)?;
        }
        {
            let subscribers = subscribers.clone();
            let subscribe = lua
                .create_function(move |_lua: &Lua, func: Function| {
                    let index = subscribers.raw_len() + 1;
                    subscribers.set(index, func)
                })
                .map_err(LuaError::Lua)?;
            aster.set("subscribe", subscribe).map_err(LuaError::Lua)?;
        }

        lua.globals().set("aster", aster).map_err(LuaError::Lua)?;
        Ok(Self {
            lua,
            commands,
            subscribers,
        })
    }

    /// 执行插件脚本；同一状态内多次调用共享 globals（插件命名空间由插件自负责）。
    pub fn load(&mut self, script: &str) -> Result<(), LuaError> {
        self.lua.load(script).exec().map_err(LuaError::Lua)
    }

    /// 把脚本注册的 Lua 命令桥入共享注册表；同名冲突失败且可见（ADR-004）。
    ///
    /// 桥入后命令从 CommandRegistry 统一执行（ADR-011：键盘 / 菜单 / Lua 同入口）；
    /// 处理器调用 Lua 函数的错误经 `HandlerFailed` 上抛。
    pub fn export_commands(&self, registry: &mut CommandRegistry) -> Result<(), LuaError> {
        let commands = self.commands.clone();
        for pair in commands.pairs::<String, Function>() {
            let (name, func) = pair.map_err(LuaError::Lua)?;
            registry
                .register(&name, move |_ctx: &mut CommandContext| {
                    func.call::<()>(())
                        .map_err(|e| CommandError::HandlerFailed(e.to_string()))
                })
                .map_err(LuaError::Command)?;
        }
        Ok(())
    }

    /// 把脚本注册的事件处理函数桥入共享总线。
    ///
    /// v1 契约（ADR-012）：订阅函数收到事件携带的 BufferId 数值；
    /// 订阅者错误不传播（观察者语义），v1 静默丢弃。
    pub fn export_subscribers(&self, bus: &mut EventBus) -> Result<(), LuaError> {
        let subscribers = self.subscribers.clone();
        for func in subscribers.sequence_values::<Function>() {
            let func = func.map_err(LuaError::Lua)?;
            bus.subscribe(move |event: &Event| {
                let id = match event {
                    Event::BufferEdited { id } => id.as_u64(),
                };
                let _ = func.call::<()>(id);
            });
        }
        Ok(())
    }

    /// 读取脚本全局状态（插件间通信 / 状态观测）。
    pub fn get_global<T: mlua::FromLua>(&self, name: &str) -> Result<T, LuaError> {
        self.lua.globals().get(name).map_err(LuaError::Lua)
    }

    /// 脚本是否已注册指定命令。
    pub fn has_command(&self, name: &str) -> bool {
        self.commands
            .get::<Option<Function>>(name)
            .unwrap_or(None)
            .is_some()
    }
}

impl fmt::Debug for LuaRuntime {
    /// Lua 状态无法派生 Debug；只暴露登记量。
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("LuaRuntime")
            .field("command_count", &self.commands.raw_len())
            .field("subscriber_count", &self.subscribers.raw_len())
            .finish()
    }
}
