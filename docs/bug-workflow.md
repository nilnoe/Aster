# Bug Workflow — 缺陷处理流程

缺陷是特殊类型的垂直切片：一条 Bug 对应一个最小修复切片，使用本流程，而不是常规 [WORKFLOW.md](../WORKFLOW.md) 管线（或视为其专用变体）。

## Pipeline

```text
Bug Report
    │
    ▼
Reproduce
    │
    ▼
Root Cause Analysis
    │
    ├── Design Bug?
    ├── Spec Bug?
    ├── Test Missing?
    ├── Implementation Bug?
    └── Architecture Bug?
    │
    ▼
Write Regression Test（Red）
    │
    ▼
AI Fix
    │
    ▼
All Tests
    │
    ▼
Architecture Audit
    │
    ▼
Documentation Update
    │
    ▼
Merge
```

## 各阶段要求

### 1. Bug Report

记录：**Bug ID**（必填，自增，登记于 [docs/bugs.md](bugs.md)）、现象、复现步骤、期望行为、实际行为、环境（版本 / macOS / 硬件）、**Upstream Reference**（可选）。

缺少复现步骤的 Bug 不进入处理。

### 2. Reproduce

在本地复现，排除环境因素。无法复现时停下并反馈，补充信息后再继续。

### 3. Root Cause Analysis

定位根因并分类，分类结论必须记录：

- **Design Bug** — 设计决策本身错误 → 修订对应 ADR，再修代码。
- **Spec Bug** — 需求 / 规格定义错误 → 修正规格文档，再修代码。
- **Test Missing** — 行为未被测试覆盖 → 补测试；这可能就是修复本身。
- **Implementation Bug** — 实现与设计不一致 → 修正实现。
- **Architecture Bug** — 违反宪法 / ADR 或引入违规耦合 → 走 Architecture Audit，必要时修订 ADR。

若根因涉及第三方组件或社区已知问题，补记 **Upstream Reference**，格式：`组件名 版本 (upstream #编号 / URL)`，并注明访问日期。

### 4. Write Regression Test（Red）

先写回归测试，确认它能复现 Bug 并 **Fail**。不能稳定复现的测试不算完成。

### 5. AI Fix

最小修复（宪法 Rule 9：不增加无谓复杂度）。

根因是 Design / Spec / Architecture 时，先改文档与决策，再改代码。

### 6. All Tests

全量测试 + 质量门禁（宪法 Rule 6）：

```text
cargo fmt
cargo clippy
cargo test
swift-format
swift test
```

### 7. Architecture Audit

确认修复未破坏 ADR、未引入隐藏耦合、未超出切片范围、未触碰复杂度预算红线。

### 8. Documentation Update

更新 [docs/changelog.md](changelog.md) 的 `Fixed` 区，注明根因分类与回归测试；必要时更新 ADR / Roadmap / 术语表。

### 9. Merge

走 PR 模板（`.github/PULL_REQUEST_TEMPLATE.md`）。Commit 使用 `fix(scope): ...` 并引用 Bug 编号。

## Rules

- 一条 Bug 一个切片，不做捆绑修复。
- 回归测试先红后绿；修复后全量测试必须保持绿。
- 根因分类必须写入 Changelog。定期统计分类分布，哪类 Bug 最多就优先加固哪一环。
- Architecture Bug 反复出现，说明审计或测试环节有缺口，应回到 WORKFLOW 修复流程本身。
- **Bug ID 必填，联网检索非必填：** 检索仅当根因涉及第三方组件或社区已知问题时进行，禁止为每个 Bug 强行搜索。
- **Upstream Reference 必须含组件版本与访问日期：** 同一 Issue 可能已在更高版本修复，版本决定"升级依赖"还是"本地 workaround"。
- 当前使用仓库内 [docs/bugs.md](bugs.md) 登记；若改用 GitHub Issues，直接复用 Issue 编号作为 Bug ID。
