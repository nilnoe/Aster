# Roadmap — 开发路线 TODO

每个条目都是一个垂直切片，必须完整执行 [WORKFLOW.md](../WORKFLOW.md) 的管线。

状态标记：`[ ]` 未开始 · `[~]` 进行中 · `[x]` 完成

切片完成时：更新本文件状态 → 更新 [docs/changelog.md](changelog.md) → 提交。

---

## Phase 0 — 项目基础

- [x] 文档体系建立（Constitution / ADR / Workflow / Roadmap / Changelog / AGENTS）
- [x] 工程基础设施文档（CI / DEVELOPING / 测试策略 / 发布流程 / 依赖政策 / 安全）
- [x] T-001 Rust Core 骨架：crate 结构 + Buffer 最小模型 + 测试（Red → Green）
- [x] T-002 DocumentManager：`open` / `close`（注册表 + 生命周期，ADR-001）

## Phase 1 — Core 编辑内核

- [x] T-003 Selection 模型（anchor / head 字节偏移，光标即 head）
- [x] T-004 Undo / Redo（inverse-operation 栈 + 相邻 Insert 合并，ADR-008）
- [x] T-005 Layout：逻辑行模型（行号 ↔ 字节区间 ↔ 偏移，ADR-009）
- [x] T-006 Theme：主题模型 + Theme DSL
- [x] T-007 Command 系统 + Event 总线
- [x] T-008 Lua Runtime（mlua）接入 + Plugin API
- [x] T-009 SQLite 存储：Scratch / Session / Crash Recovery

## Phase 2 — 系统集成

- [x] T-010 swift-bridge 接入（spike，验证 API 面）
- [x] T-011 AppKit 壳：Window + Menu + 空白视图
- [x] T-012 Metal 渲染管线：文本渲染 spike（CoreText + IME + CJK）
- [x] T-013 编辑循环：键盘输入、光标、滚动、选择
- [ ] T-014 剪贴板：复制 / 剪切 / 粘贴 + Edit 菜单接线（系统 NSPasteboard；ADR-018）
- [x] T-015 拖放与文档选择器：文件拖入 Buffer、NSOpenPanel 打开；接线 DocumentManager `open`（Disk 源，ADR-001）（ADR-018）

> 深浅色跟随系统不在本阶段：固定深色启动态，主题可编程能力由 Lua 提供（ADR-018）。

## Phase 3 — 渲染与编辑打磨（ADR-018 / ADR-019 方向）

- [ ] T-016 渲染质量：sRGB + gamma 校正（抗锯齿边缘与系统渲染对齐）；渲染颜色接入 Core Theme（ADR-010，固定深色启动主题）
- [x] T-017 光标：闪烁与可见性（BUG-002 修复随缺陷流程）
- [x] T-018 水平滚动：长行平移可读，光标横向可见性（ADR-019）
- [ ] T-019 软换行：用户可选、默认关闭的视觉折行（ADR-019）
- [ ] T-020 编辑细节：DeleteForward + 词级移动（Option+←/→）
- [ ] T-021 选择打磨：双击选词 / 三击选行
- [ ] T-022 滚动与 IME：平滑滚动 / 候选框定位精确化
- [x] T-023 性能基准体系：criterion + 稳定测量（ADR-006 数据结构决策的前置门禁，宪法 Rule 16；优先于任何存储替换切片，穿插于渲染 / 编辑切片之间执行）
- [x] T-067 未保存指示迁移系统原生：dirty「●」从标题文本手拼改为
  `NSWindow.isDocumentEdited`（关闭按钮红点，总纲 Principle 4 / 宪法 Rule 11；
  标题恢复纯文件名；2026-08-03 追加，编号顺延）
- [x] T-069 新建 Frame（⌘⇧N，2026-08-03 追加）：frame = 广义窗口（未来窗内
  分窗，故不用 window 表述）——多 Frame 状态隔离（按 frame 接线 onChange /
  标题 / 文件名 / 自动保存，编辑 frame B 不污染 frame A）；启动与 ⌘⇧N 共用
  makeFrame 单一创建路径；绑定只存在于 File 菜单（按键将来可改、与动作解耦）；
  关闭 frame 从登记移除，最后窗口关闭仍退出

## Phase 4 — Overlay 生态

- [ ] T-024 Command Palette overlay：Command / Event 接线进编辑循环（ARCHITECTURE 数据流跑通，ADR-011）+ Lua 插件加载（命令注册，ADR-012）与主题可编程入口（ADR-018）
- [ ] T-025 Search overlay
- [ ] T-026 StatusBar overlay（含未保存 / 未决文档的 Buffer 底部行内提示 + y/n 输入——替代过渡期模态弹窗，ADR-023 v1.5 无模态弹窗原则）
- [ ] T-027 Shell overlay（PTY + 模糊背景）
- [ ] T-028 Scratch 工作流：`Cmd+N` → 自动保存 → Attach Path；接线 Store scratch 与 DocumentManager（Scratch 源，ADR-001 / ADR-013）

## Phase 5 — 稳定与发布

- [x] T-043 崩溃恢复 v1（ADR-013 v1.1）：缓冲哨兵（clean_exit）+ 启动检测 + 恢复提示；缓冲文档载回编辑器
- [x] T-044 SQLite 保留论证入文档（ADR-013 v1.2 + 总纲 §5 边界）：文档 = 文本文件、SQLite = 内部状态；三条保留论据 + 拆除条件 + 三条守则；决议保留
- [x] T-045 缓冲数据生命周期（ADR-013 v1.3）：保留 = 未提交且未明确丢弃（含崩溃后 / 忽略 / 干净退出）；删除 = Cmd+S 合并成功 / 恢复载入 / 退出「不保存」三时机；AppDelegate 334 行与 bridge.rs 308 行超 Rule 3 → 拆 AppDelegate+Storage.swift 与 bridge_store.rs
- [x] T-046 多文档状态全程检查（ADR-013 v1.4 / ADR-023 v1.5，用户指示）：PendingDocs 登记所有未决文档（切换 / 打开新文件不抛弃前一个）；退出提示覆盖全部未决（保存全部 / 全部不保存 / 取消）→ 干净退出后缓冲清空；缓冲定位 = 强杀 / 意外退出等边界情况专用；无模态弹窗原则（未来 = StatusBar 底部 y/n 提示，T-026；当前 NSAlert 为过渡实现）
- [x] T-047 空快照文件退出清理（ADR-023 v1.6，用户指示）：进程干净退出时删除内容为空的 `aster-*.txt`（启动即建 / 从未输入合并的空文档不累积）；只删零长度，崩溃退出不清理
- [x] T-048 发版 CI 检查修复（Beta V0.1.2 发布前置）：clippy 1.97 items_after_test_module；CI-Bench 结果目录定位（CARGO_TARGET_DIR）；阈值 100% / 下限 100µs（ADR-021 v1.2）；版本断言改格式校验
- [x] T-049 CI-Bench 稳定性（ADR-021 v1.3）：对比改用 median（抗离群）+ 阈值 200%——共享 runner quick 模式噪声最高 +120%，100% 仍偶发误报；CI 只抓 3 倍级恶化，精确回归以本地为准
- [x] T-050 App 集成测试套件（五组，用户指示）：真实 NSApplication 生命周期 + 文档保存 / 退出 / 崩溃恢复全链路 + 端到端数据流（AppKit → Bridge → Core → 事件 → 重绘）；策略与分层见 docs/testing.md「App 集成测试」
- [x] T-051 测试方法论强化（用户指示「换思路」）：变异测试量化查错能力（6 个变体 → 暴露保存失败路径盲区）+ 失败注入测试（快照写失败必须保全缓冲行与未决状态）+ 随机操作序列不变量测试（固定种子 ×3，验证 ADR-013 v1.3 缓冲行 ⟺ 未决守恒与 BUG-011 泛化不变量）
- [ ] T-029 Crash Recovery 与 Session 恢复（T-043 已交付缓冲恢复 v1；剩余：多文档会话完整恢复、窗口状态，接线 Store session）
- [ ] T-030 首个正式版 V1.0.0（暂不排期，Beta 优先）
- [ ] T-031 日志与错误可见性：os_log（App）+ tracing（Core）接线，ADR-004 落地（宪法 Rule 13 闭环）
- [x] T-032 测试与审计加固：proptest 属性测试（Buffer / Editor / Layout 不变量）+ 审计记录制度（docs/audits.md，ADR-022）
- [x] T-033 fuzz 扩展 + 基准回归告警：属性空间扩展到 emoji / CJK / 换行 / 组合字符（CI `PROPTEST_CASES=3000` 专项运行）；criterion 基线提交 + CI 阈值对比作业（ADR-021 v1.1，反转「CI 不跑」经用户确认）

## Phase 6 — 复审整改（2026-08-02 全仓审查，I-001 ~ I-008）

> 审查结论与证据见 [docs/issues.md](issues.md)；按严重度顺序修复：P0 → P2 清理 → P1 功能 → 门禁加固。

- [x] T-034 审查问题登记：新建 docs/issues.md 并同步索引 / Roadmap / Changelog（I-001~I-008）
- [x] T-035 Up/Down 光标 UTF-8 边界修复（I-001，BUG-008，ADR-005 底线）+ Up/Down 纳入属性测试差分
- [x] T-036 存量清理：删除无消费者 `Selection::clamp`（I-004）、校正文档计数漂移与 T-032 审计回填（I-005）、核验 .DS_Store 未入库并清理工作树残留（I-006 误报纠正）
- [x] T-037 保存切片（v1 磁盘写回方向，后被 T-040 修正）：File「保存」Cmd+S + dirty 标题 + 关闭保护（I-002，ADR-023）
- [x] T-038 渲染数据路径重构：缓存行结构、每帧单次 shaping、视口切行，消除每帧 O(n)（I-003）
- [x] T-039 审计与门禁加固：审计留痕机械检查（Rule 15 扩展）+ CI-Release 与日常 CI 门禁对齐（I-007 / I-008）
- [x] T-040 Cmd+S 自动保存到 SQLite（ADR-023 v1.2，用户确认反转 T-037 磁盘写回）：每次保存新建「日期+序号」快照文件（单日多版本），默认目录 `~/Library/Application Support/Aster`（`ASTER_STORE_DIR` 可覆盖）；磁盘写回（用户指定路径）显式 Deferred 到未来文件系统切片
- [x] T-041 缓冲 + 快照保存模型（ADR-023 v1.3，用户指示）：Cmd+N 创建「日期+序号」快照文件；内容变更自动写入缓冲文件 buffer.sqlite（崩溃保护）；Cmd+S 合并缓冲 → 当前快照；修复 BUG-009（默认文档 onChange 未接线 → 无 dirty「●」/ 退出保护）
- [x] T-042 快照改为纯文本文件（ADR-023 v1.4，用户反馈 .sqlite 无法在 Buffer 打开）：Cmd+N 创建 `aster-YYYY-MM-DD-<seq>.txt`、Cmd+S 合并缓冲文本进当前快照（可直接在 Buffer / 任何编辑器打开）；SQLite 仅保留缓冲（buffer.sqlite）

## Phase 7 — 测试强化专项（2026-08-03 起，用户指示「专门投入各种测试」）

> 来源：T-050 集成测试 + T-051 变异测试暴露的盲区清单。执行原则：每个切片
> 先变异 / 注入定位盲区，再补测试；0 生产代码改动不可作为验收（发现缺陷须
> 登记 BUG 并修复）。排序按风险，可调整。

- [x] T-052 IME 契约审计：`MetalView.characterIndex(for:)` 返回字节偏移而
  NSTextInputClient 契约是 UTF-16 索引（CJK 点击定位错位候选）；`setMarkedText`
  忽略 `replacementRange`（选中文本输入拼音时组合显示与选区重叠）。验收：真实
  IME / 模拟输入验证，确认缺陷 → 登记 BUG + 修复 + 回归；无缺陷 → 契约测试固化
  （2026-08-03：两处缺陷均确认——BUG-013（characterIndex：屏幕坐标 + 字节偏移
  双违规）/ BUG-014（replacementRange 被忽略）；模拟协议调用验证 + 5 项契约回归
  先红后绿，变异复验旧实现报 3≠1 / 8≠1；App 91 全绿）
- [ ] T-053 渲染层变异测试：TextRenderer / VertexBuilder / GlyphAtlas /
  AtlasPacker 关键算法变异（坐标换算、图集分配、UV 采样、缓存失效），像素读回
  测试保持全绿；全绿变体 = 盲区 → 补测试
- [x] T-054 失败可见性审计：缓冲自动保存失败仅 NSLog（用户不可见，ADR-004
  打折）；`setupStorage` 失败（只读目录）后打开/保存行为。验收：注入写失败断言
  用户可见提示；确认缺陷 → 登记 BUG + 修复
  （2026-08-03：缺陷确认——BUG-015；目录只读注入写失败 → 自动保存失败按段落
  提示一次（防逐键弹窗）+ 成功复位；setupStorage 失败启动即提示，保存提示
  区分「存储未就绪」与「无快照序号」；2 项失败注入测试先红后绿；App 93 全绿）
- [ ] T-055 快照合并原子写：ADR-023 守则 c 承认合并写非原子（写入中途崩溃截断
  快照）——实现 tmp + rename 原子写 + 崩溃注入测试（大内容写中途 kill）
- [x] T-056 存储损坏与迁移：损坏 buffer.sqlite（截断 / 乱字节）启动不崩、旧
  schema（user_version=0）迁移、只读目录、多实例并发同一 buffer.sqlite
  （2026-08-03：Core 4 项 + App 1 项契约测试——乱字节 / 截断头返回 Sqlite
  错误不 panic、v0 schema 迁移到 v1（迁移锚点推进）、只读目录失败干净、
  双连接同库已提交行跨连接可见、损坏缓冲启动提示可见（复用 T-054 路径）；
  未发现新缺陷（负结果）；App 100 + Core 131 + Bridge 20 全绿）
- [ ] T-057 多文档时序测试：真实窗口关闭（applicationShouldTerminateAfterLast
  WindowClosed 路径）、NSMenuItem action 触发、拖放、真实 IME 事件（T-050 只
  直接调方法，绕过了 run loop 时序）
- [x] T-058 状态机随机序列扩展：T-051 不变量测试加入 undo / redo / 丢弃 /
  崩溃恢复 / 打开同名路径操作类型与更多种子（固定种子确定性保持）
  （2026-08-03：操作空间 4 → 9 类、种子 3 → 6、步数 50 → 60；新增「快照序号
  全局唯一」不变量（BUG-010 泛化）；360 步全序列不变量成立（未发现新缺陷——
  负结果记录）；变异复验：还原 BUG-011 修复后 seed 7 立即报「缓冲行与未决
  登记不一致」，确认扩展测试抓住历史缺陷；App 96 全绿）
- [x] T-059 已知限制行为固化：T-024 前「打开第二个文件丢前一个未保存编辑」、
  T-029 前「恢复只呈现最新缓冲文档」——写当前行为契约测试（标注 ADR 限制），
  防止修复前意外漂移；对应切片落地时更新断言
  （2026-08-03：3 项契约测试落地——打开第二文件未决保留（T-046 后行为）、
  恢复只呈现最新且其余保持可管、忽略后全部缓冲文档可管；T-059 审计暴露
  BUG-016（忽略分支只登记 latest，ADR-013 v1.4 规则 3/4 违反）→ 修复 +
  回归；App 99 全绿）
- [ ] T-060 崩溃完整测试：进程级 kill -9 强杀（真实崩溃路径，非伪造哨兵）、
  恢复重复（缓冲行删除失败被吞）、崩溃循环空快照累积
- [ ] T-061 跨 UTC 午夜轮转测试：快照 seq 与日期解耦语义（跨日保存 seq 落到
  新日期前缀）——注入固定日期验证跨日行为，确认是否需修复
- [x] T-062 变异测试工具化：手工变异（T-051 流程）脚本化——变异点清单 +
  自动注入 / 恢复 / 结果记录，纳入每切片质量门禁（新增状态机逻辑先变异）
  （2026-08-03：scripts/mutations.json 清单 5 个确定性变异点（T-051 M1/M2/M3/M5
  + BUG-013 回归）+ scripts/mutate.py stdlib 注入/恢复/记录（变异点唯一性校验、
  预期判定、漂移即失败）；实测 5/5 全被捕获 ~10s；M6 挂起变体不可自动化已注明；
  新增状态机逻辑前先 `python3 scripts/mutate.py` 确认无盲区）

## Phase 8 — 性能与数据结构优化（2026-08-03 评估落地，ADR-006 v1.1）

> 来源：ADR-006 v1.1 评估（App 编辑热路径全量文本流 / Core 移动重建 /
> 中间编辑基准缺口）。门禁：任何结构替换必须先有基线（宪法 Rule 16）；
> 反转既有 ADR 决策（如 T-065）需用户确认。

- [ ] T-063 编辑热路径基准扩展（P0，ADR-006 v1.1 门禁前置）：1MB 文档中间
  insert / delete 10k、光标移动 1k、单次大 blob 缓冲 upsert——补齐中间编辑与
  移动成本数据，供 Gap Buffer / Rope / 维持 String 决策（现有 bench 只测末尾）
- [ ] T-064 move_cursor 行索引缓存（P1）：Editor 持有 Layout 缓存（编辑失效、
  移动复用），移动 O(n) → O(log n)；基准对比（Rule 16）+ ADR-006 备注修订后实施
- [ ] T-065 自动保存节流（P1）：连续按键合并缓冲写（~200ms 防抖），写频率降
  一个数量级；**反转 ADR-023「每次内容变更写入」粒度**（崩溃最多丢 ~200ms）——
  需用户确认
- [ ] T-066 SQLite WAL + synchronous 评估（P1）：缓解缓冲写放大（journal 写放大），
  配套崩溃恢复语义测试（ADR-013 崩溃保护论证复核）

## Phase 9 — 治理纠偏（2026-08-03 起，用户确认「按建议来」）

> 根因：功能互相打架（BUG-009~018 全部落在保存 / 恢复 / 关闭 / Frame 域）、
> API 不稳定（ADR-023 一日六反转）、新功能未做冲突扫描（T-069 × 关闭流、
> T-054 × 多文档、恢复 × id 契约）。纠偏三原则：**保存域冻结**（ADR-023 v1.7）、
> **单一关键路径**（Phase 7 / 8 并入功能线门禁与插队项，不再平行三线）、
> **Analysis 强制冲突扫描**（WORKFLOW，已生效）。

- [x] T-070 文档生命周期状态收拢：Core 新增 `Session` 模块（ADR-025）——
  DM 注册表 + 缓冲 + 快照 + 未决 / 快照序号 / 固化基线 / 失败提示的统一所有者；
  FFI 收敛为 session 单一入口（ADR-024 总账机械化）；关 B 只问 B、失败提示按
  文档隔离、`?? 1` 兜底与注册表泄漏修复（BUG-019~022）+ 恢复 id 复用碰撞与
  残留状态（BUG-023）；变异门禁 M1/M2/M5 迁至 Core + mutate.py 产物还原；
  App 111 + Bridge 20 + Core 148 全绿
- [x] 宪法 V1.5（2026-08-03 用户确认「直接落实」）：新增 Rule 17~21——域状态
  单一所有者 / 不变量由方法保证 / 功能先冲突扫描 / 语义冻结 / 公共面总账
  机械化；WORKFLOW 冲突扫描与 ADR-023 v1.7 / ADR-024 提升为宪法级
- [ ] 保存域语义冻结复核：T-065（自动保存节流，反转 ADR-023「每次内容变更
  写入」粒度）——**需用户确认**，确认后作为第一个走冻结流程的切片

## Phase 10 — 复审整改 II（2026-08-03 全仓审查，I-009 ~ I-016）

> 来源：2026-08-03 全仓复审（域归属 / 状态管理，结论见 [docs/issues.md](issues.md)）。
> 执行原则：先收拢域再接线；保存域改动受 ADR-023 v1.7 冻结流程约束（先确认方向）。

- [x] T-071 复审整改 II 问题登记（I-009~I-016，ADR-026 新增，2026-08-03）
- [x] T-072 行结构语义收拢（I-010，ADR-026）：Bridge 暴露 `layout_line_ranges`
  （扁平 start/end 对），Swift 删除 `lineRanges` 语义复刻；App 查找保持标准二分
  （Rule 9 / 11，不引入逐查询桥接拷贝）
- [ ] T-073 光标 / 组合几何收拢（I-011 / I-014 / I-016）：caret x/y 公式收为
  一个 App 层纯函数（消除三文件四处重复 + scrollX 补偿不一致）；内容宽度测量与
  渲染共享 shaping 缓存；`EditorModel.lines` 标注测试专用或删除（Rule 12）
- [ ] T-074 frame 域收拢（I-012 / I-013）：`FrameDocument`（frame + docId +
  fileName）单一所有者；`closeDecisionDocId` 改显式参数（Rule 17 同型模式回潮
  处置）
- [ ] T-075 文档内容单一事实来源（I-009，P0）：编辑会话 Buffer 与 Session 注册表
  副本统一（`content_changed` 回写注册表，或编辑直接持有注册表 Buffer）——
   **涉及保存域语义，需用户确认方向后实施（ADR-023 v1.7 冻结流程）**；建议作为
  T-024 激活文档接线前置
- 已排期承接：T-016（Theme 接线）/ T-024（Command 输入分发）/ T-029（恢复编排
  + shouldOfferRecovery 下沉，I-015）

## Task 编号规则

- 每个切片一个编号：`T-XXX`，按 Phase 顺序递增，不重复使用。
- Commit 必须引用 Task 编号与对应 ADR（如 `feat(core): Buffer 最小模型 (T-001, ADR-005)`）。
- 新增 / 合并 / 删除切片时，重新编号并更新本文件，同时记录到 Changelog。

---

顺序仅供参考，具体切片可能因 Analysis 阶段的新证据调整；任何调整必须先反映在 ADR 中。

当前下一步：**T-014 剪贴板（NSPasteboard，ADR-018 方向）→ 随后 T-019 软换行**。
单关键路径：功能线 T-014 → T-019 → T-020 → T-021 → T-024；Phase 7 剩余测试项
（T-053 / T-055 / T-057 / T-060 / T-061）作为对应功能切片的 Red→Green 前置；
Phase 8（T-063~T-066）只在功能线切片之间插队。

## 复审政策

- 每季度或每个里程碑完成后复审一次。
- 复审输出：新增 / 调整 / 删除切片；任何调整先写 ADR，再改本文件。
- 硬约束：只支持最新 macOS（ADR-002），不新增兼容性切片。
