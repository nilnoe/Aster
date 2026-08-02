# ADR-004 — 日志与崩溃上报

- **Status:** Accepted
- **Date:** 2026-08-02
- **Version:** 1.0
- **新增 Public API:** 0 个
- **影响模块:** Core（tracing）、App（os_log）、Bridge
- **是否违反 Single Responsibility:** 否
- **是否增加循环依赖:** 否

---

## 决策

- **日志：** Swift 侧使用系统 `os_log`；Rust Core 侧使用 `tracing`，经 Bridge 汇入 `os_log`。
- **崩溃：** Core 不做 `catch_unwind` 掩盖错误；panic 即崩溃，交给系统生成报告。
- **上报：** 默认无遥测、无崩溃上报；用户显式开启后才收集。

## 原因

- `tracing` 是 Rust 生态的结构化日志标准（宪法 Rule 11 复用优先）；标准库无等价能力（Rule 7，由本 ADR 覆盖 Rule 8）。
- panic 不捕获：失败要可见、错误路径要可复现；掩盖错误会把 Implementation Bug 变成 Design Bug。
- 默认无上报：编辑器是"空白、安静"的（项目哲学），遥测是入侵。

## 审计

### Single Responsibility — 否（不违反）

日志与崩溃策略不引入业务职责。

### 循环依赖 — 否（不违反）

依赖方向：Core → tracing；App → os_log；Bridge 只做汇聚，无反向依赖。

## 新增 Public API

无。

## 影响模块

- **Core** — 新增 `tracing` 依赖；panic 策略明确。
- **App** — 使用 `os_log`；上报入口（默认关闭）在实现切片中定义。
- **Bridge** — 负责日志汇聚，无业务逻辑。

## 复杂度预算（宪法 Rule 9）

1. **增加了哪些复杂度？** 1 个依赖（tracing）；0 模块 / 0 Public API。
2. **是否是永久性的？** 是——结构化日志是长期可观测性投资。
3. **有没有更简单但同样满足需求的方案？** 手写日志宏更简单但不可观测、不可过滤，长期成本更高。

## 备注

- Crash Recovery 的数据安全由 SQLite 事务保证（Roadmap Phase 4）。
- 崩溃报告格式与开启入口在实现切片中定义，不进入第一阶段默认路径。
