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
- [x] T-015 拖放与文档选择器：文件拖入 Buffer、NSOpenPanel 打开；接线 DocumentManager `open`（Disk 源，ADR-001）（ADR-018）

> 深浅色跟随系统不在本阶段：固定深色启动态，主题可编程能力由 Lua 提供（ADR-018）。

## Phase 3 — 渲染与编辑打磨（ADR-018 / ADR-019 方向）

- [ ] T-016 渲染质量：sRGB + gamma 校正（抗锯齿边缘与系统渲染对齐）；渲染颜色接入 Core Theme（ADR-010，固定深色启动主题）
- [x] T-017 光标：闪烁与可见性（BUG-002 修复随缺陷流程）
- [x] T-018 水平滚动：长行平移可读，光标横向可见性（ADR-019）
- [ ] T-019 软换行：用户可选、默认关闭的视觉折行（ADR-019）
- [ ] T-020 编辑细节：DeleteForward + 词级移动（Option+←/→）
- [ ] T-021 选择打磨：双击选词 / 三击选行
- [ ] T-022 滚动与 IME：平滑滚动 / 候选框定位精确化
- [x] T-023 性能基准体系：criterion + 稳定测量（ADR-006 数据结构决策的前置门禁，宪法 Rule 16；优先于任何存储替换切片，穿插于渲染 / 编辑切片之间执行）

## Phase 4 — Overlay 生态

- [ ] T-024 Command Palette overlay：Command / Event 接线进编辑循环（ARCHITECTURE 数据流跑通，ADR-011）+ Lua 插件加载（命令注册，ADR-012）与主题可编程入口（ADR-018）
- [ ] T-025 Search overlay
- [ ] T-026 StatusBar overlay
- [ ] T-027 Shell overlay（PTY + 模糊背景）
- [ ] T-028 Scratch 工作流：`Cmd+N` → 自动保存 → Attach Path；接线 Store scratch 与 DocumentManager（Scratch 源，ADR-001 / ADR-013）

## Phase 5 — 稳定与发布

- [ ] T-029 Crash Recovery 与 Session 恢复；接线 Store session（ADR-013）
- [ ] T-030 首个正式版 V1.0.0（暂不排期，Beta 优先）
- [ ] T-031 日志与错误可见性：os_log（App）+ tracing（Core）接线，ADR-004 落地（宪法 Rule 13 闭环）
- [x] T-032 测试与审计加固：proptest 属性测试（Buffer / Editor / Layout 不变量）+ 审计记录制度（docs/audits.md，ADR-022）
- [x] T-033 fuzz 扩展 + 基准回归告警：属性空间扩展到 emoji / CJK / 换行 / 组合字符（CI `PROPTEST_CASES=3000` 专项运行）；criterion 基线提交 + CI 阈值对比作业（ADR-021 v1.1，反转「CI 不跑」经用户确认）

## Phase 6 — 复审整改（2026-08-02 全仓审查，I-001 ~ I-008）

> 审查结论与证据见 [docs/issues.md](issues.md)；按严重度顺序修复：P0 → P2 清理 → P1 功能 → 门禁加固。

- [ ] T-034 审查问题登记：新建 docs/issues.md 并同步索引 / Roadmap / Changelog（I-001~I-008）
- [x] T-035 Up/Down 光标 UTF-8 边界修复（I-001，BUG-008，ADR-005 底线）+ Up/Down 纳入属性测试差分
- [x] T-036 存量清理：删除无消费者 `Selection::clamp`（I-004）、校正文档计数漂移与 T-032 审计回填（I-005）、核验 .DS_Store 未入库并清理工作树残留（I-006 误报纠正）
- [x] T-037 Disk 保存切片：File「保存」Cmd+S 写回绑定路径（I-002，ADR-023；dirty 标题指示 + 关闭保护）
- [ ] T-038 渲染数据路径重构：缓存行结构、每帧单次 shaping、视口切行，消除每帧 O(n)（I-003）
- [ ] T-039 审计与门禁加固：审计留痕机械检查（Rule 15 扩展）+ CI-Release 与日常 CI 门禁对齐（I-007 / I-008）

## Task 编号规则

- 每个切片一个编号：`T-XXX`，按 Phase 顺序递增，不重复使用。
- Commit 必须引用 Task 编号与对应 ADR（如 `feat(core): Buffer 最小模型 (T-001, ADR-005)`）。
- 新增 / 合并 / 删除切片时，重新编号并更新本文件，同时记录到 Changelog。

---

顺序仅供参考，具体切片可能因 Analysis 阶段的新证据调整；任何调整必须先反映在 ADR 中。

当前下一步：**T-014 剪贴板（NSPasteboard，ADR-018 方向）→ 随后 T-019 软换行**。

## 复审政策

- 每季度或每个里程碑完成后复审一次。
- 复审输出：新增 / 调整 / 删除切片；任何调整先写 ADR，再改本文件。
- 硬约束：只支持最新 macOS（ADR-002），不新增兼容性切片。
