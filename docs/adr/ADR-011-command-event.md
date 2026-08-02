# ADR-011 — Command 系统与 Event 总线

- **Status:** Accepted
- **Date:** 2026-08-02
- **Version:** 1.0
- **新增 Public API:** 4 个公开类型（`EventBus` / `SubscriptionId` / `CommandRegistry` / `CommandContext`）+ 2 个公开枚举（`Event` / `CommandError`）+ 7 个方法
- **影响模块:** Core（新增 command、event 模块）
- **是否违反 Single Responsibility:** 否
- **是否增加循环依赖:** 否

---

## 决策

在 Rust Core 中新增两个模块：

- **event**：`EventBus`（订阅 / 退订 / 广播）、`Event`（v1 单变体 `BufferEdited { id }`）、`SubscriptionId`（退订句柄）。
- **command**：`CommandRegistry`（命令名 → 处理器）、`CommandContext`（v1 仅持有 `&mut EventBus`）、`CommandError`。

依赖方向单一：`command → event → buffer`（后者仅引用 `BufferId` 类型）。注册表与总线不依赖 DocumentManager 等生命周期模块。

## 原因

- ADR 总纲：键盘、菜单、Lua、命令面板都是 Command 的**统一入口**；Event 是 Core 向外的唯一通知通道，UI / 插件只订阅、不反向控制。本切片落地机制本身；把命令接到 Buffer / 激活文档上属于 T-013（编辑循环）。
- **ADR-006 未确定项「命令表 / 事件总线结构」在此切片确定为** `HashMap<String, Box<dyn Fn(&mut CommandContext)>>` + 带订阅 id 的总线；进入实现前先更新 ADR-006（ADR 规则）。
- **动态分发用 std `Fn`，不自定义 Trait：** 注册表要容纳异构处理器（内置函数、闭包、T-008 的 Lua trampoline）；固定命令枚举不可被插件扩展（ADR：Plugin 可以增加 Command），自定义 Trait 即重复造轮子（宪法 Rule 11）。
- **订阅返回 id 且可退订：** T-008 插件卸载 / UI 重建需要，否则订阅永久泄漏。
- **失败可见（ADR-004）：** 未知命令、重复注册都返回错误，不静默空转、不静默覆盖。
- **处理器 v1 不可失败（无 `Result`）：** 本切片命令只负责分发与事件发出；Buffer 操作错误进入命令路径是 T-013 的事，届时修订本 ADR（公共 API 变更，Rule 4）。
- **单线程，不预加 `Send` / `Sync`：** ADR Performance Goals（无轮询、事件驱动）默认单循环；Lua 线程化（T-008）时再评估。

## 审计

### Single Responsibility — 否（不违反）

- event 模块：订阅管理与事件广播，不含命令。
- command 模块：命令注册与分发，不含事件实现（仅经 context 使用总线）。

### 循环依赖 — 否（不违反）

`command → event → buffer`；无反向依赖。

## 新增 Public API

### event

| API | 职责 |
| --- | --- |
| `Event::BufferEdited { id: BufferId }` | v1 唯一事件：Buffer 内容发生变化 |
| `EventBus::new()` / `Default` | 空总线 |
| `subscribe(impl Fn(&Event) + 'static) -> SubscriptionId` | 订阅；返回退订句柄 |
| `unsubscribe(SubscriptionId) -> bool` | 退订；未知 / 已退订返回 `false`（幂等） |
| `emit(&Event)` | 广播给全部订阅者；`&self` 使处理器无法在广播期间重入总线（编译期约束） |
| `SubscriptionId` | 内部 `usize`，不公开构造；派生 `Debug / Clone / Copy / PartialEq / Eq` |

### command

| API | 职责 |
| --- | --- |
| `CommandRegistry::new()` / `Default` | 空注册表 |
| `register(&str, impl for<'a> Fn(&mut CommandContext<'a>) + 'static) -> Result<(), CommandError>` | 注册命令；同名失败 |
| `execute(&str, &mut CommandContext) -> Result<(), CommandError>` | 按名执行；未知命令失败 |
| `CommandContext::new(&mut EventBus)` | 构造上下文 |
| `CommandContext::events() -> &mut EventBus` | 命令发出事件的通道 |
| `CommandError::UnknownCommand(String)` / `AlreadyRegistered(String)` | 注册 / 查找期错误 |

## 影响模块

- **buffer** — event 仅引用 `BufferId` 类型，无行为依赖。
- **T-008（Lua）** — 经 `register` 注册 Lua 函数命令、经 `subscribe` 订阅事件；命令名与事件表示届时评估。
- **T-013（编辑循环）** — context 增加文档访问（active buffer）；处理器引入 `Result`；届时修订本 ADR。

## 复杂度预算（宪法 Rule 9）

1. **增加了哪些复杂度？** 2 个模块、6 个公开项、7 个方法；0 自定义抽象（std `Fn` + `HashMap` / `Vec`）。
2. **是否是永久性的？** 注册表与总线是编辑器的永久结构；`Event` 枚举与 context 字段按切片线性扩展。
3. **有没有更简单但同样满足需求的方案？**
   - 固定命令枚举：今日更简单，但无法被插件扩展（违反 ADR「Plugin 可以增加 Command」）；
   - 注册表无退订：少了 3 个方法，但订阅随插件 / UI 生命周期泄漏，长期成本更高。

结论：2 模块 / 6 公开项 / 0 抽象层，未触及红线。

## 备注

- `emit` 期间处理器禁止重入总线（退订 / 再次广播），该约束作为公开契约记录（ADR-011）。
- 命令名空串 / 规范化校验留给 T-008（Lua 命名空间）评估。
- 需要 `Send` / `Sync` 的场景（后台任务、插件线程）出现后再评估，不预加约束。
