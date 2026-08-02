# ADR-008 — Undo / Redo 模型（inverse-operation 栈）

- **Status:** Accepted
- **Date:** 2026-08-02
- **Version:** 1.0
- **新增 Public API:** 2 个类型（`EditOp`、`History`）+ 6 个方法
- **影响模块:** Core（新增 history 模块）
- **是否违反 Single Responsibility:** 否
- **是否增加循环依赖:** 否

---

## 决策

内存内 inverse-operation 栈（ADR-006 已定）：`History` 持 undo / redo 两个栈，`EditOp` 记录编辑操作，undo 应用逆操作，redo 重放原操作。不做快照。

## 原因

- ADR-006：快照内存是 O(n×k)，操作栈只随编辑量增长。
- `EditOp` 在记录时固化逆操作所需信息：`Insert` 保留文本（redo 直接重放），`Delete` 保留被删文本（undo 可恢复）——undo 不依赖 Buffer 的历史内容。
- **合并规则：** 仅相邻追加的 `Insert` 合并（`prev.at + prev.text.len() == at`），连续输入一次 undo 回退；`Delete` 第一阶段不合并。
- **失败语义：** 应用 op 失败时栈保持不变，错误可见（ADR-004）——历史绝不因失败丢失。

## 审计

### Single Responsibility — 否（不违反）

History 只管理操作栈与合并；不持有文本（Buffer）、不负责命令分发。

### 循环依赖 — 否（不违反）

依赖方向单一：`History → Buffer`（只调用其 `insert` / `delete`）。

## 新增 Public API

| API | 职责 |
| --- | --- |
| `EditOp::Insert { at, text }` / `EditOp::Delete { at, text }` | 一次编辑操作；公开字段，调用方保证与 Buffer 状态一致 |
| `History::new()` / `Default` | 空历史 |
| `record(op)` | 记录已应用的操作：清空 redo、按规则合并 |
| `undo(buffer) -> Result<Option<EditOp>>` | 应用逆操作；失败时栈不变 |
| `redo(buffer) -> Result<Option<EditOp>>` | 重放操作；失败时栈不变 |
| `can_undo()` / `can_redo()` | 菜单 / UI 状态 |

## 影响模块

- **Buffer** — 只读使用其 `insert` / `delete`，无修改。
- **后续：** Document 持有 History（T-007 Command 集成）；SQLite 持久化（T-021）。

## 复杂度预算（宪法 Rule 9）

1. **增加了哪些复杂度？** 1 个模块、0 抽象层；栈内文本为编辑量级。
2. **是否是永久性的？** 是——undo/redo 是编辑器的永久能力；合并规则可在基准数据驱动下调整（T-020）。
3. **有没有更简单但同样满足需求的方案？** 快照方案更简单但内存不可接受（ADR-006 已拒绝）。

结论：1 模块 / 2 类型 / 6 方法。

## 备注

- 合并上限（长粘贴是否分段）留给基准数据驱动（T-020）。
- 多光标（ADR-006 未定项）落地时 `EditOp` 需支持批操作，API 届时评估。
- T-007 若需要"apply + record"的组合入口，属公共 API 变更，须更新本 ADR。
