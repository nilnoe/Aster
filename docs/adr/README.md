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
| ADR-001 | DocumentManager | Accepted | 2026-08-02 | 2 方法 + 2 支撑类型 | Buffer, Theme | [ADR-001-document-manager.md](ADR-001-document-manager.md) |
| ADR-002 | macOS 支持策略（Latest Only） | Accepted | 2026-08-02 | 0 | Swift App、Rendering | [ADR-002-macos-support.md](ADR-002-macos-support.md) |
| ADR-003 | 插件安全模型（Trusted by Default） | Accepted | 2026-08-02 | 0 | Plugin Runtime、Plugin API | [ADR-003-plugin-trust.md](ADR-003-plugin-trust.md) |
| ADR-004 | 日志与崩溃上报 | Accepted | 2026-08-02 | 0 | Core、App、Bridge | [ADR-004-logging-crash.md](ADR-004-logging-crash.md) |
| ADR-005 | Buffer 数据模型（最小化） | Accepted | 2026-08-02 | 12 个公开项 | Core（buffer 模块） | [ADR-005-buffer-model.md](ADR-005-buffer-model.md) |
| ADR-006 | 核心数据结构决策矩阵 | Accepted | 2026-08-02 | 0 | Core | [ADR-006-data-structures.md](ADR-006-data-structures.md) |
| ADR-007 | Selection 模型（anchor / head） | Accepted | 2026-08-02 | 1 类型 + 9 方法 | Core（selection 模块） | [ADR-007-selection-model.md](ADR-007-selection-model.md) |
| ADR-008 | Undo / Redo 模型（inverse-operation 栈） | Accepted | 2026-08-02 | 2 类型 + 6 方法 | Core（history 模块） | [ADR-008-undo-redo.md](ADR-008-undo-redo.md) |
| ADR-009 | Layout 逻辑行模型 | Accepted | 2026-08-02 | 1 类型 + 4 方法 | Core（layout 模块） | [ADR-009-layout-model.md](ADR-009-layout-model.md) |
| ADR-010 | Theme 模型与 Theme DSL | Accepted | 2026-08-02 | 3 类型 + 1 方法 | Core（theme 模块） | [ADR-010-theme-model.md](ADR-010-theme-model.md) |
| ADR-011 | Command 系统与 Event 总线 | Accepted | 2026-08-02 | 4 类型 + 2 枚举 + 7 方法 | Core（command、event 模块） | [ADR-011-command-event.md](ADR-011-command-event.md) |
| ADR-012 | Lua Runtime（mlua）与 Plugin API | Accepted | 2026-08-02 | 2 类型 + 5 方法 + Lua API | Core（lua 模块） | [ADR-012-lua-runtime.md](ADR-012-lua-runtime.md) |
| ADR-013 | SQLite 存储层（Store） | Accepted | 2026-08-02 | 2 类型 + 7 方法 + 1 变体 | Core（store 模块） | [ADR-013-sqlite-store.md](ADR-013-sqlite-store.md) |
| ADR-014 | Swift Bridge 接入（spike） | Accepted | 2026-08-02 | 桥接 FFI 面 5 项 + 2 依赖 | Core（bridge 模块）、bridge/ | [ADR-014-swift-bridge-spike.md](ADR-014-swift-bridge-spike.md) |
| ADR-015 | AppKit 壳（Window / Menu） | Accepted | 2026-08-02 | 0（可执行目标） | app/ | [ADR-015-appkit-shell.md](ADR-015-appkit-shell.md) |
| ADR-016 | Metal 文本渲染管线（spike） | Accepted | 2026-08-02 | 1 个 Bridge FFI | app/、core（bridge/layout） | [ADR-016-metal-text-rendering.md](ADR-016-metal-text-rendering.md) |
| ADR-017 | 编辑循环（Editor 模块） | Accepted | 2026-08-02 | Core 8 API + Bridge 16 函数 | core（新增 editor）、bridge、app/ | [ADR-017-editor-loop.md](ADR-017-editor-loop.md) |
| ADR-018 | 基础功能完善方向（Beta V0.2 规划） | Accepted | 2026-08-02 | 0（方向性决策） | roadmap、app/、core/（规划） | [ADR-018-foundation-polish.md](ADR-018-foundation-polish.md) |
| ADR-019 | 视口滚动与软换行 | Accepted | 2026-08-02 | 0（视图层状态） | roadmap、app/（core 不变） | [ADR-019-viewport-scroll-and-wrap.md](ADR-019-viewport-scroll-and-wrap.md) |
| ADR-020 | CI 发布流水线 | Accepted | 2026-08-02 | 0（CI 基础设施） | .github/workflows/ci-release.yml、release.md | [ADR-020-ci-release-pipeline.md](ADR-020-ci-release-pipeline.md) |
| ADR-021 | 性能基准体系（criterion） | Accepted | 2026-08-02 | 0（dev-only） | core（benches）、docs/benchmarks.md | [ADR-021-performance-benchmarks.md](ADR-021-performance-benchmarks.md) |

## 触发规则

以下情况必须先有 ADR，才能进入实现：

- 新增 Public API（宪法 Rule 4）
- 新增抽象层 / Trait / Protocol（宪法 Rule 1 / 2）
- 新增依赖或第三方库（宪法 Rule 7 / 8）
- 反转既有 Accepted 决策（需用户确认）

每条 ADR 必须回答复杂度预算三问（宪法 Rule 9），并记录于本索引。
