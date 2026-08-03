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
| 水平滚动渲染（App 视图层） | — | 无显著影响 | — | T-018 / ADR-019 | 2026-08-02 | 本切片未触碰 Core（ADR-019：Core 不变）；渲染路径仅每个 x 顶点减 scrollX（O(1)），顶点数量不变；Core 各基线见 T-023 |
| 文件打开接线（App 视图层） | — | 无显著影响 | — | T-015 / ADR-001 | 2026-08-02 | 打开走 DocumentManager Disk 源（Core 未变）；「打开文档 1MB = 0.062ms」基线即本路径（T-023），App 侧仅新建 Buffer + Editor |
| SQLite 快照保存（单次文件创建 + upsert） | — | 无显著影响 | — | T-040 / ADR-023 v1.2 | 2026-08-02 | Cmd+S 每次新建「日期+序号」SQLite 文件并 upsert 一行；非编辑热路径，不触碰编辑内核基准；同日多次保存 = 多版本文件（用户指示） |
| 保存写回（Disk，单次文件 IO） | — | 作废 | — | T-037 / ADR-023 | 2026-08-02 | T-040 反转：保存目标改为 SQLite，磁盘写回 Deferred（本行仅留档） |
| 自动保存缓冲（每次内容变更一次 SQLite upsert） | — | 无显著影响 | — | T-041 / ADR-023 v1.3 | 2026-08-02 | 内容变更自动写 buffer.sqlite（崩溃保护）；单行 upsert 亚毫秒级，非渲染热路径；快照合并（Cmd+S）单次写入，频率远低于编辑 |
| 快照合并（Cmd+S，纯文本覆盖写） | — | 无显著影响 | — | T-042 / ADR-023 v1.4 | 2026-08-02 | 快照由 .sqlite 改为 .txt 纯文本：合并 = 单次 std::fs::write（整文件覆盖），比 SQLite 快照更轻；非编辑热路径 |
| 崩溃恢复检测（启动时一次） | — | 无显著影响 | — | T-043 / ADR-013 v1.1 | 2026-08-02 | 启动时读哨兵 + 枚举缓冲文档（各一次查询），非热路径；恢复载入 = 单文档文本插入 |
| 缓冲行删除（合并 / 丢弃时一次 DELETE） | — | 无显著影响 | — | T-045 / ADR-013 v1.3 | 2026-08-02 | 合并 / 恢复 / 丢弃后单行 DELETE，频率与 ⌘S 相同；缓冲 upsert 仍是唯一热路径（每次内容变更） |
| 多文档退出「保存全部」 | — | 无显著影响 | — | T-046 / ADR-013 v1.4 | 2026-08-02 | 退出时对每个未决文档一次读 + 写 + 删（N 次 ⌘S 的组合），非热路径；与单文档合并同量级 |
| 空快照退出清理（一次目录扫描） | — | 无显著影响 | — | T-047 / ADR-023 v1.6 | 2026-08-02 | 进程退出时单次 read_dir + 零长度判断；目录规模 = 当日快照数，非热路径 |
| 渲染数据路径（App 视图层） | — | 消除每帧 O(n) | — | T-038 / I-003 | 2026-08-02 | 全文 Bridge 往返 + 全量 split 改为失效缓存（每编辑一次），可见行 shaping 每帧 2→1 次，lineIndex 线性→二分；整帧时间全量基线仍 TBD（随 T-016 渲染质量切片建立） |
| App 集成测试套件 | — | 无显著影响 | — | T-050 | 2026-08-02 | 纯测试切片：生产改动仅 AppDelegate 两个提示方法抽取（同逻辑不同位置）与移除 `final`；Rust Core 零改动（基准不重跑），App 冷启动 / 编辑热路径不受影响；测试本身新增 15 个 XCTest 用例（非性能路径） |
| BUG-010/011/012 修复 | — | 无显著影响 | — | BUG-010~012 | 2026-08-02 | 保存 / 恢复链路修复：编辑热路径仅 `onContentChanged` 增加一次 String 相等比较（O(n) 短接），自动保存写频不变；打开 / 恢复 / 合并均为低频路径（各一次文件或 SQLite 操作）；Rust Core 零改动，基准不重跑 |
| T-051 测试方法论强化 | — | 无显著影响 | — | T-051 | 2026-08-03 | 纯测试切片（0 生产代码改动）：新增失败注入与随机不变量用例（非性能路径）；基准不重跑 |
| IME 契约修复（T-052，BUG-013/014） | — | 无显著影响 | — | T-052 | 2026-08-03 | 仅 IME 回调路径（点击定位 / 组合开始，非编辑热路径）：characterIndex 增加一次屏幕→视图换算与 UTF-16 换算（O(行)）；setMarkedText 增加一次选区删除（与既有 insertText 同路径）；Rust Core 零改动，基准不重跑 |
| 失败可见性修复（T-054，BUG-015） | — | 无显著影响 | — | T-054 | 2026-08-03 | 仅失败路径（正常路径多 1 个布尔赋值）：自动保存成功时多一次 `bufferSaveErrorVisible = false` 写（O(1)），失败路径按段落弹一次提示（非热路径）；Rust Core 零改动，基准不重跑 |

## 测量规则

- 必须使用 release 构建测量。
- 必须记录机器型号、macOS 版本、硬件配置；不同环境的数据不可直接比较。
- 每次记录附带关联切片与日期，可回溯到 Commit。
- **基线文件（T-033，ADR-021 v1.3）：** `bench-baseline/` 是本地 release 测量的
  17 项基线（Apple M4 / macOS 26.5.1），随仓库提交；`CI-Bench` 作业以 `--quick`
  模式对比该基线，**median 对比 + 回归超 200% 即红（100µs 以下跳过；告警级，
  非精度门禁）**——共享 runner 的 quick 模式噪声 +26%~+120%（偶发越过 100%），
  精确回归以本地 release 全量测量为准（ADR-021 v1.3）。基线更新：本地
  `cargo bench`（`cd core && CARGO_TARGET_DIR=target cargo bench`）后执行
  `python3 scripts/bench-regression.py --save-baseline bench-baseline --criterion-root core/target/criterion`。
- TBD 的目标值在首个基准切片中确定后，回写本表与 ADR。
- 基准由 criterion 0.8.2 驱动（ADR-021，关闭 plotters/rayon 默认特性），命令：
  `cargo bench --manifest-path core/Cargo.toml`；本机 Apple Silicon（arm64）/
  macOS 26.5.1。编辑热路径四项首次以短采样（1s measurement）建立，其余默认
  100 样本；跨次对比只认同一参数。
- **已知缺口（2026-08-03，ADR-006 v1.1）：** 现有基准只测**末尾**编辑
  （insert/delete end_10k）与 1MB 单次打开；文档**中间** insert/delete、
  光标移动（↑↓/Home/End）成本无数据——移动重建 `Layout`（O(n)/次）与 String
  中间编辑（O(n)）的真实代价未量化。T-063 排期补齐（1MB 中间编辑 10k、
  移动 1k、大 blob upsert）。
