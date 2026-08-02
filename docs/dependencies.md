# Dependencies — 依赖维护政策

## 原则

- 复用优先（宪法 Rule 11），但每新增一个依赖必须通过 Rule 7（为什么标准库不能解决）+ Rule 8（ADR）。
- 依赖必须锁定版本：提交 `Cargo.lock` 与 `Package.resolved`。

## 新增依赖流程

1. **Analysis**：评估候选（生态活跃度、维护状态、许可证兼容 MIT）。
2. **ADR**：记录选择与拒绝项。
3. **切片**：引入依赖本身就是一个垂直切片（测试 + benchmark 基线）。
4. **记录**：更新 [docs/benchmarks.md](benchmarks.md) 与 [docs/changelog.md](changelog.md)。

## 升级策略

- **patch**：正常维护节奏。
- **minor**：按需，走常规切片。
- **major**：必须新 ADR（行为 / API 可能变化），测试与 benchmark 对比通过后才能合入。

## 安全

- 安全补丁优先处理（bug-workflow）。
- 定期运行 `cargo audit`；Swift 侧关注 SPM 依赖安全公告。
