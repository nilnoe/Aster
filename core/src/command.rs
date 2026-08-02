//! Command 系统（ADR-011）。
//!
//! 决策依据：
//! - 键盘 / 菜单 / Lua / 命令面板共用一个 Command 入口（ADR 总纲），注册表按名分发。
//! - 处理器用 std `Fn` 动态分发：注册表需容纳异构处理器（内置函数、闭包、
//!   T-008 Lua trampoline）；自定义 Trait 即重复造轮子（宪法 Rule 11）。
//! - 未知命令 / 重复注册必须可见（ADR-004）；处理器失败语义随 T-013 引入。

use std::collections::HashMap;
use std::fmt;

use crate::event::EventBus;

/// 命令处理器。
///
/// 决策依据：私有类型别名，仅用于消化 `dyn Fn` 的冗长签名（clippy
/// type_complexity）；不公开，不构成公共 API（Rule 4）。
type CommandHandler = Box<dyn for<'a> Fn(&mut CommandContext<'a>) -> Result<(), CommandError>>;

/// Command 系统错误（v1 仅注册 / 查找错误）。
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum CommandError {
    /// 执行未注册的命令名。
    UnknownCommand(String),
    /// 命令名已被占用（不静默覆盖，插件冲突要可见）。
    AlreadyRegistered(String),
    /// 处理器执行失败；v1 携带错误消息字符串。
    ///
    /// 决策依据（ADR-011 v1.1）：Lua 命令运行时失败必须可见（ADR-004）；
    /// 消息字符串足够 UI 呈现，结构化错误随 T-013 类型化参数引入。
    HandlerFailed(String),
}

/// 命令执行上下文：命令与 Core 交互的窗口。
///
/// 决策依据：v1 仅持有事件总线（命令经它发出事件）；文档 / 激活 Buffer
/// 访问由 T-013 加入。handler 签名 `Fn(&mut CommandContext)` 不随 context
/// 字段增长而变化——这就是本类型的稳定性价值（Rule 1：防止后续切片
/// 批量修改所有已注册命令的签名）。
pub struct CommandContext<'a> {
    events: &'a mut EventBus,
}

impl<'a> CommandContext<'a> {
    pub fn new(events: &'a mut EventBus) -> Self {
        Self { events }
    }

    /// 事件总线访问：命令修改状态后必须经它广播事件（ADR 总纲数据流）。
    pub fn events(&mut self) -> &mut EventBus {
        self.events
    }
}

/// 命令注册表：命令名 → 处理器。
#[derive(Default)]
pub struct CommandRegistry {
    commands: HashMap<String, CommandHandler>,
}

impl CommandRegistry {
    pub fn new() -> Self {
        Self::default()
    }

    /// 注册命令；名字已被占用时失败。
    ///
    /// 决策依据：静默覆盖会让两个插件 / 内置命令在名字冲突时互相吞掉，
    /// 失败可见更符合 ADR-004；覆盖策略留给 T-008（Lua 命名空间）评估。
    pub fn register(
        &mut self,
        name: &str,
        handler: impl for<'a> Fn(&mut CommandContext<'a>) -> Result<(), CommandError> + 'static,
    ) -> Result<(), CommandError> {
        if self.commands.contains_key(name) {
            return Err(CommandError::AlreadyRegistered(name.to_string()));
        }
        self.commands.insert(name.to_string(), Box::new(handler));
        Ok(())
    }

    /// 按名执行命令；未知命令失败（不静默空转，ADR-004）。
    pub fn execute(&self, name: &str, ctx: &mut CommandContext<'_>) -> Result<(), CommandError> {
        let Some(handler) = self.commands.get(name) else {
            return Err(CommandError::UnknownCommand(name.to_string()));
        };
        handler(ctx)
    }
}

impl fmt::Debug for CommandRegistry {
    /// 处理器是 `dyn Fn`，无法派生 Debug；只暴露命令数量。
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("CommandRegistry")
            .field("command_count", &self.commands.len())
            .finish()
    }
}
