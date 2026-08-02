# ADR-021 — 性能基准体系（criterion）

- **Status:** Accepted
- **Date:** 2026-08-02
- **Version:** 1.3
- **新增 Public API:** 0（仅 dev-dependency 与 `benches/`，不影响公共接口）
- **影响模块:** core（dev-dependencies、benches/）、docs/benchmarks.md、Roadmap T-023 / T-033、.github/workflows/ci-bench.yml（v1.3）
- **是否违反 Single Responsibility:** 否
- **是否增加循环依赖:** 否

---

## 决策

1. **基准工具用 criterion**（dev-dependency，仅 core crate）：提供稳定统计（置信区间 /
   回归检测）与报告，替代手写计时循环。
2. **基准分两组**：
   - 编辑内核组（`bench_editor.rs`）：Buffer 基础操作、Selection、History、Editor 编辑
     热路径、Layout 构建与 `line_at`、DocumentManager 打开——覆盖 ADR-006 评估框架的
     「编辑热路径 / 行访问 / 打开成本」维度。
   - 管线组（`bench_pipeline.rs`）：Theme DSL 解析、Command 分发 + Event 广播、Lua
     命令分发、SQLite Scratch 保存 / 加载——为已交付 Core 模块建立稳定基线。
3. **稳定测量规则**：一律 release 构建；记录机器 / macOS / 硬件（沿用
   docs/benchmarks.md 测量规则）；criterion 默认统计量；全量测量在本地切片 DoD
   执行。
4. **CI 基准回归告警（v1.1 新增，反转原「CI 不跑」）**：新增 `CI-Bench` 作业——
   `cargo bench -- --quick` 后与仓库内提交的基线（`bench-baseline/`，本地 release
   测量生成）经 `scripts/bench-regression.py` 对比，回归超阈值即失败。噪声控制：
   基线均值 < 10µs 的项不参与对比（超快基准跨机器噪声占比大）；阈值默认 10%
   （告警级，可经 `--threshold` 调整）。全量测量仍以本地为准，CI 只做告警。

   v1.2（T-048）：CI-Bench 阈值与下限调整——**threshold 10% → 100%，跳过下限
   10µs → 100µs**。原因（2026-08-02 发版实测）：共享 runner 上 `--quick` 模式
   噪声 +26%~+120%（全部基准同步偏移，本地对照 0 回归），10% 阈值必然误报。
   CI 定位回归为「数量级恶化粗告警」，精确回归仍以本地 release 全量测量为准
   （决策 4 不变）。阈值再误报时按备注 1 流程调整并记录。

   v1.3（T-049）：**对比改用 `median.point_estimate`（抗离群，回退 mean）+
   threshold 100% → 200%（下限 100µs 不变）**。原因（2026-08-02 第二轮实测）：
   100% 阈值仍被单次越过（buffer_insert +118.1% 误报，同轮发布流水线的 bench
   却通过——共享 runner 负载差异）。median 降低单次卡顿影响；200% 只捕获
   「3 倍级恶化」；精确回归以本地 release 全量测量为准（决策 4 不变）。
4. **对接 ADR-006**：文本存储（String / Gap / Rope / Piece Table）的决策数据来自编辑
   内核组基准；「打开成本」以 1MB 文档的载入 + Layout 构建计时近似；「内存」维度
   criterion 不测，本轮以峰值 RSS 手测记录补充，dhat / Instruments 在需要时另走 ADR
   （Rule 8）。
5. **渲染帧基线**：App 侧整帧重建成本属 Swift 层，不在本切片；其 Rust 侧组成（Layout
   构建 / `line_at`）已在编辑内核组覆盖，Swift 侧基准随渲染切片（T-016 前后）单独建立。

## 原因

- **为什么标准库不能解决（Rule 7）**：Rust 标准库没有基准框架；手写 `Instant` 循环无法
  给出置信区间与回归检测，长期基线对比不可靠。criterion 是事实标准（Rule 11 复用优先）。
- **为什么现在做（Rule 16）**：ADR-006 的存储决策（String → Rope/Gap）与渲染策略
  （整帧重建）都是性能取舍，必须先有可复现基线；基准体系拖延越久，决策窗口越窄。
- **为什么 v1.1 反转「CI 不跑」**：宪法 Rule 16 要求性能决策持续数据驱动；基准
  长期只在本地执行等于无回归防线（T-023 后 Core 改动没有任何基准对照）。
  反转经用户确认（2026-08-02，T-033 遗留项）。噪声顾虑用「10µs 下限 + 10% 阈值
  + 快速模式」吸收，并明确 CI 是告警而非精度门禁；criterion 自带 baseline 对比
  不会因回归失败退出（0.8.2 实测），故自建 stdlib 对比脚本（Rule 11：标准库优先，
  不引入 jq / pandas 等依赖）。

## 审计

### Single Responsibility — 否（不违反）

基准只测量，不引入业务职责。

### 循环依赖 — 否（不违反）

dev-dependency 不进入发布产物；core 公共接口不变。

## 新增 Public API

无。

## 影响模块

- **core/Cargo.toml** — 新增 criterion（dev-dependencies）。
- **core/benches/** — 两组基准文件。
- **docs/benchmarks.md** — 回填首个稳定基线（T-023 产出）。
- **Roadmap** — T-023 完成。

## 复杂度预算（宪法 Rule 9）

1. **增加了哪些复杂度？** 1 个 dev-dependency + 2 个基准文件；0 模块 / 0 Public API。
   v1.1：+1 个 CI 作业 + 1 个对比脚本 + 1 份提交基线（bench-baseline/）。
2. **是否是永久性的？** criterion 是长期基准基础设施（dev-only，不进入产物）；基准文件
   随新模块追加；CI 告警作业与基线文件随基准体系长期维护。
3. **有没有更简单但同样满足需求的方案？** 手写计时循环——无置信区间与回归检测，基线
   不可比；放弃基准——违反 Rule 16 且存储决策永远无数据。criterion 是最简可用形态。

结论：1 dev-dependency / 2 基准文件 + CI 告警（v1.1）/ 0 公共接口，未触及红线。

## 备注

- 基准文件同样受宪法 Rule 3（≤300 行）约束；分组按职责拆文件。
- 内存维度与 Swift 渲染帧基线是已知后续项，回填到 benchmarks.md 的备注中，不阻塞
  本切片的时延基线。
- v1.1：`bench-baseline/` 由本地 release 测量生成并提交（机器：Apple M4 / macOS
  26.5.1，与 benchmarks.md 一致）；CI 对比用相对阈值吸收跨机器噪声；阈值误报时
  调整 `--threshold` 并记录到 benchmarks.md。
