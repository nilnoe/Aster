# Changelog — 版本变迁记录

本文件记录项目的版本与每次重要变更。

**版本策略：** 现阶段为 Beta，模板 `Beta V0.0.0`。小补丁递增末位，功能开发递增中间位（末位归零），首位恒为 0。尚未发布的变更维护在 `[Unreleased]`，发布时归档为 `[Beta V0.x.y]`。首个正式版为 `V1.0.0`。

**链接规则：** 每条变更必须链接到对应的 ADR 与 Roadmap 切片；反向可追溯。

---

## [Unreleased]

<!-- 尚未发布的变更维护在此；发布时归档到 [Beta V0.x.y]。 -->

### Added — 2026-08-02（T-034 复审问题登记）

- docs(issues)：新建 [docs/issues.md](../docs/issues.md) 审查问题登记表——2026-08-02
  全仓审查的 8 条问题（I-001~I-008，含 P0 CJK 光标边界缺陷、P1 保存缺口 / 渲染每帧
  O(n)、P2 死 API / 文档漂移 / 审计形式化 / Release 门禁缺口）逐一编号、附证据与
  处置切片；已知待办（T-014/016/024/028/029/031）只作完整性登记不重复编号
- docs(roadmap)：新增 Phase 6 复审整改切片 T-034~T-039（按严重度排序：P0 → P2 → P1 → 门禁）

### Fixed — 2026-08-02（T-035，BUG-008）

- fix(core)：Up/Down 光标在 CJK 行落非字符边界（BUG-008，根因分类：Implementation
  Bug）——`move_cursor` 字节列目标直接 `t_start + column.min(...)`，进入含多字节
  字符的行时可能落在字符内部（实测 `"abcd\n你好"` 行末 ↓ → head=9 在"好"内），
  违反 ADR-005「所有编辑偏移必须是字符边界」，后续 type_text / delete_backward
  全部失败、按键静默丢失。修复：所有移动统一 `floor_char_boundary(new_head.min(len))`
  钳制（Left/Right 等本就停在边界，floor 恒等）。回归测试：4 个手写用例（↓/↑ 进出
  CJK 行、Shift 扩展）+ 属性测试纳入 Up/Down 差分并显式断言「光标必须落在字符边界」
  不变量（`PROPTEST_CASES=3000` 实测通过）

### Changed — 2026-08-02（T-036 存量清理，I-004 ~ I-006）

- refactor(core)：撤销无消费者公共 API `Selection::clamp`（I-004，Rule 14 处置：
  接线或撤销——实际裁剪由 `Editor::set_selection` 的 floor_char_boundary 承担；
  [ADR-007](../docs/adr/ADR-007-selection-model.md) v1.1 备注记录移除，3 个对应测试删除）
- docs：校正计数漂移（I-005）——experience core/src 1676 → 1726、audits App 1483 →
  1615；T-032 审计行 commit 回填 d867ac7
- chore(repo)：I-006 核验纠正——`.DS_Store` 从未被 git 跟踪（`git ls-files` /
  `git log` 双重核验为空），.gitignore 早已覆盖，仅清理工作树残留；审查登记表
  标记「误报撤销」并记录核验方法（Rule 15：证据优先，find 输出不区分跟踪状态）

### Added — 2026-08-02（T-037 Disk 保存，I-002，ADR-023）

- feat(core)：`DocumentManager::save_text`（写回绑定路径 + 同步注册表副本；
  错误可见：UnknownBuffer / 新增 NoPath / SaveFailed）——Disk 保存最小语义
- feat(bridge)：`document_manager_save_text` FFI 1 项（成功返回 id，usize 透传）
- feat(app)：File 菜单「保存」⌘S（AppDelegate.saveDocument）；dirty 状态经
  `EditorModel.onChange`（type / delete / undo / redo 才置脏，移动与选区不触发），
  窗口标题「●」指示；关闭 / 退出未保存 → NSAlert 三选（保存 / 不保存 / 取消），
  保存失败阻止退出（ADR-004：失败可见）
- test：Core 5 项（写回 + 注册副本同步 + 未知 id + Scratch NoPath + 写失败
  IsADirectory）+ Bridge 2 项（保存往返、未知 id throws）+ App 2 项（菜单 ⌘S、
  onChange 语义）

### Changed — 2026-08-02（T-038 渲染数据路径重构，I-003）

- refactor(app)：消除渲染每帧 O(n)（I-003）——`EditorModel` 显示文本与行区间
  改为按编辑 / 组合失效缓存（渲染帧内多次读取零成本，不再每帧经 Bridge 全文
  往返 + 全量 split）；`lineText(_:)` 只切可见行；`lineIndex` 手写二分替代线性
  扫描（O(log n)）；`VertexBuilder` 每个可见行每帧只 shaping 一次（选区 / 字形 /
  光标三处复用原两次 `LineLayout`）
- test(app)：3 项——lineIndex 行边界 / 空文本语义、显示缓存随编辑 / 组合 / 移动
  失效、lineText 反映最新内容；既有 47 项渲染 / 像素测试全部保持绿（行为不变）

### Changed — 2026-08-02（T-039 审计与门禁加固，I-007 / I-008）

- ci(docs)：CI-Docs 新增审计完整性机械检查（Rule 15 扩展，I-007）——audits.md
  「本切片」未回填行只允许当前切片一行（不得累积），表内 commit 必须真实存在
  （checkout 改 fetch-depth 0 提供完整历史）；审计从"人工回填自觉"变为"合入前提"
- ci(release)：CI-Release gates 与日常 CI 对齐（I-008）——补上 swift-format
  app/Sources lint、fuzz（PROPTEST_CASES=3000）、规模预算（core + app）、docs
  完整性（ADR 索引 + 审计表）、基准回归（--quick + bench-baseline 10% 阈值）
- docs(audits)：审计规则增加"行为证据必填"（只数行数 / API 数的审计不算审计）；
  回填 T-035~T-038 审计 commit（29bdf9d / 6ceb0fe / 135f44a / 7220747）
- docs(pr)：PR 模板审计区增加行为证据与审计行必填项（T-039）

### Changed — 2026-08-02（T-040 保存目标改为 SQLite 快照，ADR-023 v1.2，用户确认）

- **反转（用户确认）**：T-037 的「Cmd+S 写回磁盘绑定路径」提前实现了未来文件系统
  切片的能力；按用户指示改为 **Cmd+S 自动保存到 SQLite**（ADR 总纲 §5/§6 既定方向：
  SQLite 承担 Scratch / 内部状态，无需用户指定路径）
- feat(core)：`Store::open_next` / `open_latest`——按「日期+序号」轮转
  （`aster-YYYY-MM-DD-<seq>.sqlite`），**单日内可写入多个文件**（用户指示：
  每次保存一个新快照文件，同日保存历史 = 多版本；seq = 当日最大序号 + 1，
  容忍缺号；latest = 最高序号）；civil date 用标准算法（不引 chrono，Rule 7）
- feat(bridge)：Store FFI 4 项（store_open_next / store_open_latest /
  store_save_scratch / store_load_scratch）；撤销 document_manager_save_text
- feat(app)：Cmd+S 每次经 Store 新建快照文件（保存键 = BufferId，演示 Buffer 也可
  保存）；默认目录 `~/Library/Application Support/Aster`，`ASTER_STORE_DIR` 覆盖
  （StorePaths，纯函数可单测）；dirty 标题与关闭保护保留
- refactor(core)：撤销 `DocumentManager::save_text` + `NoPath` / `SaveFailed`
  （Rule 14：无消费者；未来文件系统切片重新引入，ADR-023 v1.2 Deferred）
- test：Core 6 项（序号递增 / 缺号跳序 / 目录自动创建 / latest 往返 / 无文件 None /
  civil date 已知 epoch）+ Bridge 2 项（保存读回闭环、双快照 latest 胜出）+ App 2 项
  （StorePaths 默认目录与环境变量覆盖、bufferId 保存键）

### Changed — 2026-08-02（T-041 缓冲 + 快照保存模型，ADR-023 v1.3，用户指示）

- **模型修正（用户指示 2026-08-02）**：Cmd+S 不再新建文件——**Cmd+N 创建新快照**
  （`aster-YYYY-MM-DD-<seq>.sqlite`，日期+序号）；**编辑自动保存到缓冲文件**
  `buffer.sqlite`（崩溃保护，无需按保存）；**Cmd+S = 合并缓冲 → 当前快照**（提交 /
  固化）；dirty「●」= 缓冲 ≠ 快照（未提交编辑），退出保护基于此
- feat(core)：`Store::next_snapshot`（创建并返回序号）/ `open_snapshot`（合并目标）/
  `open_buffer`（自动保存工作区）；`open_latest` 保留（T-028 恢复）
- feat(bridge)：Store FFI 6 项 + `document_manager_open_scratch`（ADR-001 v1.2：
  Cmd+N 经 DM 分配唯一保存键）
- feat(app)：File 菜单「新建」⌘N；内容变更自动写缓冲 + 置 dirty；Cmd+S 合并；
  **修复 BUG-009**——onChange 统一在 makeModel 接线（启动默认 Buffer 也生效，
  dirty「●」与退出保护恢复）
- test：Core 6 项（快照序号 / 缺号 / open_snapshot 往返 / buffer 往返 / latest /
  civil date）+ Bridge 3 项（合并读回、缓冲往返、scratch id 递增）+ App 1 项
  （菜单 ⌘N）

### Changed — 2026-08-02（T-042 快照改为纯文本，ADR-023 v1.4，用户反馈）

- **修正（用户反馈）**：快照文件是 .sqlite 数据库时无法在 Buffer 打开——提交产物
  必须是可打开的文本文件。**快照改为纯文本** `aster-YYYY-MM-DD-<seq>.txt`
  （Cmd+N 创建、Cmd+S 合并缓冲文本进当前快照，可直接在 Buffer / 任意编辑器打开）；
  SQLite 只保留缓冲（buffer.sqlite，崩溃保护）
- feat(core)：新增 `snapshot` 模块（`Snapshot`：日期 + 序号轮转、创建 / 写 / 读 /
  latest_seq；复用 store 的 today_iso）；Store 移除 SQLite 快照 API（next_snapshot /
  open_snapshot / open_latest，Rule 12/14：无消费者立即删除，职责回归 SRP）
- feat(bridge)：Snapshot FFI 5 项（snapshot_new / snapshot_create_next /
  snapshot_write / snapshot_read + 缓冲 store_open_buffer / save / load）；
  移除 store_next_snapshot / store_open_snapshot / store_open_latest
- feat(app)：Cmd+N / Cmd+S 改走文本快照；缓冲自动保存不变
- test：Core 4 项（snapshot 模块：序号递增 / 缺号 / 纯文本往返 / latest）+ Bridge
  3 项（快照往返、.txt 断言、缓冲往返）

### Added — 2026-08-02（T-018 水平滚动）

- feat(app)：水平滚动（T-018，[ADR-019](../docs/adr/ADR-019-viewport-scroll-and-wrap.md)）——
  新增 `Viewport` 视口状态（scrollX / scrollY、钳制、光标可见性、可视行窗口，
  纯几何可单测）；触控板双指 / Shift+滚轮横向平移（macOS 在事件层已交换
  Shift+滚轮轴向，视图直接读 scrollingDeltaX，不手写 Shift 分支）；光标移出
  右边缘自动横向滚入视野（含组合文本末尾，BUG-004 语义）；内容宽度按可见行
  最大宽度计算（不取全文档最宽行）；鼠标命中换算与 IME 候选框（firstRect）
  跟随 scrollX
- refactor(app)：MetalView / TextRenderer 拆分（宪法 Rule 3，T-018 前置）——
  IME 客户端移到 `MetalView+Input.swift`（298 → 258 行），顶点生成抽为
  `VertexBuilder`（292 → 130 + 200 行）；与 MetalPipeline 拆分同一模式（ADR-016）
- test(app)：`ViewportTests` 7 项（钳制 / 光标可见性 / 可视行窗口）；渲染器
  离屏质心位移像素测试（scrollX 6pt @2x → 质心左移 12px）；MetalView 滚轮
  轴映射测试（CGEvent 构造，量级断言不依赖「自然滚动」偏好方向）

### Fixed — 2026-08-02

- fix(app)：横向滚动后行末光标消失 / 回车后左侧边距消失（BUG-006，
  根因分类：Implementation Bug）——`Viewport.ensureCursorVisible` 把光标滚到
  「恰好贴边」：右缘时光标 quad（2pt 宽）整体在视口外；左缘（回车到新行行首）
  时 scrollX 被设为 cursorX，12pt 左边距被滚出视口。修复：左右各预留 12pt
  边缘留白（与渲染层 `leftPadPts` 对称，新增 `rightPadPts`），内容宽度计入
  右留白（否则滚动到最右时 clamp 吃掉留白，光标仍会贴边）。回归测试：Viewport
  边缘留白单测、MetalView 接线测试（行末右缘 / 回车后行首左缘）、离屏渲染像素
  测试（行末光标列必须落在右缘 12pt 留白内）
- fix(app)：拼音组合期间组合文本超出右缘不自动横向滚动（BUG-007，
  根因分类：Implementation Bug）——`setMarkedText`（IME 每次组合更新都走这里）
  只更新组合与重绘，未调用 `scrollCursorIntoView`（与提交路径 `insertText`
  不一致），组合末尾光标（BUG-004 语义：光标 + 组合长度）超出视口。修复：
 组合更新时同步滚动，组合末尾光标保持在右缘 12pt 留白内。回归测试：组合
  更新后 scrollX 必须增大且组合末尾光标 ≤ 视口宽 - 右留白

### Added — 2026-08-02（T-015 文件打开接线）

- feat(app)：文件打开接线（T-015，[ADR-001](../docs/adr/ADR-001-document-manager.md) v1.1）——
  DocumentManager 首次进产品（Rule 14 存量处置推进）：File 菜单「打开…」（Cmd+O，
  NSOpenPanel）与文件拖入（NSDraggingDestination，`.fileURL`）统一经
  DocumentManager Disk 源读取内容 → 新建 Buffer + Editor 会话替换当前内容；
  打开失败 NSAlert 可见（ADR-004），窗口标题跟随文件名
- feat(bridge)：DocumentManager Bridge FFI 3 项（`document_manager_new` /
  `document_manager_open_disk` / `document_manager_text`；ADR-001 v1.1）——
  id 以 usize 透传（swift-bridge 0.1.59 的 Result C 结构命名对 u64 未实现，
  实测 todo!() 崩溃）；Core 新增 `pub(crate)` 访问器 `DocumentManager::text(id)`
- test(bridge)：DocumentManager 契约 2 项（Disk 打开 + CJK 往返；路径不存在
  必须 throws）；core 单测（文本访问器 + 未知 id）；app 单测（load 替换会话 +
  视口重置）

### Added — 2026-08-02（T-033 fuzz 扩展 + 基准回归告警）

- [ADR-021](../docs/adr/ADR-021-performance-benchmarks.md) v1.1 — 反转「CI 不跑
  基准」：新增 `CI-Bench` 作业（`cargo bench -- --quick` + 仓库内基线对比，回归
  超 10% 即红；10µs 以下项跳过；全量测量仍以本地 release 为准）。反转经用户
  确认（T-033 遗留项）
- [ADR-022](../docs/adr/ADR-022-property-tests-audit-log.md) v1.1 — fuzz 语义 =
  扩展属性空间（不引入 cargo-fuzz，Rule 9）：emoji / CJK / 换行 / 组合字符输入
  + ≤80 步操作序列；CI-Rust 增加 `PROPTEST_CASES=3000` property 专项运行
- feat(bench)：`bench-baseline/` 提交本地 release 测量的 17 项基线（Apple M4 /
  macOS 26.5.1）+ `scripts/bench-regression.py`（stdlib 对比脚本，criterion 自带
  baseline 对比不因回归失败退出，0.8.2 实测）
- feat(test)：`editor_matches_model_fuzz_unicode` / `editor_undo_redo_fuzz_multiline`
  两个新属性测试（多行 + 多字节输入下差分与 undo/redo 往返契约）

### Changed — 2026-08-02（Beta V0.2 规划）

- ci：新增 `CI-Release` 发布流水线（[ADR-020](../docs/adr/ADR-020-ci-release-pipeline.md)）——
  打 `Beta-V*` tag 自动跑门禁 → 构建 release → 打包 Aster.app zip → 附加到 GitHub
  Release（版本取自 core/Cargo.toml 单一来源）；手动 dispatch 可验证到 artifact 步骤

- docs(roadmap)：基础功能完善方向重构（[ADR-018](../docs/adr/ADR-018-foundation-polish.md)）——
  T-014 移除「深浅色跟随」（固定深色 + Lua 主题），新增 Phase 3 渲染与编辑打磨
  （sRGB+gamma、光标、DeleteForward/词移动、双击/三击选词、平滑滚动/IME 定位、
  criterion 基准体系）并重新编号
- [ADR-018](../docs/adr/ADR-018-foundation-polish.md) — 方向决策：深浅色不跟随系统
  （Rule 9 论证）、渲染质量优先、光标为 T-013 验收缺口（BUG-002）、基准体系前置
- docs(roadmap)：滚动与换行决策落地（[ADR-019](../docs/adr/ADR-019-viewport-scroll-and-wrap.md)）——
  新增 T-018 水平滚动（v1 默认能力，ADR-006 原方案落地）、T-019 软换行（用户可选、
  默认关闭）；Phase 3~5 重新编号（T-020 编辑细节 / T-021 选词 / T-022 滚动与 IME /
  T-023 基准 / T-024~T-028 Overlay / T-029~T-030 稳定与发布）
- [ADR-019](../docs/adr/ADR-019-viewport-scroll-and-wrap.md) — 视口滚动与软换行：
  水平滚动为 v1 默认；软换行默认关闭的用户选项（ADR-006 修订，经用户确认）；
  视觉折行属 App 渲染层，Core Layout 边界不变（ADR-009）

### Changed — 2026-08-02（治理与性能优先级，用户确认）

- [docs/constitution.md](../docs/constitution.md) — Version 1.4：新增 Rule 13~16
  （ADR 必须闭环 / 无消费者的公共接口禁止交付 / 文档完整性是机械门禁 /
  性能决策必须数据驱动）。修订依据：复审发现的四类失败模式（ADR-004 失约、
  零消费者模块提前建成、ADR-018 索引漏登、基准长期 TBD）；经用户确认。
- docs(roadmap)：未接线模块接线计划落地（宪法 Rule 13 / 14 处置）——
  DocumentManager → T-015 / T-028；Command / Event → T-024；Lua → T-024；
  Store → T-028 / T-029；Theme → T-016 / T-024；ADR-004 日志落地 → 新增 T-031；
  T-023 提升为数据结构决策前置门禁（宪法 Rule 16）
- docs(adr)：ADR-006 更新——任务编号校正（T-020 → T-023 / T-021 → T-029）；
  新增「数据结构评估框架」（评估维度 + 决策门禁，宪法 Rule 16 落地）
- ci(docs)：新增 CI-Docs 作业（ADR 索引完整性 + 索引链接检查；宪法 Rule 15 机械执行）
- ci(release)：CI-Release 增加版本一致性门禁（tag 与 core/Cargo.toml 必须一致；Rule 15）
- docs(release)：发布清单增加「归档一致性」检查（tag 内容与 Changelog 归档一致）
- docs(workflow)：WORKFLOW Architecture / Benchmark 步骤回链 Rule 13 / 14 / 16

### Added — 2026-08-02（T-023 性能基准体系）

- [ADR-021](../docs/adr/ADR-021-performance-benchmarks.md) — 性能基准体系：criterion
  （dev-dependency）+ 两组基准（编辑内核 / 管线），稳定测量规则（release + 机器记录 +
  CI 不跑）；ADR-006 数据结构评估框架的数据来源（宪法 Rule 16 落地）
- feat(bench)：T-023 落地——编辑内核组 10 项 + 管线组 7 项基准，docs/benchmarks.md
  回填首个稳定基线（criterion 0.8.2；Apple Silicon arm64 / macOS 26.5.1）；
  编辑热路径基准即为 ADR-006 存储决策的对照数据

### Added — 2026-08-02（T-032 测试与审计加固）

- [ADR-022](../docs/adr/ADR-022-property-tests-audit-log.md) — 属性测试（proptest）
  与审计记录制度：回应复审「测试不足 / 审计空转」意见——proptest 覆盖 UTF-8 边界、
  任意操作序列与 undo/redo 往返；审计结论强制落表 docs/audits.md
- feat(test)：T-032 —— Buffer（插入边界 / 删插 round-trip）、Editor（与朴素模型
  差分、undo/redo 往返）、Layout（行结构不变量）属性测试落地
- docs(workflow)：WORKFLOW Audit 步骤要求审计结论写入 docs/audits.md，无记录视为
  未执行
- docs(audit)：新增 docs/audits.md 审计登记表（含全仓复审与 T-023 审计行，
  ADR-022 决策 3 落地）

## [Beta V0.1.1] — 2026-08-02

**补丁版：** 上一版（Beta V0.1.0）发布后的缺陷修复——渲染覆盖层不可见、
IME 提交与光标、鼠标指针。版本号 0.1.0 → 0.1.1（core_version 单一来源）。

### Fixed — 2026-08-02

- fix(app)：文本区鼠标指针为箭头而非 I 型（BUG-005，根因分类：Implementation Bug）——
  MetalView 未注册光标矩形；`resetCursorRects` 增加 `addCursorRect(bounds, .iBeam)`
- fix(app)：IME 组合期间光标不跟随（BUG-004，根因分类：Implementation Bug）——
  组合文本内联于光标处，光标却画在组合起点；改为画在组合文本末尾
  （cursor + composition 长度）。回归测试：离屏渲染后断言光标竖直线出现在
  "ab你好" 末尾列（Red→Green）
- fix(app)：拼音组合期间回车不提交（BUG-003，根因分类：Implementation Bug）——
  keyDown 无条件拦截 keyCode 36 直连 `typeText("\n")`（会清空组合），输入法得不到
  回车键；数字键选词正常正因走 `interpretKeyEvents`。修复：组合激活期间所有按键
  交还输入法。回归测试注入回车事件断言组合保留、Buffer 无换行
- fix(app)：光标 / 选区高亮 / IME 下划线不可见（BUG-002，根因分类：Implementation Bug）——
  图集纯白像素画在了用户坐标 y=0（对应纹理最后一行），而纯色 quad 的 UV 采样纹理
  行 0 → 全部透明。修复：白像素画到用户 y = H-1..H（纹理行 0）；新增离屏渲染像素
  回归测试（TextRenderer 与 on-screen 共享顶点构建与编码，`waitUntilCompleted` 后读回）

### Added — 2026-08-02

- feat(app)：光标闪烁（T-017，ADR-018）——MetalView 0.5s 计时器翻转相位，
  渲染层按相位画光标；离屏渲染路径（`renderOffscreen`）供像素回归测试使用

### Changed — 2026-08-02

- chore(version)：core 版本 0.1.0 → 0.1.1（Beta V0.1.1 补丁版；Changelog、
  应用版本（core_version）、git tag 三处同步）

## [Beta V0.1.0] — 2026-08-02

**首个功能版本：** T-001 ~ T-013 全部落地——文档体系、Rust Core 编辑内核、
swift-bridge 桥接、AppKit 壳、Metal 文本渲染与编辑循环可用。
目标环境：macOS 26.5.1 / Apple M4（ADR-002：仅支持最新 macOS）。

### Fixed — 2026-08-02

- fix(app)：Retina 下 Metal 文本渲染模糊（BUG-001，根因分类：Implementation Bug）——
  字形图集原按点（pt）尺寸栅格化而 quad 按像素绘制，2× 缩放 + 线性采样导致发糊；
  改为按像素尺寸栅格化（`CTFontCreateCopyWithAttributes` 按 scale 缩放），缓存键含
  pixelSize；quad 吸附像素网格 + nearest 采样；回归测试断言 2× 图集矩形大于 1×

### Added — 2026-08-02（续 T-013）

- feat(core)：编辑循环（T-013，ADR-017）——新增 `Editor` 模块（Buffer + Selection +
  History 协调者）：`type_text`（选区替换，`EditOp::Replace` 一次 undo 撤销）、
  `delete_backward`（UTF-8 字符边界）、`move_cursor`（8 方向 + Shift 扩展，行/列
  字节列语义）、`undo`/`redo`（光标折叠到操作点）、`select_all`、`set_selection`
- [ADR-017](../docs/adr/ADR-017-editor-loop.md) — 编辑循环决策：编辑语义全部落 Core，
  命令/激活文档接线推迟到 T-015，IME 内联组合模型，滚动为视图状态
- feat(app)：Metal 编辑视图（T-013，ADR-017）——方向键/退格/回车直连 Core、
  IME 组合文本内联光标处 + 下划线、点击定位/拖选、滚轮滚动与光标可见性、
  Edit 菜单撤销/重做/全选接线；新增 `LineLayout`（shaping 一次多查询）与
  `MetalPipeline`（管线资源拆出，Rule 3）

### Added — 2026-08-02

- feat(app)：Metal 文本渲染管线 spike（T-012，ADR-016）——空白视图替换为 MTKView；
  Core Buffer 文本经 **CoreText shaping → 字形图集纹理 → Metal quad 绘制**全链路；
  Bridge 新增 `layout_line_starts`（行结构复用 Core Layout，ADR-009）；视图实现
  `NSTextInputClient`：IME 组合文本带下划线渲染，提交经 `buffer_insert` 写回 Core；
  CJK 多行往返在 Bridge 测试验证，字形图集做像素级读回验证（无 GPU 时跳过）；
  可测逻辑抽离为 `EditorModel`（输入状态机）与 `AtlasPacker`（图集分配器）
- [ADR-016](../docs/adr/ADR-016-metal-text-rendering.md) — Metal 文本渲染管线：
  字形缓存（按需图集 + font+glyph 键）与 GPU 缓冲格式（32B/顶点 quad 流）落定，
  渲染归 App、纯逻辑归 Core 的边界固化
- [ADR-006](../docs/adr/ADR-006-data-structures.md) — 「字形缓存 / GPU 缓冲格式」
  从未确定改为已确定（引用 ADR-016）；软换行维持不做
- 项目启动：文档体系建立
  - [docs/constitution.md](../docs/constitution.md) — 项目宪法（12 条不可违反原则）
  - [docs/adr/ADR-001-document-manager.md](../docs/adr/ADR-001-document-manager.md) — DocumentManager（Status: Proposed）
  - [WORKFLOW.md](../WORKFLOW.md) — 11 步垂直切片开发管线
  - [docs/roadmap.md](../docs/roadmap.md) — 开发路线 TODO
  - [docs/changelog.md](../docs/changelog.md) — 本文件
  - [AGENTS.md](../AGENTS.md) — 执行约定
- [docs/constitution.md](../docs/constitution.md) — Version 1.1：新增 Rule 10（注释必须有决策依据）与修订流程
- [docs/constitution.md](../docs/constitution.md) — Version 1.2：新增 Rule 11（禁止重复造轮子 / Reuse First）
- [docs/constitution.md](../docs/constitution.md) — Version 1.3：修订 Rule 3（上帝文件禁令）+ 新增 Rule 12（规模预算：单文件 / 模块 / 总量上限、扩容与精简条件、封装与接口）
- [docs/scale.md](../docs/scale.md) — 规模预算执行细则（硬性上限表、预警 80%、扩容 ≤25%、精简五触发条件）
- [docs/experience.md](../docs/experience.md) — 经验沉淀：项目现状速览、工作方式、Rust/Clippy/测试经验、架构决策速查、踩坑记录
- 新增 ADR：
  - [ADR-002](../docs/adr/ADR-002-macos-support.md) — macOS 支持策略：仅最新版，零兼容负担（Accepted）
  - [ADR-003](../docs/adr/ADR-003-plugin-trust.md) — 插件安全模型：默认信任，第一阶段不沙箱（Accepted）
  - [ADR-004](../docs/adr/ADR-004-logging-crash.md) — 日志与崩溃上报：os_log + tracing，默认无遥测（Accepted）
- 许可：新增 MIT License（Copyright 2026 nilnoe）
- 文档体系扩展：
  - [docs/adr/README.md](../docs/adr/README.md) — ADR 索引（编号规则、状态机、触发规则）
  - [docs/adr/_template.md](../docs/adr/_template.md) — ADR 模板
  - [.github/PULL_REQUEST_TEMPLATE.md](../.github/PULL_REQUEST_TEMPLATE.md) — PR 模板（宪法 Rule 6 / 9 强制项）
  - [docs/benchmarks.md](../docs/benchmarks.md) — 性能基线记录
  - [docs/bug-workflow.md](../docs/bug-workflow.md) — 缺陷处理流程（根因分类 + 回归测试先行）
  - [docs/bug-workflow.md](../docs/bug-workflow.md) — Bug Report 阶段新增 Bug ID（必填）与 Upstream Reference（可选，含版本与访问日期）
  - [docs/bugs.md](../docs/bugs.md) — 缺陷登记表（内部登记）
- 工程基础设施：
  - [.github/workflows/ci-rust.yml](../.github/workflows/ci-rust.yml) + [ci-swift.yml](../.github/workflows/ci-swift.yml) — CI：Rust 与 Swift 门禁机械执行（按路径触发）
  - [.github/workflows/ci-rust.yml](../.github/workflows/ci-rust.yml) — 新增 Scale Budget 检查（单文件 ≤ 300 行、core 总量 ≤ 20k）
  - [.github/PULL_REQUEST_TEMPLATE.md](../.github/PULL_REQUEST_TEMPLATE.md) — 新增规模预算必填项
  - [DEVELOPING.md](../DEVELOPING.md) — 构建与运行
  - [docs/testing.md](../docs/testing.md) — 分层测试策略
  - [docs/release.md](../docs/release.md) — 发布流程（Trunk-based + 发布清单）
  - [docs/dependencies.md](../docs/dependencies.md) — 依赖维护政策（新增 / 升级 / 安全）
  - [SECURITY.md](../SECURITY.md) — 漏洞报告与信任模型
  - [docs/roadmap.md](../docs/roadmap.md) — 新增复审政策与 ADR-002 硬约束
- [docs/release.md](../docs/release.md) — 版本策略：Beta V0.0.0 模板（末位补丁 / 中间位功能 / 首位恒 0），首个正式版 V1.0.0
- [docs/roadmap.md](../docs/roadmap.md) — 切片编号规则（T-XXX）与编号表，Commit 必须引用 Task 与 ADR
- feat(core)：Buffer 最小模型（T-001，ADR-005）——`Buffer` / `BufferId` / `BufferError`，UTF-8 字符边界安全，13 个契约测试
- [ADR-006](../docs/adr/ADR-006-data-structures.md) — 核心数据结构决策矩阵：已确定（Selection / Undo 栈 / 注册表 / 存储决策机制）+ 未确定（存储算法 / 行索引 / 多光标 / mmap 等，含原因）
- [ADR-001](../docs/adr/ADR-001-document-manager.md) — 状态 Proposed → Accepted：确定 `open` / `close` 签名与支撑类型（`DocumentSource` / `DocumentManagerError`）；激活状态延迟到 T-013；SQLite 落盘延迟到 T-009 / T-021
- feat(core)：DocumentManager `open` / `close`（T-002，ADR-001）——注册表 + 生命周期；`DocumentSource`（Disk / Scratch）；错误可见（ADR-004）；8 集成 + 5 单元测试
- feat(core)：Undo / Redo（T-004，ADR-008）——`History` + `EditOp`（inverse-operation 栈）；相邻 Insert 合并；失败时栈不变；11 个契约测试
- feat(core)：Layout 逻辑行模型（T-005，ADR-009）——`Layout::build` / `line_count` / `line_range` / `line_at`；不可变快照索引；10 个契约测试
- [ADR-006](../docs/adr/ADR-006-data-structures.md) — 行索引与软换行从未确定改为已确定（v1 不可变索引、无软换行；替换触发点 T-020）
- feat(core)：Selection 模型（T-003，ADR-007）——`anchor` + `head` 字节偏移，光标即 head，10 个契约测试
  - [docs/glossary.md](../docs/glossary.md) — 术语表
  - [ARCHITECTURE.md](../ARCHITECTURE.md) — 架构总览
  - [WORKFLOW.md](../WORKFLOW.md) — 新增 Commit Message 约定（Conventional Commits）
- [ADR-010](../docs/adr/ADR-010-theme-model.md) — Theme 模型与 Theme DSL（固定四角色 + `rgba()` 语法，Accepted）
- feat(core)：Theme 模型与 Theme DSL 解析（T-006，ADR-010）——`Color` / `Theme` / `ThemeError`；`Theme::parse` 行级解析；12 个契约测试
- [ADR-011](../docs/adr/ADR-011-command-event.md) — Command 系统与 Event 总线（std `Fn` 注册表 + 订阅 id 总线，Accepted）
- [ADR-006](../docs/adr/ADR-006-data-structures.md) — 「命令表 / 事件总线结构」从未确定改为已确定（ADR-011 决策）
- feat(core)：Command 系统与 Event 总线（T-007，ADR-011）——`CommandRegistry` / `CommandContext` / `EventBus` / `Event::BufferEdited`；9 个契约测试
- [ADR-012](../docs/adr/ADR-012-lua-runtime.md) — Lua Runtime（mlua 0.12，lua54 + vendored）与 Plugin API（Accepted）
- [ADR-011](../docs/adr/ADR-011-command-event.md) — 修订 v1.1：处理器签名改为可失败，`CommandError` 新增 `HandlerFailed`（T-008 提前触发）
- feat(core)：Lua Runtime 与 Plugin API（T-008，ADR-012）——`LuaRuntime`（load / export_commands / export_subscribers / get_global）；Lua 侧 `aster.register_command` / `aster.subscribe`；6 个契约测试；新增依赖 mlua（Rule 7 / 8 论证见 ADR-012）
- [ADR-013](../docs/adr/ADR-013-sqlite-store.md) — SQLite 存储层（rusqlite 0.40 bundled，scratch + session 两表，Accepted）
- [ADR-001](../docs/adr/ADR-001-document-manager.md) — 备注更新：存储层由 T-009 交付，Scratch 工作流接线在 T-019、Session / Crash Recovery 编排在 T-021
- feat(core)：SQLite 存储层（T-009，ADR-013）——`Store`（scratch upsert / session 事务整表替换）；`SessionDocument`；9 个契约测试；新增依赖 rusqlite（Rule 7 / 8 论证见 ADR-013）
- [ADR-014](../docs/adr/ADR-014-swift-bridge-spike.md) — Swift Bridge 接入 spike（swift-bridge 0.1.59 + swift-bridge-build，Accepted）
- feat(bridge)：swift-bridge 接入 spike（T-010，ADR-014）——core `bridge` 模块（Buffer / BufferId 桥接面 + `buffer_insert` 适配）；bridge/ Swift Package（systemLibrary C 模块 + staticlib 链接）；3 个 XCTest 契约测试；新增依赖 swift-bridge、swift-bridge-build（Rule 7 / 8 论证见 ADR-014）
- ci(swift)：CI-Swift 作业改为先跑 `bridge/build.sh` 再 lint / test（生成绑定 + staticlib 链接进测试）
- [ADR-015](../docs/adr/ADR-015-appkit-shell.md) — AppKit 壳（程序化启动、最小菜单集、版本单一来源，Accepted）
- feat(app)：AppKit 壳（T-011，ADR-015）——`main.swift` 程序化启动 + 空白 NSWindow + 最小菜单（App / Edit / Window）；关于面板版本号经 Bridge 来自 Core；4 个 XCTest（含 App → Bridge → Core 垂直线程）；Swift App 规模预算自此生效
- ci(swift)：CI-Swift 增加 app 包 lint 与 test
- fix(build)：`swift run` 构建警告清零（T-011 后续）——Swift 6 下生成绑定 retroactive conformance 警告经目标级 `-suppress-warnings` 抑制（生成代码目标）；部署目标统一为 macOS 26（manifest `.v26` + `MACOSX_DEPLOYMENT_TARGET=26.0`），消除 32 条链接警告
