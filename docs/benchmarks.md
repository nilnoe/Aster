# Benchmarks — 性能基线

目标（ADR Performance Goals）：

- Cold Startup：尽可能快（具体目标待首个基准切片确定）
- Document Opening：即时
- Rendering：GPU
- 无多余分配、无轮询、一切事件驱动

基线原则（Workflow）：每个切片至少建立或刷新一次基线；没有基线的性能断言不可信。

## 指标表

| 指标 | 基线 | 最新 | 趋势 | 关联切片 / ADR | 日期 | 备注 |
| --- | --- | --- | --- | --- | --- | --- |
| Cold Startup（ms） | TBD | TBD | — | — | — | 目标待定 |
| 打开文档 100KB（ms） | TBD | TBD | — | — | — | — |
| 打开文档 1MB（ms） | TBD | TBD | — | — | — | — |
| 渲染帧时间（ms） | TBD | TBD | — | — | — | — |
| 内存占用（MB） | TBD | TBD | — | — | — | — |
| Undo 1000 次（ms） | TBD | TBD | — | — | — | — |
| Buffer 基础操作（insert/delete 10k 次，ms） | TBD | TBD | — | T-001 / ADR-005 | 2026-08-02 | 无量化目标；后续用 criterion 建立 |
| Selection 基础操作（10k 次，ms） | TBD | TBD | — | T-003 / ADR-007 | 2026-08-02 | 无量化目标；纯值类型 |
| DocumentManager 基础操作（open/close 10k 次，ms） | TBD | TBD | — | T-002 / ADR-001 | 2026-08-02 | 无量化目标；HashMap 注册表 |
| Undo / Redo 基础操作（10k 次，ms） | TBD | TBD | — | T-004 / ADR-008 | 2026-08-02 | 无量化目标；操作栈 |
| Layout 构建 1MB（ms）与 line_at 10k 次（ms） | TBD | TBD | — | T-005 / ADR-009 | 2026-08-02 | 无量化目标；O(n) 构建 |
| Theme DSL 解析（parse 10k 次，ms） | TBD | TBD | — | T-006 / ADR-010 | 2026-08-02 | 无量化目标；行级手写解析器 |
| Command 分发 + Event 广播（execute/emit 10k 次，ms） | TBD | TBD | — | T-007 / ADR-011 | 2026-08-02 | 无量化目标；HashMap 查表 + Vec 广播 |
| Lua 命令分发（load 脚本 + execute 10k 次，ms） | TBD | TBD | — | T-008 / ADR-012 | 2026-08-02 | 无量化目标；mlua vendored Lua 5.4 |

## 测量规则

- 必须使用 release 构建测量。
- 必须记录机器型号、macOS 版本、硬件配置；不同环境的数据不可直接比较。
- 每次记录附带关联切片与日期，可回溯到 Commit。
- TBD 的目标值在首个基准切片中确定后，回写本表与 ADR。
