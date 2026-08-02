# Roadmap — 开发路线 TODO

每个条目都是一个垂直切片，必须完整执行 [WORKFLOW.md](../WORKFLOW.md) 的管线。

状态标记：`[ ]` 未开始 · `[~]` 进行中 · `[x]` 完成

切片完成时：更新本文件状态 → 更新 [docs/changelog.md](changelog.md) → 提交。

---

## Phase 0 — 项目基础

- [x] 文档体系建立（Constitution / ADR / Workflow / Roadmap / Changelog / AGENTS）
- [ ] Rust Core 骨架：crate 结构 + Buffer 最小模型 + 测试（Red → Green）
- [ ] ADR-001 实现：DocumentManager `open` / `close`（依赖 Buffer 骨架）

## Phase 1 — Core 编辑内核

- [ ] Buffer：文本存储 + Cursor + Selection
- [ ] Undo / Redo
- [ ] Layout：行布局引擎
- [ ] Theme：主题模型 + Theme DSL
- [ ] Command 系统 + Event 总线
- [ ] Lua Runtime（mlua）接入 + Plugin API
- [ ] SQLite 存储：Scratch / Session / Crash Recovery

## Phase 2 — 系统集成

- [ ] swift-bridge 接入（spike，验证 API 面）
- [ ] AppKit 壳：Window + Menu + 空白视图
- [ ] Metal 渲染管线：文本渲染 spike（CoreText + IME + CJK）
- [ ] 编辑循环：键盘输入、光标、滚动、选择
- [ ] 系统集成：深浅色跟随、拖放、剪贴板、文档选择器

## Phase 3 — Overlay 生态

- [ ] Command Palette overlay
- [ ] Search overlay
- [ ] StatusBar overlay
- [ ] Shell overlay（PTY + 模糊背景）
- [ ] Scratch 工作流：`Cmd+N` → 自动保存 → Attach Path

## Phase 4 — 打磨与发布

- [ ] 性能基准体系：冷启动 / 打开文档 / 渲染，基线记录
- [ ] Crash Recovery 与 Session 恢复
- [ ] 首个公开版本 1.0.0

---

顺序仅供参考，具体切片可能因 Analysis 阶段的新证据调整；任何调整必须先反映在 ADR 中。

当前下一步：**Rust Core 骨架（Buffer 最小模型）**。

