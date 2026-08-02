# ADR-007 — Selection 模型（anchor / head 字节偏移）

- **Status:** Accepted
- **Date:** 2026-08-02
- **Version:** 1.0
- **新增 Public API:** 1 个类型、9 个方法
- **影响模块:** Core（新增 selection 模块）
- **是否违反 Single Responsibility:** 否
- **是否增加循环依赖:** 否

---

## 决策

`Selection` 是纯值类型：`anchor` + `head` 字节偏移（ADR-006 已定）。**光标就是 head**，不引入独立的 `Cursor` 类型。

## 原因

- ADR-006 已确定 Selection 形状；本 ADR 落实并记录其 API（宪法 Rule 4）。
- **不引入 `Cursor` 类型**：光标与选区是同一概念的两个状态（折叠 vs 展开），独立类型会创造两套表示同一概念的 API，增加永久复杂度（Rule 9）。
- 纯值类型、不依赖文本：文本相关的字符边界校验由 Buffer 负责（ADR-005），Selection 只做几何运算。

## 审计

### Single Responsibility — 否（不违反）

Selection 只负责选区几何（锚点 / 光标 / 排序 / 裁剪）；不持有文本、不负责输入处理。

### 循环依赖 — 否（不违反）

selection 模块不依赖任何其他模块，Core 内独立。

## 新增 Public API

| API | 职责 |
| --- | --- |
| `Selection::new(at)` | 折叠选择（仅光标在 `at`） |
| `Selection::new_range(anchor, head)` | 创建区域；两端顺序无关 |
| `anchor()` / `head()` | 读取锚点与光标 |
| `start()` / `end()` | 归一化后的有序两端 |
| `collapsed()` | 是否无选区 |
| `set_head(at)` | 移动光标、保留锚点（Shift 扩展语义） |
| `collapse(at)` | 折叠到 `at`（取消选区） |

## 影响模块

- **Core（新增 selection 模块）** — 唯一影响；T-004（Undo）、T-007（Command）、T-013（编辑循环）通过本模块使用选区。

## 复杂度预算（宪法 Rule 9）

1. **增加了哪些复杂度？** 1 个模块、1 个值类型、9 个方法，0 抽象层。
2. **是否是永久性的？** 是——Selection 是编辑器的永久结构。
3. **有没有更简单但同样满足需求的方案？** 无——纯值类型即最简；`Cursor` 类型被显式拒绝。

## 备注

- 多光标（ADR-006 未定项）未来扩展为有序 `Selection` 集合，不改变本 API。
- 越界但不越 `len` 的非字符边界位置，由调用方结合 Buffer 的错误语义校正，Selection 不猜测。

  v1.1 备注（T-036，I-004）：`clamp(len)` 已移除——发布后零消费者（Rule 14 处置：
  无消费者的公共接口接线或撤销；实际裁剪由 `Editor::set_selection` 的
  `floor_char_boundary` 承担，选区收缩语义经 `Editor` 统一）；对应 3 个测试一并删除。
