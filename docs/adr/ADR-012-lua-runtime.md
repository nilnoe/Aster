# ADR-012 — Lua Runtime（mlua）与 Plugin API

- **Status:** Accepted
- **Date:** 2026-08-02
- **Version:** 1.0
- **新增 Public API:** `LuaRuntime`（5 方法）+ `LuaError`（2 变体）+ Lua 侧 API（`aster.register_command` / `aster.subscribe` / 全局读写）+ 新增依赖 **mlua**（宪法 Rule 7 / 8）
- **影响模块:** Core（新增 lua 模块）；command、event（只读使用）
- **是否违反 Single Responsibility:** 否
- **是否增加循环依赖:** 否

---

## 决策

在 Rust Core 中新增 `lua` 模块：`LuaRuntime` 封装 mlua 的 Lua 5.4 状态，`load(script)` 执行插件脚本；Lua 侧提供 v1 Plugin API（`aster.register_command(name, fn)` / `aster.subscribe(fn)`），脚本先把命令 / 订阅存进 Lua Table，再由 `export_commands` / `export_subscribers` 桥入共享的 CommandRegistry / EventBus（ADR-011 统一入口）。

依赖：`mlua`（feature `lua54` + `vendored`）。

## 原因

- **Rule 7（为什么标准库不能解决）：** Rust 标准库没有嵌入式脚本能力；插件体系是 ADR 总纲 3.5 已定方向（Plugin 可以增加 Command / Event / UI / Renderer），必须引入脚本运行时。
- **Rule 11（复用优先）+ Rule 8（第三方库 ADR）：** mlua 是 rlua 的活跃维护 fork（rlua 已停更），MIT 许可、生态成熟，是嵌入 Lua 的事实标准；手写 FFI 绑定 = 重复造轮子且引入大量 unsafe（Rule 11 禁止）。
- **拒绝项：** rlua（停更，风险不可接受）；LuaJIT（Lua 5.1 方言，语义与 5.4 不同）；luau（Roblox 方言，生态窄）。
- **`vendored` 理由：** 从源码编译捆绑的 Lua 5.4（MIT），构建封闭、版本锁定、不依赖系统 Lua（macOS 不预装稳定 Lua，ADR-002 零兼容负担）；mlua 同时支持系统 Lua，但 vendored 可复现性最好。
- **「先存 Lua Table、后显式桥入」的理由：** mlua 的 `create_function` 回调是 `'static`，无法借用外部 Rust 状态；把命令 / 订阅先存在 Lua 侧表里，Rust 侧在顶层一次性桥入共享组件，避免 `Rc<RefCell>` 之类的内部可变性蔓延（Rule 9）。

## 审计

### Single Responsibility — 否（不违反）

lua 模块只做两件事：Lua 宿主（执行脚本）与 Plugin API 面（命令 / 订阅的登记）。命令分发与事件广播属于 command / event 模块，lua 只经参数使用。

### 循环依赖 — 否（不违反）

`lua → command / event`（单向，仅使用其注册表与总线）；mlua 是外部依赖，不反向依赖 Core。

## 新增 Public API

### Rust 侧

| API | 职责 |
| --- | --- |
| `LuaRuntime::new() -> Result<Self, LuaError>` | 创建 Lua 5.4 状态并安装 `aster` API 表 |
| `LuaRuntime::load(&mut self, script: &str) -> Result<(), LuaError>` | 执行脚本；同一状态内多次调用共享 globals |
| `LuaRuntime::export_commands(&self, registry: &mut CommandRegistry) -> Result<(), LuaError>` | 把脚本注册的 Lua 命令桥入共享注册表；同名冲突失败（ADR-011） |
| `LuaRuntime::export_subscribers(&self, bus: &mut EventBus) -> Result<(), LuaError>` | 把脚本注册的事件处理函数桥入共享总线 |
| `LuaRuntime::get_global<T: mlua::FromLua>(&self, name: &str) -> Result<T, LuaError>` | 读取脚本全局状态（插件间通信 / 状态观测） |
| `LuaError::Lua(mlua::Error)` / `Command(CommandError)` | Lua 执行错误与命令桥接错误的区分（ADR-004） |

### Lua 侧（Plugin API v1）

| API | 职责 |
| --- | --- |
| `aster.register_command(name: string, fn)` | 登记命令；名字冲突由 Rust 侧桥入时暴露（ADR-004） |
| `aster.subscribe(fn)` | 登记事件处理函数；v1 收到事件携带的 BufferId 数值参数 |

## 影响模块

- **command / event** — 处理器签名改为可失败（ADR-011 v1.1：新增 `CommandError::HandlerFailed`），Lua 命令错误可向上传播。
- **T-009 / T-013** — Lua 访问 Buffer / 文档经 CommandContext 扩展，届时评估 API 面。
- **T-015+（Overlay）** — 命令面板等经共享 CommandRegistry 执行 Lua 命令，无需感知来源。

## 复杂度预算（宪法 Rule 9）

1. **增加了哪些复杂度？** 1 个模块、1 个依赖（mlua vendored）、5 个方法、2 个错误变体；0 抽象层。
2. **是否是永久性的？** 是——Lua 运行时与 Plugin API 是插件体系（ADR 总纲 3.5）的基石，属永久结构；API 面按切片线性扩展。
3. **有没有更简单但同样满足需求的方案？** 无插件运行时违反 ADR 总纲；手写 FFI 违反 Rule 11 且 unsafe 维护成本更高；rlua / LuaJIT / luau 均有版本或维护风险。mlua + vendored 是最简单合规方案。

结论：1 模块 / 1 依赖 / 5 方法 / 0 抽象层，未触及红线。

## 备注

- **重入限制：** mlua 禁止在 Lua 回调栈内再次进入 Lua。v1 的 Lua 侧 API 只写表、不调用 Lua；事件全部从 Rust 顶层发出，因此不会触发。T-013 把编辑命令接入 Lua 时保持该契约。
- **订阅者错误不传播：** EventBus 处理器签名不可失败（ADR-011），Lua 订阅函数运行错误 v1 静默丢弃（观察者语义，不让单个插件拖垮事件循环）；tracing 日志切片落地后呈现。
- **插件生命周期（卸载 / 重载）与命名空间冲突策略**留后续切片，本切片不实现。
