# Audits — 架构审计登记表

WORKFLOW 第 8 步（Architecture Audit）的强制产物。每个切片在审计完成后追加一行；
审计必须留痕，**无记录的审计视为未执行**（宪法 Rule 13 精神；ADR-022 决策 3）。

| 切片 / 事项 | Commit | 审计项 | 结论 | 违规与处置 | 日期 |
| --- | --- | --- | --- | --- | --- |
| T-044 SQLite 保留论证（ADR-013 v1.2） | 7a1408d | 行为证据：纯文档切片（无代码改动）；论证基于代码现状核验（scratch/meta 在用、session 表零消费者、libsqlite3.a 2.4MB、FFI 6 项）；Rule 9 三问（0 抽象层 / 0 依赖 / 0 API，仅文档）；Rule 13（守则 b 把 session 表接线义务挂到 T-029，防悬挂）；决议保留经用户确认 | Pass | 无 | 2026-08-02 |
| T-043 崩溃恢复 v1（ADR-013 v1.1） | cab4045 | 行为证据：Core 2 + Bridge 1 + App 3 测试全绿（哨兵缺省/往返、缓冲枚举、恢复决策纯函数）；ADR-013 v1.1 修订留痕；Rule 9 三问（meta 表 1 行 + 3 方法 + 恢复提示，0 抽象层 / 0 新依赖）/ Rule 12（store.rs 288、AppDelegate 292 ≤300；core/src 2110、App 1945 在预算）/ Rule 14（3 FFI 消费者 = AppDelegate 恢复流程，同切片交付） | Pass | 无 | 2026-08-02 |
| T-042 快照改为纯文本（ADR-023 v1.4） | b8cd54b | 行为证据：Core 4（snapshot 模块全绿）+ Bridge 3 + App 全量 56 全绿；快照 .txt 纯文本断言（Buffer 可打开，用户反馈）；ADR-023 v1.4 修订留痕；Rule 3（snapshot 独立模块而非塞进 Store——Store=SQLite SRP）/ Rule 9 三问（0 抽象层 / 0 新依赖）/ Rule 12（snapshot.rs 172、store.rs 缩减；core/src 2039、App 1882 在预算）/ Rule 14（移除无消费者的 SQLite 快照 API） | Pass | 无 | 2026-08-02 |
| T-041 缓冲 + 快照保存模型（ADR-023 v1.3，BUG-009） | c4b4710 | 行为证据：Core 6 + Bridge 3 + App 1 测试全绿（快照序号 / 缓冲往返 / 合并读回 / 菜单 ⌘N / scratch id）；ADR-023 v1.3 + ADR-001 v1.2 修订留痕（用户指示，Rule 13）；BUG-009 根因 = onChange 只在 open() 接线，makeModel 统一接线修复；Rule 9 三问（三文件模型：缓冲连续写 + 快照提交，0 抽象层 / 0 新依赖）/ Rule 12（store.rs 267、AppDelegate 243 ≤300；core/src 1916、App 1880 在预算）/ Rule 14（open_scratch FFI 消费者 = newDocument，同切片交付） | Pass | 无 | 2026-08-02 |
| T-040 保存改为 SQLite 快照（ADR-023 v1.2） | d28cb9b | 行为证据：Core 6 + Bridge 2 + App 2 测试全绿（序号递增 / 缺号 / latest 往返 / 目录创建 / StorePaths）；ADR-023 v1.2 反转经用户确认（Rule 13：反转 Accepted 决策必须用户同意，changelog 记录）；Rule 4（open_next/open_latest + 1 错误变体 + FFI 4 项先 ADR）/ Rule 9 三问（0 抽象层 / 0 新依赖；civil date 标准算法，不引 chrono）/ Rule 12（store.rs 244、AppDelegate 171 ≤300；core/src 1872、App 1800 均在预算）/ Rule 14（撤销无消费者的 save_text / 错误变体） | Pass | T-037 方向偏差（磁盘写回超前实现）已由用户指示纠正，ADR v1.1 → v1.2 留痕 | 2026-08-02 |
| T-039 审计与门禁加固 | 3171806 | 行为证据：CI-Docs 新增审计完整性机械检查（未回填行 ≤1 + hash 全存在，fetch-depth 0，本地模拟通过）；CI-Release 补齐 swift-format(app/Sources) / fuzz / 规模预算 / docs 完整性 / 基准回归（I-008 对齐）；Rule 9 三问（纯 CI 配置与文档，0 依赖 / 0 抽象层）/ Rule 15（审计留痕从人工回填变为机械门禁） | Pass | 无 | 2026-08-02 |
| T-038 渲染数据路径重构 | 7220747 | 行为证据：3 个新测试 + 既有 49 项全绿（渲染 / 像素测试行为不变）；基准记录：每帧 O(n) → O(可见行)（全文 Bridge 往返与 split 只在失效后一次），帧时间全量基线随 T-016 建立；Rule 9 三问（缓存 2 字段 + 1 行切分 API + 二分，0 抽象层 / 0 依赖）/ Rule 12（EditorModel 249、VertexBuilder 202 ≤300；App 1775 < 5,000）/ Rule 3（EditorModel 单一职责未变） | Pass | 无 | 2026-08-02 |
| T-037 Disk 保存（ADR-023） | 135f44a | 行为证据：Core 5 + Bridge 2 + App 2 测试全绿（保存往返 / 失败可见 / 菜单 / onChange）；ADR-023 Accepted 且入索引（Rule 13 闭环）；Rule 4（1 方法 + 2 错误变体 + 1 FFI 先 ADR）/ Rule 9 三问（0 抽象层 / 0 依赖，App 薄胶水 ~96 行）/ Rule 12（AppDelegate 177、EditorModel 198、AppMenu 109 ≤300；App 总量 1711 < 5,000）/ Rule 14（onChange 是 App 模块内回调，非公共 API） | Pass | 无 | 2026-08-02 |
| T-035 Up/Down 边界修复（BUG-008） | 29bdf9d | 行为证据：4 个手写回归 + Up/Down 纳入属性差分 + 边界不变量显式断言（`PROPTEST_CASES=3000` 通过）；ADR-017 v1.1 备注（字节列须 floor 到边界，ADR-005 优先）；Rule 9 三问（1 行钳制 + 模型镜像算法，0 抽象层 / 0 依赖）/ Rule 12（property.rs 超 300 行 → 拆 support（119）/ property（162）/ property_fuzz（91），全部 ≤300；editor.rs 238 ≤300） | Pass | 无 | 2026-08-02 |
| T-034 审查问题登记 | 440c75b | Rule 15（issues.md 入 README 索引）/ Rule 3（issues.md 单一职责）/ Rule 9 三问（0 抽象层 / 0 依赖 / 0 公共 API，纯文档） | Pass（自审） | 无 | 2026-08-02 |
| 复审（全仓） | d996059、db053f5、bce9d05、fb82b85、aa78b6a | 文档漂移 / ADR 失约 / 零消费者模块 / 基准缺失 / 门禁缺口 | 发现并处置 | ADR-018 索引补登、宪法 V1.4（R13~16）、接线计划（T-015/016/024/028/029/031）、CI-Docs 与 CI-Release 门禁、T-023 基准落地 | 2026-08-02 |
| T-023 性能基准体系 | aa78b6a | Rule 16 基准门禁 / Rule 3 文件 ≤300 / ADR-021 / Rule 9 三问（1 dev-dep、0 公共接口） | Pass | 无 | 2026-08-02 |
| T-032 测试与审计加固 | d867ac7 | Rule 8（proptest ADR-022）/ Rule 9 三问 / 审计留痕制度落地 | Pass（自审） | 无 | 2026-08-02 |
| T-018 水平滚动 | 47c1dc2 | ADR-019（0 公共 API、Core 不变）/ Rule 3（MetalView 298、TextRenderer 292 贴线，拆分后 258 / 130+200）/ Rule 9 三问（1 个视口状态 + 输入平移 + 光标可见性，无抽象层 / 无依赖）/ Rule 12（全部 ≤300，App 总量 1483 < 5,000；T-036 校正：现 1615）/ Rule 14（Viewport / VertexBuilder 均 App 模块内，非公共 API） | Pass | 无；拆分前置在本切片完成 | 2026-08-02 |
| T-036 存量清理 | 6ceb0fe | Rule 14（`Selection::clamp` 零消费者 → 撤销，ADR-007 v1.1 记录）/ Rule 12（core/src 1726 ≤20k；死代码移除）/ Rule 15（experience / audits 计数校正；T-032 hash 回填）/ I-006 核验纠正（.DS_Store 从未入库，误报撤销）；Rule 9 三问（0 抽象层 / 0 依赖，纯删除 + 文档校正） | Pass | I-006 误报：审查依据 find 输出未区分跟踪状态，已用 git ls-files 核验纠正 | 2026-08-02 |
| BUG-006 光标边缘留白 | 98cfb30 | ADR-019 光标横向可见性语义落实 / Rule 9（2 个留白常量 + 2 条边界规则，无新增依赖 / 抽象）/ Rule 12（Viewport 75、TextRenderer 132 等全部 ≤300） | Pass | 无 | 2026-08-02 |
| BUG-007 组合期间横向可见性 | 1d7dfe7 | ADR-019（组合末尾光标 = BUG-004 语义纳入可见性）/ Rule 9（1 行调用，无新增状态 / 依赖）/ Rule 12（MetalView+Input 99 行 ≤300） | Pass | 无 | 2026-08-02 |
| T-015 文件打开接线 | e6a7ebd | ADR-001 v1.1（Bridge FFI 3 项已记录）/ Rule 3（全部 ≤300）/ Rule 9 三问（3 个 FFI 适配函数 + App 薄胶水，0 抽象层 / 0 依赖）/ Rule 12（pub(crate) 访问器，不构成公共 API）/ Rule 14（DocumentManager 首次进产品，真实调用方 = AppDelegate） | Pass | 无；注册表副本与会话分离的激活状态边界已记录于 ADR-001 v1.1，随 T-024 统一 | 2026-08-02 |
| T-033 fuzz + 基准回归告警 | 9a60b08 | ADR-021 v1.1（反转「CI 不跑」经用户确认）/ ADR-022 v1.1（fuzz = 属性空间扩展，0 新依赖）/ Rule 7（对比脚本仅标准库）/ Rule 9（1 脚本 + 1 CI 作业 + 基线文件，无抽象层）/ Rule 12（bench-baseline 数据非源码，不计行数） | Pass | 无；criterion 自带 baseline 对比不因回归失败退出，自建脚本补齐（已记录 ADR-021 v1.1 原因） | 2026-08-02 |

## 规则

- 每切片必须新增一行；违规项必须写明处置（修代码 / ADR 修订 / 用户确认），
  不允许只写"通过"不写依据。
- **行为证据必填（T-039，I-007）**：审计项必须包含实际验证过的行为——运行的
  测试 / 基准命令、验证的边界或不变量、检查的门禁；只数行数 / API 数的审计
  不算审计。
- Commit 列填切片提交 hash；提交前无法预先填写的填「本切片」，由 git log 追溯。
- **回填机械门禁（T-039，I-007）**：CI-Docs 检查审计表——「本切片」只允许
  当前切片一行（未回填不得累积），表内 commit 必须存在于 git 历史；回填是
  合入前提，不再靠人工自觉。
- Roadmap 复审政策（季度 / 里程碑）触发全仓审计行，结论同步到 changelog。
