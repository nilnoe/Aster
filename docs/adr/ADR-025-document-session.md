# ADR-025 — 文档会话（DocumentSession）：生命周期状态收拢

- **Status:** Accepted
- **Date:** 2026-08-03
- **Version:** 1.0
- **新增 Public API:** `Session` 类型 + `SessionError` + Bridge FFI 21 项（session_* 前缀）
- **影响模块:** core（新增 session 模块、bridge；删除 bridge_store）、app（AppDelegate 及扩展）、docs
- **是否违反 Single Responsibility:** 否
- **是否增加循环依赖:** 否

---

## 决策

在 Rust Core 新增 `session` 模块：`Session` 是**文档生命周期状态的唯一所有者**——
统一持有 DocumentManager（注册表 / id 分配 / 磁盘读取）、缓冲 Store（崩溃保护 /
哨兵）、快照 Snapshot（提交产物），以及每文档的「未决标记 / 快照序号 / 已固化
基线 / 自动保存失败提示」。App 不再持有任何文档生命周期账本；窗口 / 视图（frame）
仍属 App 层，只通过 Session 查询 / 驱动文档状态。

## 原因

### 问题证据（T-070 收拢动机，2026-08-03 全仓体检）

1. **功能互相打架**：BUG-009~018 全部落在保存 / 恢复 / 关闭 / Frame 域。旧实现把
   状态散在 AppDelegate 11 个跨切面可变字段（`pendingDocs` /
   `snapshotSeqByDocId` / `committedTextByDocId` / `bufferSaveErrorVisible` /
   `frames` …）里，三张以 docId 为键的平行账本在 6+ 条路径手工同步，漏一条 =
   一个新 BUG（共享序号覆盖 / 恢复漏写缓冲 / undo 假 dirty / 忽略分支失管）。
2. **新功能未做冲突扫描**：T-069 Frame × 关闭流（关 frame B 弹 frame A 的未决
   提示）、T-054 失败提示 × 多文档（全局单布尔，frame B 保存成功吞掉 frame A 的
   提示）、`makeFrame` 兜底 `?? 1`（存储故障时两个 frame 抢同一 id）、DM 注册表
   随每次新建 / 打开永久增长（`DocumentManager::close` 零消费者）。
3. **测试兜底替代模型保证**：T-069 重构时变异测试立即抓到 M3 存活——状态跨层
   散落，任何重构都可能踩坏不变量。状态机收拢进 Core 后，不变量由方法保证，
   Core 单测 + 变异门禁直接保护（docs/testing.md「可测试逻辑尽可能落在 Rust
   Core」的宪法分工）。

### 为什么不放在 App / 保持现状

- 保持现状 = 继续给 11 个字段打补丁，第 12、13 个字段只是时间问题（Rule 9 三问
  第三问：更简单方案 = 收拢，不是加字段）。
- 纯 Swift 模型（无 AppKit）可测，但宪法 Rule 13 / WORKFLOW 明确「可测试逻辑
  尽可能落在 Rust Core」；且 Core 内 Session 可直接持有 Store / Snapshot / DM，
  单次调用完成「登记 + 建快照 + 写缓冲」的组合操作，App 只剩薄胶水。

## 审计

### Single Responsibility

Session 的唯一职责 = 文档生命周期状态（创建 / 置脏 / 保存 / 丢弃 / 关闭 / 恢复
登记）与持久化编排（缓冲 + 快照 + 注册表）。不包含：文本编辑语义（Editor）、
窗口 / 视图状态（frame，App 层）、渲染、命令分发。

### 循环依赖

```text
session → document_manager / store / snapshot（单向）
bridge → session → document_manager / store / snapshot
app → bridge → session
```

无反向依赖；session 不依赖 app / bridge。

## 新增 Public API

### Rust（lib.rs 导出）

| API | 职责 |
| --- | --- |
| `Session::open(dir: &Path) -> Session` | 打开（或创建）会话：缓冲 + 快照目录 + 注册表；缓冲打开失败不阻止会话（`store_error()` 携带消息） |
| `Session::store_error(&self) -> Option<&str>` | 启动时缓冲打开失败的消息（T-054：启动即提示） |
| `Session::is_clean_exit / set_clean_exit` | 崩溃恢复哨兵（ADR-013 v1.1 透传） |
| `Session::open_scratch(&mut self) -> Result<u64, SessionError>` | Cmd+N / 新 Frame / 恢复：注册 Scratch + 分配快照序号（快照失败容忍，seq 为 None） |
| `Session::open_disk(&mut self, path) -> Result<u64, SessionError>` | 打开磁盘文件并登记；已固化基线 = 文件内容（T-070 修正：磁盘文档 undo 回原文不置脏） |
| `Session::text(&self, id) -> Result<&str, SessionError>` | 注册文本读取；未知 id 显式报错（修正旧 `document_manager_text` 静默空串） |
| `Session::content_changed(&mut self, id, content) -> Result<(), SessionError>` | 内容变更唯一入口：未决标记 + 缓冲自动保存；内容 == 基线 → 不置脏并删冗余行（BUG-012）；写失败**按文档**只提示一次（T-054） |
| `Session::save(&mut self, id)` | Cmd+S 合并：读缓冲 → 写快照 → 更新基线 → 删缓冲行（顺序 = 变异 M1 保护点，写失败保全缓冲与未决） |
| `Session::save_all(&mut self)` | 退出「保存全部」：按 id 升序逐个合并，任一失败即中止 |
| `Session::discard / discard_all` | 明确丢弃（ADR-013 v1.3 删除时机 3）：删缓冲行 + 清未决 |
| `Session::pending_ids / is_pending` | 未决查询（退出提示 / 标题 dirty / ⌘S 空操作） |
| `Session::snapshot_seq(&self, id)` | 快照序号查询（测试 / 审计） |
| `Session::load_buffered / delete_buffered` | 崩溃恢复载入与旧行清理（ADR-013 v1.3 删除时机 2） |
| `Session::register_buffered(&mut self, id)` | 崩溃遗留行登记：分配序号（已登记保留原序号）+ 置未决（BUG-011 / BUG-016） |
| `Session::prune_empty(&self)` | 干净退出清理空快照（T-047，ADR-023 v1.6） |
| `Session::close_document(&mut self, id)` | 关闭文档：注册表移除（ADR-001 生命周期；T-070 修正注册表泄漏） |
| `SessionError`（6 变体） | UnknownDoc / StoreNotReady / NoSnapshot / MissingBuffer / DocumentManager / Store / Io |

### Bridge FFI（21 项，session_* 前缀）

`session_new` / `session_store_error` / `session_is_clean_exit` /
`session_set_clean_exit` / `session_buffered_ids` / `session_open_scratch` /
`session_open_disk` / `session_text` / `session_content_changed` / `session_save` /
`session_save_all` / `session_discard` / `session_discard_all` /
`session_pending_ids` / `session_is_pending` / `session_snapshot_seq` /
`session_load_buffered` / `session_delete_buffered` / `session_register_buffered` /
`session_prune_empty` / `session_close_document`。

> **取代（Supersedes）**：旧 `document_manager_*`（4 项）、`store_*`（7 项）、
> `snapshot_*`（5 项）FFI 随本切片撤销（无生产消费者，Rule 14）；对应行为由
> session FFI 承接，ADR 索引计数以 ADR-024 机械校验为准。`buffer_*` / `editor_*`
> / `layout_line_starts` / `core_version` 编辑面不变。

## 影响模块

- **core（新增 session 模块，~260 行）**：状态收拢 + 持久化编排；不引入 Trait /
  抽象层（Rule 1 / 2：普通 struct，直接组合既有模块）。
- **core（bridge）**：删除 bridge_store 适配层（store / snapshot FFI 撤销）；
  新增 session FFI 21 项。
- **core（document_manager / store / snapshot）**：本身不变；`text` 访问器继续
  pub(crate) 供 Session 使用。
- **app**：AppDelegate 删除 documentManager / bufferStore / snapshot /
  pendingDocs / snapshotSeqByDocId / committedTextByDocId / bufferSaveErrorVisible
  七个字段，改为单一 `session: Session?`；关闭流改为**按窗口文档决策**
  （关 B 只问 B）；窗口关闭时 `session_close_document`（注册表生命周期）。
- **docs**：ADR-001 / ADR-013 / ADR-023 头部计数标注由本 ADR 承接；ADR-024 落地
  FFI 总账机械校验；changelog / roadmap / audits / benchmarks / experience 同步。

## 复杂度预算（宪法 Rule 9）

1. **增加了哪些复杂度？** 1 个 Core 模块（~260 行）+ 1 个错误类型 + 21 项 FFI；
   删除 16 项旧 FFI + App 侧 7 个字段与 ~150 行账本同步代码。净复杂度**下降**：
   状态唯一入口，不变量由方法保证。
2. **是否永久？** 是——文档生命周期是编辑器永久结构；但收拢后状态维度被锁定
   在一个模块内，不会随功能继续膨胀（对比：旧三账本每功能 +1 字段）。
3. **有没有更简单方案？** 维持现状（继续加字段）更简单但已证明不可维护
   （10 个 BUG）；纯 Swift 模型比 Core 更简单但违反宪法分工且无法直接编排
   Store / Snapshot。结论：Core 收拢是满足「停止互相踩踏」的最简合规方案。

结论：1 模块 / 1 类型 / 0 抽象层，净删代码，未触及红线。

## 备注

- 本 ADR 不新增窗口 / 会话恢复语义：多文档完整会话恢复仍在 T-029；Session 提供
  `register_buffered` 原语，编排仍由 App 启动流程驱动。
- 保存域语义冻结（ADR-023 v1.7）：Session 状态机新增 / 反转语义必须先确认方向。
- 实现切片：T-070（本 ADR 同切片交付全部消费者——App 重接线 + Bridge / App /
  Core 测试 + 变异门禁迁移至 Core）。
