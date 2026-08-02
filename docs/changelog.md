# Changelog — 版本变迁记录

本文件记录项目的版本与每次重要变更。

**版本策略：** 现阶段为 Beta，模板 `Beta V0.0.0`。小补丁递增末位，功能开发递增中间位（末位归零），首位恒为 0。尚未发布的变更维护在 `[Unreleased]`，发布时归档为 `[Beta V0.x.y]`。首个正式版为 `V1.0.0`。

**链接规则：** 每条变更必须链接到对应的 ADR 与 Roadmap 切片；反向可追溯。

---

## [Unreleased]

### Added — 2026-08-02

- 项目启动：文档体系建立
  - [docs/constitution.md](../docs/constitution.md) — 项目宪法（10 条不可违反原则）
  - [docs/adr/ADR-001-document-manager.md](../docs/adr/ADR-001-document-manager.md) — DocumentManager（Status: Proposed）
  - [WORKFLOW.md](../WORKFLOW.md) — 11 步垂直切片开发管线
  - [docs/roadmap.md](../docs/roadmap.md) — 开发路线 TODO
  - [docs/changelog.md](../docs/changelog.md) — 本文件
  - [AGENTS.md](../AGENTS.md) — 执行约定
- [docs/constitution.md](../docs/constitution.md) — Version 1.1：新增 Rule 10（注释必须有决策依据）与修订流程
- [docs/constitution.md](../docs/constitution.md) — Version 1.2：新增 Rule 11（禁止重复造轮子 / Reuse First）
- [docs/constitution.md](../docs/constitution.md) — Version 1.3：修订 Rule 3（上帝文件禁令）+ 新增 Rule 12（规模预算：单文件 / 模块 / 总量上限、扩容与精简条件、封装与接口）
- [docs/scale.md](../docs/scale.md) — 规模预算执行细则（硬性上限表、预警 80%、扩容 ≤25%、精简五触发条件）
- [docs/experience.md](../docs/experience.md) — 经验沉淀：项目现状速览、工作方式、Rust/Clippy/测试经验、架构决策速查、踩坑记录
- 新增 ADR：
  - [ADR-002](../docs/adr/ADR-002-macos-support.md) — macOS 支持策略：仅最新版，零兼容负担（Accepted）
  - [ADR-003](../docs/adr/ADR-003-plugin-trust.md) — 插件安全模型：默认信任，第一阶段不沙箱（Accepted）
  - [ADR-004](../docs/adr/ADR-004-logging-crash.md) — 日志与崩溃上报：os_log + tracing，默认无遥测（Accepted）
- 许可：新增 MIT License（Copyright 2026 nilnoe）
- 文档体系扩展：
  - [docs/adr/README.md](../docs/adr/README.md) — ADR 索引（编号规则、状态机、触发规则）
  - [docs/adr/_template.md](../docs/adr/_template.md) — ADR 模板
  - [.github/PULL_REQUEST_TEMPLATE.md](../.github/PULL_REQUEST_TEMPLATE.md) — PR 模板（宪法 Rule 6 / 9 强制项）
  - [docs/benchmarks.md](../docs/benchmarks.md) — 性能基线记录
  - [docs/bug-workflow.md](../docs/bug-workflow.md) — 缺陷处理流程（根因分类 + 回归测试先行）
  - [docs/bug-workflow.md](../docs/bug-workflow.md) — Bug Report 阶段新增 Bug ID（必填）与 Upstream Reference（可选，含版本与访问日期）
  - [docs/bugs.md](../docs/bugs.md) — 缺陷登记表（内部登记）
- 工程基础设施：
  - [.github/workflows/ci-rust.yml](../.github/workflows/ci-rust.yml) + [ci-swift.yml](../.github/workflows/ci-swift.yml) — CI：Rust 与 Swift 门禁机械执行（按路径触发）
  - [.github/workflows/ci-rust.yml](../.github/workflows/ci-rust.yml) — 新增 Scale Budget 检查（单文件 ≤ 300 行、core 总量 ≤ 20k）
  - [.github/PULL_REQUEST_TEMPLATE.md](../.github/PULL_REQUEST_TEMPLATE.md) — 新增规模预算必填项
  - [DEVELOPING.md](../DEVELOPING.md) — 构建与运行
  - [docs/testing.md](../docs/testing.md) — 分层测试策略
  - [docs/release.md](../docs/release.md) — 发布流程（Trunk-based + 发布清单）
  - [docs/dependencies.md](../docs/dependencies.md) — 依赖维护政策（新增 / 升级 / 安全）
  - [SECURITY.md](../SECURITY.md) — 漏洞报告与信任模型
  - [docs/roadmap.md](../docs/roadmap.md) — 新增复审政策与 ADR-002 硬约束
- [docs/release.md](../docs/release.md) — 版本策略：Beta V0.0.0 模板（末位补丁 / 中间位功能 / 首位恒 0），首个正式版 V1.0.0
- [docs/roadmap.md](../docs/roadmap.md) — 切片编号规则（T-XXX）与编号表，Commit 必须引用 Task 与 ADR
- feat(core)：Buffer 最小模型（T-001，ADR-005）——`Buffer` / `BufferId` / `BufferError`，UTF-8 字符边界安全，13 个契约测试
- [ADR-006](../docs/adr/ADR-006-data-structures.md) — 核心数据结构决策矩阵：已确定（Selection / Undo 栈 / 注册表 / 存储决策机制）+ 未确定（存储算法 / 行索引 / 多光标 / mmap 等，含原因）
- [ADR-001](../docs/adr/ADR-001-document-manager.md) — 状态 Proposed → Accepted：确定 `open` / `close` 签名与支撑类型（`DocumentSource` / `DocumentManagerError`）；激活状态延迟到 T-013；SQLite 落盘延迟到 T-009 / T-021
- feat(core)：DocumentManager `open` / `close`（T-002，ADR-001）——注册表 + 生命周期；`DocumentSource`（Disk / Scratch）；错误可见（ADR-004）；8 集成 + 5 单元测试
- feat(core)：Undo / Redo（T-004，ADR-008）——`History` + `EditOp`（inverse-operation 栈）；相邻 Insert 合并；失败时栈不变；11 个契约测试
- feat(core)：Layout 逻辑行模型（T-005，ADR-009）——`Layout::build` / `line_count` / `line_range` / `line_at`；不可变快照索引；10 个契约测试
- [ADR-006](../docs/adr/ADR-006-data-structures.md) — 行索引与软换行从未确定改为已确定（v1 不可变索引、无软换行；替换触发点 T-020）
- feat(core)：Selection 模型（T-003，ADR-007）——`anchor` + `head` 字节偏移，光标即 head，10 个契约测试
  - [docs/glossary.md](../docs/glossary.md) — 术语表
  - [ARCHITECTURE.md](../ARCHITECTURE.md) — 架构总览
  - [WORKFLOW.md](../WORKFLOW.md) — 新增 Commit Message 约定（Conventional Commits）
- [ADR-010](../docs/adr/ADR-010-theme-model.md) — Theme 模型与 Theme DSL（固定四角色 + `rgba()` 语法，Accepted）
- feat(core)：Theme 模型与 Theme DSL 解析（T-006，ADR-010）——`Color` / `Theme` / `ThemeError`；`Theme::parse` 行级解析；12 个契约测试
- [ADR-011](../docs/adr/ADR-011-command-event.md) — Command 系统与 Event 总线（std `Fn` 注册表 + 订阅 id 总线，Accepted）
- [ADR-006](../docs/adr/ADR-006-data-structures.md) — 「命令表 / 事件总线结构」从未确定改为已确定（ADR-011 决策）
- feat(core)：Command 系统与 Event 总线（T-007，ADR-011）——`CommandRegistry` / `CommandContext` / `EventBus` / `Event::BufferEdited`；9 个契约测试
- [ADR-012](../docs/adr/ADR-012-lua-runtime.md) — Lua Runtime（mlua 0.12，lua54 + vendored）与 Plugin API（Accepted）
- [ADR-011](../docs/adr/ADR-011-command-event.md) — 修订 v1.1：处理器签名改为可失败，`CommandError` 新增 `HandlerFailed`（T-008 提前触发）
- feat(core)：Lua Runtime 与 Plugin API（T-008，ADR-012）——`LuaRuntime`（load / export_commands / export_subscribers / get_global）；Lua 侧 `aster.register_command` / `aster.subscribe`；6 个契约测试；新增依赖 mlua（Rule 7 / 8 论证见 ADR-012）
- [ADR-013](../docs/adr/ADR-013-sqlite-store.md) — SQLite 存储层（rusqlite 0.40 bundled，scratch + session 两表，Accepted）
- [ADR-001](../docs/adr/ADR-001-document-manager.md) — 备注更新：存储层由 T-009 交付，Scratch 工作流接线在 T-019、Session / Crash Recovery 编排在 T-021
- feat(core)：SQLite 存储层（T-009，ADR-013）——`Store`（scratch upsert / session 事务整表替换）；`SessionDocument`；9 个契约测试；新增依赖 rusqlite（Rule 7 / 8 论证见 ADR-013）
- [ADR-014](../docs/adr/ADR-014-swift-bridge-spike.md) — Swift Bridge 接入 spike（swift-bridge 0.1.59 + swift-bridge-build，Accepted）
- feat(bridge)：swift-bridge 接入 spike（T-010，ADR-014）——core `bridge` 模块（Buffer / BufferId 桥接面 + `buffer_insert` 适配）；bridge/ Swift Package（systemLibrary C 模块 + staticlib 链接）；3 个 XCTest 契约测试；新增依赖 swift-bridge、swift-bridge-build（Rule 7 / 8 论证见 ADR-014）
- ci(swift)：CI-Swift 作业改为先跑 `bridge/build.sh` 再 lint / test（生成绑定 + staticlib 链接进测试）
- [ADR-015](../docs/adr/ADR-015-appkit-shell.md) — AppKit 壳（程序化启动、最小菜单集、版本单一来源，Accepted）
- feat(app)：AppKit 壳（T-011，ADR-015）——`main.swift` 程序化启动 + 空白 NSWindow + 最小菜单（App / Edit / Window）；关于面板版本号经 Bridge 来自 Core；4 个 XCTest（含 App → Bridge → Core 垂直线程）；Swift App 规模预算自此生效
- ci(swift)：CI-Swift 增加 app 包 lint 与 test
