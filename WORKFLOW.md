# Development Workflow

每次只做最小化实现，一次一个垂直切片（Vertical Slice）。

一个切片必须从 Task 贯穿到 Commit，不允许停在中间某个水平层。

缺陷处理使用独立流程：[docs/bug-workflow.md](docs/bug-workflow.md)。

## Pipeline

1. **Task** — 确定一个具体、有边界、可验收的垂直切片。明确验收标准与 Definition of Done。
2. **Analysis** — 调研选项、验证约束、识别风险，记录分析结论。若结论与既有 ADR 冲突，必须标记出来，不允许直接带病进入下一阶段。
   本阶段强制完成**冲突扫描**（T-070 治理纠偏，2026-08-03）：必须逐项回答并记录——
   - 本切片会触碰哪些既有子系统（保存状态机 / Frame / 窗口关闭退出流 / IME /
     渲染缓存 / 存储层 / 编辑内核）？
   - 对每个被触碰的子系统：为什么不会破坏既有语义？哪些既有回归必须跑通？
   - 涉及保存 / 恢复 / 关闭域的任何改动，必须先跑变异门禁（scripts/mutate.py）
     与全量 App 集成测试再进入实现；未扫描 = Analysis 未完成。
3. **Architecture** — 设计切片架构，并在本阶段完成所有必要的 ADR：
   - 新增 Public API → 必须有 ADR（宪法 Rule 4）
   - 新增抽象层（Trait / Protocol / 包装）→ 必须回答"为什么不能直接实现"并证明复杂度下降（宪法 Rule 1 / 2）
   - 新增依赖 / 第三方库 → 必须论证标准库不能解决，并生成 ADR（宪法 Rule 7 / 8）
   - 反转既有 Accepted 决策 → 必须获得用户确认
   - Accepted 且需代码落地的 ADR 必须在本发布周期内进入 Roadmap，或显式标记 Deferred（注明原因与复评条件）（宪法 Rule 13）
   - 新增 Public API 必须与真实调用方同一切片交付（宪法 Rule 14；spike 显式标注并在审计处置）
4. **Test Design** — 设计并编写测试，定义该切片的验收标准。运行测试，确认 **Fail（Red）**。
5. **Implementation** — 最小实现，让测试 **Pass（Green）**。随后 Refactor，测试保持 Pass。UI 保持薄，可测试的逻辑尽可能落在 Rust Core 内。
6. **Format** — `cargo fmt` + `swift-format`。
7. **Lint** — `cargo clippy`。
8. **Audit** — Architecture Audit：检查切片是否符合 ADR 与宪法——Core 是否稳定、是否有隐藏耦合、是否有超出切片范围的代码、是否有违规抽象、是否通过复杂度预算（宪法 Rule 9）与规模预算（宪法 Rule 12，见 [docs/scale.md](docs/scale.md)）；同时检查 ADR 闭环（Rule 13）与公共接口消费者（Rule 14）。审计结论必须写入 [docs/audits.md](docs/audits.md)（每切片一行，含违规与处置）；无记录的审计视为未执行。
9. **Benchmark** — 运行相关基准并与上一基线对比，记录结果。涉及 ADR Performance Goals（Cold Startup、Document Opening、Rendering）的切片必须给出量化对比；不涉及的切片也要刷新基线或记录"无显著影响"。涉及性能取舍的架构变更必须先建立可复现基线再动手（宪法 Rule 16）。
10. **Documentation** — 更新 ADR、README、docs、Roadmap 状态与 Changelog 中所有与本切片相关的部分。
11. **Commit** — 全量质量门禁通过（宪法 Rule 6）：`cargo fmt`、`cargo clippy`、`cargo test`、`swift-format`、`swift test`。全部通过才允许提交。Commit message 引用对应的 Task 与 ADR。

## Definition of Done

一个切片只有在满足全部条件时才允许 Commit：

- 测试全绿（Red → Green → Refactor 完成）
- 宪法 Rule 6 五项门禁全部通过
- Architecture Audit 无违规项
- 复杂度预算三问已回答并记录（宪法 Rule 9）
- 规模预算已检查（宪法 Rule 12：单文件 ≤ 300 行、无上帝文件、总量未超预算）
- Benchmark 已记录
- 文档已更新（含 Roadmap 状态与 Changelog）

## Commit Message 约定

- 使用 Conventional Commits：`type(scope): summary`。
- type：`feat` / `fix` / `docs` / `refactor` / `perf` / `test` / `chore`。
- 必须引用对应 Task（编号见 [docs/roadmap.md](docs/roadmap.md)）与 ADR 编号，例如：`feat(core): Buffer 最小模型 (T-001, ADR-005)`。
- 正文解释"为什么"，而非复述改动（宪法 Rule 10）。

## Rules

- **Minimal：** 每个切片只交付可演示能力所需的最小改动，不多做。
- **Vertical：** 切片必须穿透 Swift UI、Bridge、Rust Core、测试，而不是按层推进。
- **ADR First：** 先记录决策，再实现。
- **Testable：** 可测试的逻辑尽可能落在 Rust Core 内，通过 Bridge 暴露给测试。
- **Benchmark 是常态：** 每个切片至少建立或刷新一次性能基线；没有基线的性能断言不可信。
- **Docs 是 Commit 的一部分：** 未更新文档的切片不算完成。
- **Quality Gates：** 门禁全部通过是 Commit 的前提，不允许"先提交后补"。

下一个 Task 总是关键路径上最薄的下一个切片。
