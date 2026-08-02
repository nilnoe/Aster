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
- [ ] T-004 Undo / Redo
- [ ] T-005 Layout：行布局引擎
- [ ] T-006 Theme：主题模型 + Theme DSL
- [ ] T-007 Command 系统 + Event 总线
- [ ] T-008 Lua Runtime（mlua）接入 + Plugin API
- [ ] T-009 SQLite 存储：Scratch / Session / Crash Recovery

## Phase 2 — 系统集成

- [ ] T-010 swift-bridge 接入（spike，验证 API 面）
- [ ] T-011 AppKit 壳：Window + Menu + 空白视图
- [ ] T-012 Metal 渲染管线：文本渲染 spike（CoreText + IME + CJK）
- [ ] T-013 编辑循环：键盘输入、光标、滚动、选择
- [ ] T-014 系统集成：深浅色跟随、拖放、剪贴板、文档选择器

## Phase 3 — Overlay 生态

- [ ] T-015 Command Palette overlay
- [ ] T-016 Search overlay
- [ ] T-017 StatusBar overlay
- [ ] T-018 Shell overlay（PTY + 模糊背景）
- [ ] T-019 Scratch 工作流：`Cmd+N` → 自动保存 → Attach Path

## Phase 4 — 打磨与发布

- [ ] T-020 性能基准体系：冷启动 / 打开文档 / 渲染；基准数据驱动文本存储选择（ADR-006）
- [ ] T-021 Crash Recovery 与 Session 恢复
- [ ] T-022 首个正式版 V1.0.0（暂不排期，Beta 优先）

## Task 编号规则

- 每个切片一个编号：`T-XXX`，按 Phase 顺序递增，不重复使用。
- Commit 必须引用 Task 编号与对应 ADR（如 `feat(core): Buffer 最小模型 (T-001, ADR-005)`）。
- 新增 / 合并 / 删除切片时，重新编号并更新本文件，同时记录到 Changelog。

---

顺序仅供参考，具体切片可能因 Analysis 阶段的新证据调整；任何调整必须先反映在 ADR 中。

当前下一步：**Rust Core 骨架（Buffer 最小模型）**。

## 复审政策

- 每季度或每个里程碑完成后复审一次。
- 复审输出：新增 / 调整 / 删除切片；任何调整先写 ADR，再改本文件。
- 硬约束：只支持最新 macOS（ADR-002），不新增兼容性切片。
