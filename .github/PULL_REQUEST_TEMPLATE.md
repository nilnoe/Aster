# Pull Request

<!-- 每个 PR 必须完整填写。缺失任何必填项都会被拒绝。 -->

## 关联

- Task / Roadmap 条目：
- ADR：<!-- 新增 Public API / 抽象层 / 依赖 / 反转决策必须有 ADR -->

## 复杂度预算（宪法 Rule 9）

1. 这个改动增加了哪些复杂度？
2. 这些复杂度是否是永久性的？
3. 有没有更简单但同样满足需求的方案？

## 规模预算（宪法 Rule 12）

- 新增 / 修改 / 删除行数：
- 是否存在超过 300 行的文件：
- 是否触发精简条件（Rule of Three / 预警线 / 冗余代码）：

## 审计

- 是否违反 Single Responsibility：
- 是否增加循环依赖：
- 新增 Public API 数量：
- 影响模块：
- 行为证据（实际运行的测试 / 基准 / 验证的边界；T-039，I-007——只数行数的审计不算审计）：
- docs/audits.md 审计行：<!-- 切片名 + 结论；Commit 列先填「本切片」，合入后由 CI 机械门禁校验回填（I-007） -->

## 质量门禁（宪法 Rule 6）

- [ ] `cargo fmt`
- [ ] `cargo clippy`
- [ ] `cargo test`
- [ ] `swift-format`
- [ ] `swift test`

## Benchmark

- 指标与结果（或"无显著影响"）：
- 基线位置（docs/benchmarks.md）：

## 文档更新

- [ ] Roadmap 状态已更新
- [ ] Changelog 已更新
- [ ] ADR 已新增 / 更新
- [ ] 其他相关文档（README / Glossary / Architecture）

## 变更说明

一句话总结 + 为什么（宪法 Rule 10：注释与提交说明都要有决策依据）。
