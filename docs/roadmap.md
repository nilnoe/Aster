# Roadmap — 开发路线 TODO

每个条目都是一个垂直切片，必须完整执行 [WORKFLOW.md](../WORKFLOW.md) 的管线。

状态标记：`[ ]` 未开始 · `[~]` 进行中 · `[x]` 完成

切片完成时：更新本文件状态 → 更新 [docs/changelog.md](changelog.md) → 提交。

---

## Phase 0 — 项目基础

- [x] 文档体系建立（Constitution / ADR / Workflow / Roadmap / Changelog / AGENTS）
- [x] 工程基础设施文档（CI / DEVELOPING / 测试策略 / 发布流程 / 依赖政策 / 安全）
- [x] T-001 Rust Core 骨架：crate 结构 + Buffer 最小模型 + 测试（Red → Green）
- [x] T-002 DocumentManager：`open` / `close`（注册表 + 生命周期，ADR-001）

## Phase 1 — Core 编辑内核

- [x] T-003 Selection 模型（anchor / head 字节偏移，光标即 head）
- [x] T-004 Undo / Redo（inverse-operation 栈 + 相邻 Insert 合并，ADR-008）
- [x] T-005 Layout：逻辑行模型（行号 ↔ 字节区间 ↔ 偏移，ADR-009）
- [x] T-006 Theme：主题模型 + Theme DSL
- [x] T-007 Command 系统 + Event 总线
- [x] T-008 Lua Runtime（mlua）接入 + Plugin API
- [x] T-009 SQLite 存储：Scratch / Session / Crash Recovery

## Phase 2 — 系统集成

- [x] T-010 swift-bridge 接入（spike，验证 API 面）
- [x] T-011 AppKit 壳：Window + Menu + 空白视图
- [x] T-012 Metal 渲染管线：文本渲染 spike（CoreText + IME + CJK）
- [x] T-013 编辑循环：键盘输入、光标、滚动、选择
- [ ] T-014 剪贴板：复制 / 剪切 / 粘贴 + Edit 菜单接线（系统 NSPasteboard；ADR-018）
- [ ] T-015 拖放与文档选择器：文件拖入 Buffer、NSOpenPanel 打开（ADR-018）

> 深浅色跟随系统不在本阶段：固定深色启动态，主题可编程能力由 Lua 提供（ADR-018）。

## Phase 3 — 渲染与编辑打磨（ADR-018 方向）

- [ ] T-016 渲染质量：sRGB + gamma 校正（抗锯齿边缘与系统渲染对齐）
- [ ] T-017 光标：闪烁与可见性（BUG-002 修复随缺陷流程）
- [ ] T-018 编辑细节：DeleteForward + 词级移动（Option+←/→）
- [ ] T-019 选择打磨：双击选词 / 三击选行
- [ ] T-020 滚动与 IME：平滑滚动 / 候选框定位精确化
- [ ] T-021 性能基准体系：criterion + 稳定测量（穿插执行，不阻塞功能切片；ADR-006 存储决策的前置）

## Phase 4 — Overlay 生态

- [ ] T-022 Command Palette overlay
- [ ] T-023 Search overlay
- [ ] T-024 StatusBar overlay
- [ ] T-025 Shell overlay（PTY + 模糊背景）
- [ ] T-026 Scratch 工作流：`Cmd+N` → 自动保存 → Attach Path

## Phase 5 — 稳定与发布

- [ ] T-027 Crash Recovery 与 Session 恢复
- [ ] T-028 首个正式版 V1.0.0（暂不排期，Beta 优先）

## Task 编号规则

- 每个切片一个编号：`T-XXX`，按 Phase 顺序递增，不重复使用。
- Commit 必须引用 Task 编号与对应 ADR（如 `feat(core): Buffer 最小模型 (T-001, ADR-005)`）。
- 新增 / 合并 / 删除切片时，重新编号并更新本文件，同时记录到 Changelog。

---

顺序仅供参考，具体切片可能因 Analysis 阶段的新证据调整；任何调整必须先反映在 ADR 中。

当前下一步：**T-017 光标（BUG-002 修复 + 闪烁）→ 随后 T-014 剪贴板**。

## 复审政策

- 每季度或每个里程碑完成后复审一次。
- 复审输出：新增 / 调整 / 删除切片；任何调整先写 ADR，再改本文件。
- 硬约束：只支持最新 macOS（ADR-002），不新增兼容性切片。
