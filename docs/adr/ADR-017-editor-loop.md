# ADR-017 — 编辑循环（Editor 模块）

- **Status:** Accepted
- **Date:** 2026-08-02
- **Version:** 1.0
- **新增 Public API:** Core `Editor` 类型 + 8 方法 + `Movement` 枚举；Bridge FFI 面（Editor opaque + 16 函数）
- **影响模块:** core（新增 editor 模块）、core/src/bridge.rs、app/
- **是否违反 Single Responsibility:** 否
- **是否增加循环依赖:** 否

---

## 决策

T-013 在 Core 新增 `Editor`：持有 `Buffer` + `Selection` + `History`，提供
`type_text` / `delete_backward` / `move_cursor` / `undo` / `redo` / `select_all`，
把「键盘输入、光标、滚动、选择」变成可测试的 Core 语义；App 经 Bridge 调用后
事件驱动重渲染，光标 / 选区高亮 / 滚动窗口在 Metal 渲染层实现。

## 原因

- **Buffer 是第一公民（ADR 总纲）但编辑是会话级语义**：DocumentManager 管生命周期
  （ADR-001）、Buffer 管文本（ADR-005）、Selection 管选区几何（ADR-007）、History 管
  逆操作栈（ADR-008）——需要一个协调者把它们串成一次编辑（替换选区、记录历史、
  删除后裁剪选区），这正是 T-013 的最小缺口。`Editor` 是状态协调者（同 DocumentManager），
  不是抽象层，Rule 1 / 2 不触发。
- **可测逻辑留在 Core（docs/testing.md）**：光标移动的字符 / 行边界语义、删除回退的
  UTF-8 边界、undo/redo 与选区裁剪，全部是可单测的纯逻辑，不进 UI。
- **命令 / 事件接线延后**：ADR-011 备注原计划 T-013 给 `CommandContext` 加入文档访问、
  ADR-001 备注计划 T-013 引入激活文档——本切片不引入这两项：它们与 T-015（命令面板）
  的可见收益绑定，提前引入「激活文档」语义会为最小切片增加一个状态维度（Rule 9）。
  键盘走 App → Bridge → Core 直连，事件驱动重渲染（ADR 总纲数据流不变）。
- **IME 内联组合模型**：组合文本不再作为独立尾行渲染，而是插入 displayText 光标处并
  对标记区间画下划线——光标、选区、IME 统一走同一条「文本 + 区间」渲染路径。
- **滚动是视图状态**：App 持有 `scrollY`（点），渲染按可视行窗口切行；
  Core 不持有像素坐标（ADR 总纲：Core 平台无关）。

## 审计

### Single Responsibility

`editor` 模块只回答「当前编辑会话」：文本修改 + 选区维护 + 历史记录。
不负责生命周期（DocumentManager）、不负责像素布局（App）、不负责命令分发（Command）。

### 循环依赖

`editor → buffer / selection / history / layout / error`（单向）；
`bridge → editor`；app → bridge → core。无反向。

## 新增 Public API

| API | 职责 |
| --- | --- |
| `Editor::new(buffer: Buffer) -> Editor` | 建立编辑会话（吸收 Buffer 所有权） |
| `editor.text() -> &str` | 当前文本（渲染数据源） |
| `editor.selection() -> Selection` | 当前选区（anchor / head） |
| `editor.type_text(&mut self, &str) -> Result<Option<EditOp>, BufferError>` | 替换选区并记录历史；`None` = 无变化（空输入不污染历史） |
| `editor.delete_backward(&mut self) -> Result<Option<EditOp>, BufferError>` | 删选区或光标前一个 UTF-8 字符 |
| `editor.move_cursor(&mut self, Movement, extend: bool)` | 光标移动；`extend` 为 Shift 扩展语义（ADR-007） |
| `editor.undo(&mut self) / redo(&mut self) -> Result<bool, BufferError>` | 历史栈应用 + 选区裁剪（ADR-008） |
| `editor.select_all(&mut self)` | 全选（0..len） |
| `editor.set_selection(&mut self, anchor, head)` | 任意区间选择（IME 替换 / 鼠标定位）；钳制到字符边界，不产生历史 |
| `Movement` 枚举 | Left / Right / Up / Down / LineStart / LineEnd / DocStart / DocEnd |

Bridge FFI 面（Rule 4）：`Editor` opaque + 16 个适配函数——文本 / 选区读取、
`type_text` / `delete_backward` / `undo` / `redo` / `select_all` / `set_selection`、
8 个方向移动函数。`Movement` 枚举**不桥接**（swift-bridge 0.1.59 对 already_declared
枚举需手写 FFI 胶水，ADR-014 备注），方向用独立函数机械适配；错误映射为消息字符串
（ADR-014 惯例），成功返回光标位置 / bool。

## 影响模块

- **core（新增 editor 模块）** — 唯一业务逻辑落点；Layout 在行移动 / 行起止时按需重建
  （ADR-009：编辑后重建）。
- **core/src/bridge.rs** — 新增 Editor / Movement 桥接面；Buffer / Layout 桥接不变。
- **app/** — `EditorModel` 从「末尾追加」改为「光标编辑」；新增 `LineLayout`
  （行 shaping → 光标 x / 选区矩形 / 标记下划线）；`TextRenderer` 拆分子功能避免超 300 行；
  `MetalView` 接入方向键 / 退格 / 滚轮 / 点击定位。

## 复杂度预算（宪法 Rule 9）

1. **增加了哪些复杂度？** 1 个 Core 模块（约 150 行）、1 个枚举、1 个 Bridge opaque、
   App 侧 1 个 LineLayout + 渲染扩展；0 抽象层 / 0 依赖。
2. **是否是永久性的？** Editor 是编辑会话的永久结构（T-019 Scratch、T-013 后所有编辑
   都走它）；Movement 枚举随命令面板（T-015）复用。
3. **有没有更简单但同样满足需求的方案？** 在 App 里直接拼 insert/delete/selection——
   最省事但把 UTF-8 边界、选区裁剪、历史一致性全部推到 UI 层，违反分层测试策略；
   不做 Up/Down（只左右）更小，但「光标」对编辑器语义不完整。Editor 是成本最低的完整闭环。

结论：1 模块 / 8 API / 0 抽象层，未触及红线。

## 备注

- **列语义**：Up/Down 保持「字节列」（当前 head 相对行首的字节偏移），CJK 宽字符下
  视觉列不完全精确；像素级列位置随 T-013 后渲染切片细化。

  v1.1 备注（T-035，BUG-008）：字节列目标必须 `floor_char_boundary` 钳制到字符
  边界——「字节列」是列度量语义，不代表允许光标停在多字节字符内部；ADR-005 的
  UTF-8 安全底线优先于列精确度。属性测试自 T-035 起将 Up/Down 纳入差分。
- **延后项**：光标闪烁、平滑滚动、鼠标拖选在切片内做最小版（静态光标 / 点滚动 /
  点击定位+拖选扩展）；CommandContext 文档访问与激活文档（ADR-001 / ADR-011 备注）
  随 T-015 命令面板。
- **UTF-16 ↔ UTF-8 换算放 App**：IME `replacementRange` 是 UTF-16 语义，换算为
  Buffer 字节偏移后调用 Core；换算测试落在 EditorModel。
