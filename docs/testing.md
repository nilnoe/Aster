# Testing — 测试策略

原则：测试先于实现（宪法 Rule 5）；UI 保持薄，可测试逻辑尽可能落在 Rust Core。

## 分层

| 层 | 测试类型 | 覆盖内容 |
| --- | --- | --- |
| Core（Rust） | 单元测试 / 属性测试 | Buffer、Undo、Layout、Theme、Command、Event 等纯逻辑，不依赖 I/O |
| Core（Rust） | 集成测试 | SQLite 持久化、PTY 会话、Lua 宿主 |
| Bridge | 集成测试 | Swift ↔ Rust 往返调用；API 签名与行为契约 |
| App（Swift） | 薄测试 | 仅测抽出的逻辑（T-012 起：输入状态机 / 图集分配器 / 字形图集像素读回 / LineLayout 命中换算；无 GPU 时跳过）；View 层靠手动验证与基准 |
| 性能 | benchmark | 见 [docs/benchmarks.md](benchmarks.md)；每个切片刷新基线 |

## 规则

- Red → Green → Refactor（宪法 Rule 5）；Bug 回归测试见 [docs/bug-workflow.md](bug-workflow.md)。
- 属性测试用于易漏边界的逻辑（文本操作、布局）。
- 错误路径与 panic 路径必须测试（ADR-004：失败要可见）。
- Public API 的行为契约（ADR 定义）必须覆盖。
- 测试命名：`<module>_<behavior>`，断言行为而非实现。

## 工具（计划）

- Rust：`cargo test` + proptest + criterion（benchmark）
- Swift：XCTest + swift-format

首个切片落地时确认具体测试框架配置并回写本文档。
