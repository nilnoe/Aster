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
- `ARCHITECTURE.md` — 架构总览：分层、数据流、垂直切片的插入点。
- `docs/adr/README.md` — ADR 索引与模板。
- `docs/glossary.md` — 术语表：领域词汇的权威定义。
- `docs/benchmarks.md` — 性能基线记录。
- `docs/bug-workflow.md` — 缺陷处理流程：Bug 必须按此管线修复。
- `docs/bugs.md` — 缺陷登记表：Bug 报告必须在此登记编号。
- `DEVELOPING.md` — 构建与运行；目标环境仅最新 macOS（ADR-002）。
- `docs/testing.md` — 分层测试策略。
- `docs/release.md` — 发布流程。
- `docs/dependencies.md` — 依赖维护政策。
- `docs/scale.md` — 规模预算：单文件 / 模块 / 总量上限与精简触发条件。
- `SECURITY.md` — 信任模型与漏洞报告。
- `.github/workflows/` — CI 机械门禁（Rust / Swift 双作业，按路径触发）。
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
- **注释：** 宪法 Rule 10——注释必须详尽且有决策依据，回答"为什么"，禁止为注释而注释；有宪法 / ADR 依据的必须引用编号。
- **复用优先：** 宪法 Rule 11——禁止重复造轮子；标准库 / 系统能力 > 成熟开源 > 自研；自研必须有证明。
- **宪法不可自行修改：** Agent 不得直接修改 `docs/constitution.md`；需要修订时先向用户提出建议，获得确认后执行。
- **CI 强制：** PR 必须通过 GitHub Actions 全部作业（宪法 Rule 6 的机械执行）。
- **平台与安全约束：** 仅支持最新 macOS（ADR-002）；插件默认信任（ADR-003）；默认无遥测，崩溃上报需显式开启（ADR-004）。
- **规模预算：** 宪法 Rule 12——单文件 ≤ 300 行、禁上帝文件、逻辑模块 ≤ 1,200 行、Core ≤ 20k / Swift ≤ 5k；扩容需 ADR 与用户确认；重复出现三处必须提取或复用。
- **版本：** 现阶段 Beta，模板 `Beta V0.0.0`——补丁递增末位、功能递增中间位、首位恒为 0；首个正式版为 `V1.0.0`（见 docs/release.md）。
- **Benchmark 是常态：** 每个切片至少建立或刷新一次性能基线，涉及 ADR Performance Goals 的切片必须给出量化对比。
- **Docs 是 Commit 的一部分：** 未更新文档的切片不算完成（含 Roadmap 状态与 Changelog）。
- **违反 ADR 即停止：** 如果任务要求的行为违背 ADR 已接受的决策，先停下并向用户说明，不要擅自实现。
- **反转 Accepted 决策需要用户确认：** 可以提出 ADR 修订建议，但改变已接受决策前必须获得用户同意。
