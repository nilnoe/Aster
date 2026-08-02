# AGENTS.md

这是本仓库所有 agent 的工作约定。每次任务开始时必须阅读本文件，并在整个会话中遵守。

## Project

本项目是一个原生 macOS 编辑器：极简、Buffer 为中心、高度可编程。

必读文档：

- `docs/constitution.md` — 项目宪法，不可违反的原则，优先级最高。
- `ADR.md` + `docs/adr/` — 架构决策记录，所有技术决策的权威来源。
- `WORKFLOW.md` — 开发管线，所有任务的强制执行流程。
- `docs/roadmap.md` — 开发路线 TODO：每个任务从这里选取，完成时更新其状态。
- `docs/changelog.md` — 版本变迁记录：每个切片完成时更新。
- `README.md` — 文档体系索引。

核心约束（来自 ADR）：

- 只支持 macOS：Swift + AppKit + Metal + CoreText。不做跨平台。
- Rust Core 必须平台无关，不允许依赖 AppKit / SwiftUI / NSView / NSWindow。
- Buffer 是第一公民；Sidebar、Terminal、Search、Command Palette 等所有 UI 都是可选 Overlay。
- UI 用 Swift + AppKit，渲染用 Metal，插件用 Lua (mlua)，存储用 SQLite，桥接用 swift-bridge。
- Core 必须保持稳定。Plugin 可以增加 UI / Command / Event / Renderer，但不能修改 Core。

## Mandatory Workflow

每个任务都是一个最小垂直切片，必须完整执行 `WORKFLOW.md` 中的管线：

Task → Analysis → Architecture → Test Design → Implementation → Format → Lint → Audit → Benchmark → Documentation → Commit

规则：

- **Minimal：** 每个切片只交付可演示能力所需的最小改动，不多做。
- **Vertical：** 切片必须穿透 Swift UI、Bridge、Rust Core、测试，不按水平层推进。
- **ADR First：** 先记录决策，再实现。如果 Analysis 与既有决策冲突，先标记，获得用户确认后再更新 ADR。
- **Tests First：** Red → Green。UI 保持薄，可测试的逻辑尽可能落在 Rust Core 内。
- **Quality Gates：** `cargo fmt`、`cargo clippy`、`cargo test` 必须全部通过，才能进入 Architecture Audit。
- **Constitution 优先：** `docs/constitution.md` 的规则不可违反；任何 Commit 前必须通过宪法 Rule 6 的全部质量门禁（含 `swift-format`、`swift test`）。
- **复杂度预算：** 每个 PR 必须回答宪法 Rule 9 三问（新增复杂度、是否永久、更简单方案）；Audit 阶段拒绝为小功能堆叠抽象层 / 模块 / 公共接口。
- **Benchmark 是常态：** 每个切片至少建立或刷新一次性能基线，涉及 ADR Performance Goals 的切片必须给出量化对比。
- **Docs 是 Commit 的一部分：** 未更新文档的切片不算完成（含 Roadmap 状态与 Changelog）。
- **违反 ADR 即停止：** 如果任务要求的行为违背 ADR 已接受的决策，先停下并向用户说明，不要擅自实现。
- **反转 Accepted 决策需要用户确认：** 可以提出 ADR 修订建议，但改变已接受决策前必须获得用户同意。
