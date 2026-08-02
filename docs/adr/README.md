# ADR Index — 架构决策记录索引

每条决策一个文件，编号递增（ADR-001, ADR-002, ...），内容遵循 `_template.md`。

## 状态机

```text
Proposed → Accepted
        → Rejected
        → Superseded
```

状态变更时必须更新本索引与 [docs/changelog.md](../changelog.md)。

## 索引

| ID | 标题 | 状态 | 日期 | Public API | 影响模块 | 文件 |
| --- | --- | --- | --- | --- | --- | --- |
| ADR-001 | DocumentManager | Proposed | 2026-08-02 | 2 | Buffer, Theme | [ADR-001-document-manager.md](ADR-001-document-manager.md) |
| ADR-002 | macOS 支持策略（Latest Only） | Accepted | 2026-08-02 | 0 | Swift App、Rendering | [ADR-002-macos-support.md](ADR-002-macos-support.md) |
| ADR-003 | 插件安全模型（Trusted by Default） | Accepted | 2026-08-02 | 0 | Plugin Runtime、Plugin API | [ADR-003-plugin-trust.md](ADR-003-plugin-trust.md) |
| ADR-004 | 日志与崩溃上报 | Accepted | 2026-08-02 | 0 | Core、App、Bridge | [ADR-004-logging-crash.md](ADR-004-logging-crash.md) |
| ADR-005 | Buffer 数据模型（最小化） | Accepted | 2026-08-02 | 12 个公开项 | Core（buffer 模块） | [ADR-005-buffer-model.md](ADR-005-buffer-model.md) |
| ADR-006 | 核心数据结构决策矩阵 | Accepted | 2026-08-02 | 0 | Core | [ADR-006-data-structures.md](ADR-006-data-structures.md) |
| ADR-007 | Selection 模型（anchor / head） | Accepted | 2026-08-02 | 1 类型 + 9 方法 | Core（selection 模块） | [ADR-007-selection-model.md](ADR-007-selection-model.md) |

## 触发规则

以下情况必须先有 ADR，才能进入实现：

- 新增 Public API（宪法 Rule 4）
- 新增抽象层 / Trait / Protocol（宪法 Rule 1 / 2）
- 新增依赖或第三方库（宪法 Rule 7 / 8）
- 反转既有 Accepted 决策（需用户确认）

每条 ADR 必须回答复杂度预算三问（宪法 Rule 9），并记录于本索引。
