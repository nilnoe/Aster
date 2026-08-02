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
- feat(core)：Selection 模型（T-003，ADR-007）——`anchor` + `head` 字节偏移，光标即 head，10 个契约测试
  - [docs/glossary.md](../docs/glossary.md) — 术语表
  - [ARCHITECTURE.md](../ARCHITECTURE.md) — 架构总览
  - [WORKFLOW.md](../WORKFLOW.md) — 新增 Commit Message 约定（Conventional Commits）
