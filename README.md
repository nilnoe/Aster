# Aster

一个真正属于 macOS 的、极简但高度可编程的编辑器。

**核心信条：** 我打开的是一个 Buffer，而不是一个 IDE。

**当前阶段：** Beta（版本模板 `Beta V0.0.0`）；首个正式版为 `V1.0.0`。

## 文档体系

项目文档是一条完整链条，环环相扣：

| 文档 | 作用 | 位置 |
| --- | --- | --- |
| 宪法 | 不可违反的原则，优先级最高 | [docs/constitution.md](docs/constitution.md) |
| ADR | 架构决策记录 | [ADR.md](ADR.md) + [docs/adr/README.md](docs/adr/README.md) |
| 流程 | 垂直切片开发管线 | [WORKFLOW.md](WORKFLOW.md) |
| 构建 | 前置要求与命令 | [DEVELOPING.md](DEVELOPING.md) |
| 路线 | 开发路线 TODO | [docs/roadmap.md](docs/roadmap.md) |
| 变迁 | 版本变更记录 | [docs/changelog.md](docs/changelog.md) |
| 架构 | 分层与数据流 | [ARCHITECTURE.md](ARCHITECTURE.md) |
| 术语 | 领域词汇定义 | [docs/glossary.md](docs/glossary.md) |
| 性能 | 基准与基线 | [docs/benchmarks.md](docs/benchmarks.md) |
| 测试 | 分层测试策略 | [docs/testing.md](docs/testing.md) |
| 发布 | 版本与发布流程 | [docs/release.md](docs/release.md) |
| 依赖 | 依赖维护政策 | [docs/dependencies.md](docs/dependencies.md) |
| 规模 | 代码量预算与精简触发 | [docs/scale.md](docs/scale.md) |
| 经验 | 项目记忆与踩坑记录 | [docs/experience.md](docs/experience.md) |
| Bug 流程 | 缺陷处理管线 | [docs/bug-workflow.md](docs/bug-workflow.md) |
| Bug 登记 | 缺陷编号与状态 | [docs/bugs.md](docs/bugs.md) |
| 约定 | Agent 执行约定 | [AGENTS.md](AGENTS.md) |
| 许可 | MIT | [LICENSE](LICENSE) |
| 安全 | 漏洞报告与信任模型 | [SECURITY.md](SECURITY.md) |
| CI | 机械质量门禁（Rust / Swift） | [.github/workflows/](.github/workflows/) |

链条关系：**宪法约束一切 → ADR 记录决策 → Workflow 规定怎么执行 → Roadmap 决定下一步做什么 → Changelog 记录已经做了什么 → AGENTS 保证以上全部被遵守。**
