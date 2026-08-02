# ADR-005 — Buffer 数据模型（最小化）

- **Status:** Accepted
- **Date:** 2026-08-02
- **Version:** 1.0
- **新增 Public API:** 3 个公开类型、9 个方法、2 个错误变体
- **影响模块:** Core（新增 buffer 模块）
- **是否违反 Single Responsibility:** 否
- **是否增加循环依赖:** 否

---

## 决策

Buffer 是编辑器第一公民（项目哲学）。第一阶段用 `String` 作为文本存储，提供最小编辑操作（`insert` / `delete`），并保证 UTF-8 字符边界安全。

## 原因

- 项目至今没有代码（T-001 是第一个代码切片）；Buffer 数据模型是 Core 的起点。
- `String` 是最简实现（宪法 Rule 9）：成熟 UTF-8 API、O(1) 追加；Rope 等复杂结构留给基准数据证明需要时再引入（T-020）。
- 新增 Public API 必须有 ADR（宪法 Rule 4）。
- Buffer 的生命周期不属于本模块：由 DocumentManager 管理（ADR-001）。

## 审计

### Single Responsibility — 否（不违反）

Buffer 只持有文本与编辑操作；生命周期（ADR-001）、布局（T-005）、渲染均不进入本模块。

### 循环依赖 — 否（不违反）

Core 内独立模块，无任何依赖方向。

## 新增 Public API

- `BufferId`：`new(u64)` / `as_u64()` — 唯一标识；新类型隐藏内部表示，避免与 usize / 内存地址混淆。
- `Buffer`：`new(BufferId)` / `id()` / `text()` / `len()` / `is_empty()` / `insert(at, &str) -> Result<usize, BufferError>` / `delete(start, end) -> Result<usize, BufferError>`。
- `BufferError`：`InvalidCharBoundary(usize)` / `RangeOutOfBounds { start, end, len }`。

不引入 Trait：当前无抽象需求（宪法 Rule 2，直接实现即可）。

## 影响模块

- **Core（新增 buffer 模块）** — 唯一影响；其他模块（Layout、Theme、Command）在后续切片中通过本模块的公共 API 使用 Buffer。

## 复杂度预算（宪法 Rule 9）

1. **增加了哪些复杂度？** 1 个模块、0 抽象层、`String` 存储。
2. **是否是永久性的？** Buffer 与 BufferId 是永久结构；`String` 存储实现可替换，不改变 API 面。
3. **有没有更简单但同样满足需求的方案？** 无——结构体 + `String` 即最简方案。

结论：1 模块 / 12 个公开项 / 0 抽象层，未触及红线。

## 备注

- Rope / 增量存储由性能切片（T-020）以基准数据驱动决定。
- Cursor + Selection（T-003）与 Undo（T-004）在后续切片叠加，不修改本 ADR 的 API。
