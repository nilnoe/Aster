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
| Cold Startup（ms） | TBD | TBD | — | — | — | 目标待定；Lua 状态创建 0.020 ms（T-023）是组成部分之一 |
| 打开文档 100KB（ms） | TBD | TBD | — | — | — | — |
| 打开文档 1MB（ms） | 0.062 | 0.062 | 建立 | T-023 / ADR-021 | 2026-08-02 | DocumentManager open：磁盘读 + Buffer 载入 + 注册 |
| 渲染帧时间（ms） | TBD | TBD | — | — | — | Swift 侧整帧重建基线随渲染切片（T-016 前后）建立；Rust 侧组成（Layout 构建 / line_at）已覆盖 |
| 首帧字形栅格化+上传（16 字形，ms） | TBD | 0.30（@2x） | 刷新 | T-012 / ADR-016 | 2026-08-02 | release 构建；Apple M4 / macOS 26.5.1；BUG-001 后按像素尺寸栅格化，1× 基线 0.25 → 2× 基线 0.30，可接受 |
| 内存占用（MB） | TBD | TBD | — | — | — | — |
| Undo 1000 次（ms） | TBD | TBD | — | — | — | 10k 口径已建立（见下），千次口径后续补 |
| Buffer 基础操作（insert/delete 10k 次，ms） | 0.174 / 0.039 | 0.174 / 0.039 | 建立 | T-023 / ADR-021 | 2026-08-02 | 编辑热路径维度（ADR-006）；insert 在末尾逐次追加、delete 从末尾逐次删除（String O(n) 总成本含状态增长） |
| Selection 基础操作（10k 次，ms） | 0.0006 | 0.0006 | 建立 | T-023 / ADR-021 | 2026-08-02 | 纯值类型 set_head |
| DocumentManager 打开 1MB（ms） | 0.062 | 0.062 | 建立 | T-023 / ADR-021 | 2026-08-02 | 与「打开文档 1MB」同测（ADR-006 打开成本维度） |
| Undo / Redo 基础操作（10k 次，ms） | 0.145 / 1.424 | 0.145 / 1.424 | 建立 | T-023 / ADR-021 | 2026-08-02 | record 10k Delete ops；undo 10k 含 Buffer 应用 |
| Editor 基础操作（10k type + 10k delete，ms） | 0.290 / 0.329 | 0.290 / 0.329 | 刷新 | T-013→T-023 / ADR-017 / ADR-021 | 2026-08-02 | 原 T-013 手测 0.83 拆分为 criterion 分项；含历史记录 |
| Layout 构建 1MB（ms）与 line_at 10k 次（ms） | 0.264 / 0.277 | 0.264 / 0.277 | 建立 | T-023 / ADR-009 / ADR-021 | 2026-08-02 | 行访问维度（ADR-006） |
| Theme DSL 解析（parse 10k 次，ms） | 4.210 | 4.210 | 建立 | T-023 / ADR-010 / ADR-021 | 2026-08-02 | 四角色完整 DSL |
| Command 分发 + Event 广播（execute/emit 10k 次，ms） | 0.077 / 0.012 | 0.077 / 0.012 | 建立 | T-023 / ADR-011 / ADR-021 | 2026-08-02 | 单命令 HashMap 查找 + 单订阅者 Vec 广播 |
| Lua 命令分发（load 脚本 + execute 10k 次，ms） | 0.295 | 0.295 | 建立 | T-023 / ADR-012 / ADR-021 | 2026-08-02 | dispatch 0.295；Lua 状态创建 0.020（冷启动组成部分） |
| SQLite Scratch 保存 / 加载（10k 次，ms） | 10.298 / 7.405 | 10.298 / 7.405 | 建立 | T-023 / ADR-013 / ADR-021 | 2026-08-02 | 内存库；每次 upsert / query |
| Swift → Rust 往返调用（10k 次，ms） | TBD | TBD | — | T-010 / ADR-014 | 2026-08-02 | 无量化目标；spike 验证全链路 |
| App 冷启动（ms） | TBD | TBD | — | T-011 / ADR-015 | 2026-08-02 | 无量化目标；首个 App 切片，正式基线 T-020 |

## 测量规则

- 必须使用 release 构建测量。
- 必须记录机器型号、macOS 版本、硬件配置；不同环境的数据不可直接比较。
- 每次记录附带关联切片与日期，可回溯到 Commit。
- TBD 的目标值在首个基准切片中确定后，回写本表与 ADR。
- 基准由 criterion 0.8.2 驱动（ADR-021，关闭 plotters/rayon 默认特性），命令：
  `cargo bench --manifest-path core/Cargo.toml`；本机 Apple Silicon（arm64）/
  macOS 26.5.1。编辑热路径四项首次以短采样（1s measurement）建立，其余默认
  100 样本；跨次对比只认同一参数。
