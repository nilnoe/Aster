# Issues — 审查问题登记表

全仓审查（2026-08-02）发现的问题登记。每条问题一个编号（I-XXX），与修复切片 /
Bug 编号双向可追溯；修复完成时回填状态与 Commit，**不清理历史行**（问题登记也是
审计证据，Rule 13 精神：处置留痕）。

状态：`Open`（已登记未处置）· `Fixing`（切片进行中）· `Fixed`（已修复并合入）·
`Deferred`（有明确归属切片但未排期）。

| ID | 严重度 | 问题 | 证据 / 现象 | 处置 | 状态 | 修复 Commit |
| --- | --- | --- | --- | --- | --- | --- |
| I-001 | P0 | Up/Down 跨 CJK 行光标落在字符内部（非 UTF-8 边界），后续编辑全部报错、按键静默丢失 | `core/src/editor.rs` 字节列语义未钳制边界；实测 `"abcd\n你好"` 行末 ↓ → head=9（"好"内部），违反 ADR-005 UTF-8 底线；属性测试差分明确排除 Up/Down，无覆盖 | BUG-008 / T-035 | Fixed | 29bdf9d |
| I-002 | P1 | 编辑器没有保存能力：关窗即丢编辑；Roadmap 无保存切片 | 全仓无持久化路径；T-015 只有 open | T-037 → T-040 → T-041 → T-042（ADR-023 v1.4：Cmd+N 纯文本快照 / 自动保存缓冲 / Cmd+S 合并） | Fixed | 135f44a + d28cb9b + c4b4710 + b8cd54b |
| I-003 | P1 | 渲染数据路径每帧 O(n)：全文 Bridge 拷贝 + 全量切分 + 线性行扫描 + 可见行每帧双重 shaping | `EditorModel.lines/lineByteRanges` 每帧全量重建；`VertexBuilder` 选区循环与字形循环各建一次 `LineLayout`；benchmarks.md 渲染帧时间 TBD，从未被基准覆盖 | T-038 | Fixed | 7220747 |
| I-004 | P2 | 无消费者公共 API `Selection::clamp` 滞留 main（Rule 14 禁止；Rule 12 死代码立即删除） | 全仓零调用，实际钳制由 `set_selection` 的 floor_char_boundary 承担 | T-036 | Fixed | 6ceb0fe |
| I-005 | P2 | 文档计数漂移与审计行未回填：experience 写 core 1676 行（实 1731）；audits 写 App 1483（实 1615）；T-032 审计行 commit 列仍为「本切片」（d867ac7） | Rule 15 机械门禁只覆盖 ADR 索引，未覆盖 experience / audits 计数 | T-036 | Fixed | 6ceb0fe |
| I-006 | P2（误报） | 疑似 `.DS_Store` 入库 | 核验纠正：`git ls-files | grep -i ds_store` 为空、`git log -- .github/.DS_Store` 无提交——从未入库，.gitignore 早已覆盖；仅工作树残留（find 输出误判为已提交） | T-036 | 撤销（误报） | 无（无需修复；工作树残留已清理） |
| I-007 | P2 | 审计流于形式：审计行在 feature commit 之后回填（T-018/T-015/T-033），不是提交前门禁；全部「Pass（自审）」；无 CI 机械检查 audits.md | git log：794f5f6 / f4d2fba / b760698 均为事后回填 commit；T-032 行至今未回填 | T-039 | Fixed | 3171806 |
| I-008 | P2 | CI-Release 门禁弱于日常 CI：不 lint app/Sources、不查规模预算、不跑 fuzz、不跑 docs 完整性、不跑基准回归 | `ci-release.yml` gates job 与 ci-rust/ci-swift/ci-docs/ci-bench 对比 | T-039 | Fixed | 3171806 |
| I-009 | P0 | 文档内容双副本：Session/DM 注册表 Buffer 与 App Editor Buffer 各持一份文本，编辑后注册表副本失鲜（content_changed 只写 SQLite 不回写注册表）——T-024 激活文档 / T-028 Scratch 接线后任何经 session_text 的读取会读到陈旧内容 | `AppDelegate.open` 另建 Buffer 经 editor_new 进 Editor（app/Sources/AsterApp/AppDelegate.swift:199-202）；`Session::content_changed`（core/src/session.rs:104）只写缓冲不更新 dm 副本；`Session::text` 读注册表 | T-075（**需用户确认**，ADR-023 v1.7 保存域冻结） | Open | |
| I-010 | P1 | 行结构语义双实现：Core `Layout::line_range`/`line_at` 与 Swift `EditorModel.lineRanges`/`lineIndex` 复刻（`\n` 归属、末行边界双所有者） | core/src/layout.rs:43,56 vs app/Sources/AsterApp/EditorModel.swift:117,271；Bridge 只暴露 layout_line_starts（core/src/bridge.rs:46） | T-072（ADR-026：range 派生回 Core，查找保留标准二分） | Fixed | 3901447 |
| I-011 | P1 | IME 组合状态语义与光标几何四处重复：「光标 = 光标 + 组合长度」公式在 EditorModel / MetalView / MetalView+Input / VertexBuilder 各算一遍，scrollX 补偿位置不一致（firstRect 减、scrollCursorIntoView 不减） | app/Sources/AsterApp/EditorModel.swift:24,68；MetalView.swift:245；MetalView+Input.swift:78；VertexBuilder.swift:114 | T-073（caretDisplayByte + CaretGeometry 收拢） | Fixed | 44a2262 |
| I-012 | P1 | `closeDecisionDocId` 瞬态实例字段当参数用：T-070 清理「全局布尔 / 跨切面上下文」后同型模式回潮，关闭决策上下文存在 AppDelegate 实例上（重入可串） | AppDelegate.swift:39；set/defer 于 AppDelegate+CloseFlow.swift:64-65；读取于 AppDelegate.swift:115 | T-074（presentPendingDocsAlert(closeDocumentId:) 显式参数） | Fixed | 5a2dfb4 |
| I-013 | P1 | frame ↔ 文档关联域无单一所有者：frames / frameFileName / view.model.bufferIdValue 分散，5+ 处各自推导（标题 / 保存 / 关闭决策 / 窗口关闭 / 内容变更） | AppDelegate.swift:34,36,239；AppDelegate+CloseFlow.swift:63,93；AppDelegate+Storage.swift:96,126 | T-074（FrameDocument 单一登记） | Fixed | 5a2dfb4 |
| I-014 | P2 | 内容宽度测量与渲染对同一批可见行重复 shaping：contentSize() 每滚动事件 shaping 一次，渲染帧 VertexBuilder 再 shaping 一次（T-038 只统一了 buildVertices 内部） | app/Sources/AsterApp/MetalView.swift:222 vs VertexBuilder.swift:34 | T-073（contentVersion 键控宽度测量缓存） | Fixed | 44a2262 |
| I-015 | P2 | `shouldOfferRecovery` 纯函数滞留 App：按「可测逻辑尽可能进 Core」应下沉 Session（与恢复编排同域） | AppDelegate.swift:62（纯函数，App 测试覆盖中） | T-029 | Deferred | |
| I-016 | P2 | `EditorModel.lines` 生产路径零消费（仅测试用），Rule 12 死代码需标注或删除 | app/Sources/AsterApp/EditorModel.swift:86；消费点仅 MetalViewTests / RendererTests | T-073（删除，测试改用 lineText） | Fixed | 44a2262 |

## 已知待办（Roadmap 已有归属，此处仅作完整性登记，不重复编号）

- Command / Event / Lua / Store / Theme 零消费者模块接线：T-024 / T-028 / T-029（Rule 13/14
  存量处置；接线时预留接口返工预算）。
- Edit 菜单 cut / copy / paste 尚未接线：T-014（NSPasteboard）。
- 主题颜色硬编码、渲染颜色未接 Core Theme：T-016。
- os_log（App）+ tracing（Core）未接线：T-031（ADR-004 闭环）。
- Undo 历史无上限、无持久化：T-029（Crash Recovery）。
- 打开第二个文件时替换当前会话、未保存编辑静默丢弃：随 T-024（激活文档统一）缓解；
  T-037 先提供保存能力与关闭保护。
- 主题颜色硬编码、Core Theme 零消费者：T-016（2026-08-03 复审复核确认）。
- 键盘 / 菜单 / IME 三条输入入口未接 Core Command 总线（ARCHITECTURE 数据流
  未落地）：T-024。
- 崩溃恢复编排（needsRecoveryPrompt + presentRecoveryIfNeeded）滞留 App：
  T-029（关联 I-015）。

## 规则

- 新问题登记时编号自增，写明证据、严重度与处置切片；无证据不登记。
- 处置切片完成时必须回填状态与 Commit，并在 [docs/audits.md](audits.md) 留审计行。
- 严重度定义：P0 = 数据损坏 / 核心语义违反（ADR-005 UTF-8 底线）或崩溃；P1 = 功能
  缺口 / 性能阶梯；P2 = 规则违反 / 债务 / 门禁缺口。
