# ADR-023 — 保存语义（SQLite 缓冲 + 快照，按日期 + 序号轮转）

- **Status:** Accepted
- **Date:** 2026-08-02
- **Version:** 1.8
- **新增 Public API:** v1.4：`Snapshot` 类型 5 方法 + Bridge FFI 5 项（snapshot_new /
  snapshot_create_next / snapshot_write / snapshot_read + 缓冲 store_open_buffer /
  store_save_scratch / store_load_scratch）
- **影响模块:** core（新增 snapshot 模块、store、bridge）、app（AppDelegate、AppMenu、EditorModel）、docs
- **是否违反 Single Responsibility:** 否
- **是否增加循环依赖:** 否

---

> **v1.7 备注（T-070 治理纠偏，2026-08-03）**：保存域进入**语义冻结期**——
> 本 ADR 在一天内被反转六次（v1.1~v1.6），每次反转都伴随 FFI 加加减减与
> App 状态补丁（BUG-009~018 全部落在此域）。冻结规则：保存 / 恢复 / 关闭域
> 的任何语义改动，必须先向项目所有者说明「改动什么语义、为什么、影响哪些
> 既有行为」，经确认并修订本 ADR 后才允许实现（实现先行 = 违规，T-037 /
> T-040 / T-042 前例）。FFI 面自 T-070 起收敛为 `Session` 统一入口（ADR-025），
> 本 ADR 头部的 store / snapshot FFI 计数由 ADR-025 / ADR-024 承接。

> **v1.8 备注（T-065，2026-08-03，冻结期第二次方向确认）**：自动保存粒度反转
> ——缓冲写入从「每次内容变更」改为 **200ms 防抖**。用户 2026-08-03 指示
> 「性能第一、参考 Phase 8」确认方向。语义：连续输入只写一次缓冲（崩溃最多丢
> ~200ms 编辑，旧语义 ~0ms）；保存 / 关闭 / 退出前强制冲刷（flushAutosave），
> 读取缓冲行前语义不变（写仍全量覆盖当前活文，ADR-027 单 Buffer）。实现位置：
> **App 层防抖**（一次性 Timer + 脏 id 集合）——Core Session 写透语义与
> 「未决 ⟺ 缓冲行」不变量不变（对比 Core 侧批处理需改不变量，Rule 9 拒绝）。

## 决策

1. **保存 = 自动持久化到 SQLite（v1.1 反转 v1.0 的磁盘写回）**。`Cmd+S` 把当前
   编辑文本写入 SQLite，**不需要用户指定路径**（ADR 总纲 §5/§6：SQLite 承担
   Scratch / 会话等内部状态；Scratch 自动保存、无需命名）。磁盘文件（用户指定
   路径存储）是未来文件系统切片的能力，**本版本不实现**（见备注，Rule 13 显式
   Deferred）。反转经项目所有者确认（2026-08-02 用户指示：T-037 把未来路线
   提前实现，方向修正）。
2. **双文件模型（v1.4，用户指示 2026-08-02）**：
   - **快照文件（纯文本）** `aster-YYYY-MM-DD-<seq>.txt`：**Cmd+N 创建**（每次
     新文档 = 当日下一个序号文本文件，seq = 当日最大 + 1，容忍缺号；单日内可写
     多个文件）；**Cmd+S = 合并缓冲 → 当前快照**（把缓冲文本写入该文本文件，
     提交 / 固化，不是新建文件）。**v1.4 修正：快照必须是文本文件，不是 SQLite
     数据库**——提交产物要在 Buffer 里打开（用户指出 .sqlite 无法在 buffer 打开；
     文本文件经 DocumentManager Disk 源直接读入）。
   - **缓冲文件** `buffer.sqlite`（SQLite，同目录）：**编辑自动保存**（每次内容
     变更写入，无需用户按保存）——程序意外崩溃时缓冲文件保住最新编辑；
   - dirty「●」= 缓冲与快照不一致（未提交编辑），退出时提示保存。
   - 读取 / 继续 = 当日最高 seq（`Snapshot::latest_seq`）。日期为 UTC（本地时区
     午夜轮转随配置系统细化）。旧日文件自然留存；**保留期 / 自动清理属未来配置
     切片，本版本不做自动删除**（Rule 9）。
   - **v1.6 补充（空文件清理，用户指示 2026-08-02）**：快照 `aster-*.txt` 中
     **内容为空的文件在进程干净退出时删除**（`Snapshot::prune_empty`）——启动
     即建的 001、⌘N 后从未输入 / 合并的空文档，不应在默认目录累积。只删除
     零长度文件；崩溃退出不清理（下次干净退出时一并处理）。
3. **默认路径可指定（v1.1）**：默认目录 = `~/Library/Application Support/Aster`；
   v1 经环境变量 `ASTER_STORE_DIR` 覆盖（最小实现，无配置系统），Config DSL / Lua
   配置切片落地后迁移为配置项。
4. **错误全部可见（ADR-004）**：目录创建失败 → `StoreError::Io`；
   SQLite 操作失败 → `StoreError::Sqlite`（既有变体）；App 经 NSAlert 呈现，不静默吞掉。
5. **App 侧最小可用集（v1.5）**：File 菜单「新建」（⌘N，创建新快照）+「保存」
   （⌘S，合并缓冲）；dirty 状态由 `EditorModel.onChange` 回调维护（type_text /
   delete_backward / undo / redo 成功才触发，光标移动与选区不置脏），窗口标题加
   「●」；关闭 / 退出时存在未提交编辑 → NSAlert 三选（保存 / 不保存 / 取消）；
   保存键 = BufferId（启动默认 Buffer 也接线 onChange——修复此前未接线导致无
   dirty / 退出保护失效的 bug）。
   - **v1.5 修订（无模态弹窗原则，用户指示 2026-08-02）**：产品理念是**不弹窗**
     ——模态 NSAlert 违背「极简、纯 Buffer」理念，是**过渡实现**；未保存 / 未决
     文档提示的未来形态是 **Buffer 底部行内提示 + y/n 输入**（StatusBar overlay，
     T-026，尚未建设）。过渡期保留弹窗并明确标注临时，T-026 落地后移除。
   - 退出提示覆盖**全部**未决文档（T-046：保存全部 / 全部不保存 / 取消），
     不再只问当前文档。
6. **保存数据模型（v1.4）**：SQLite（`buffer.sqlite`）承载缓冲工作副本（每 id
   一行，持续覆盖，崩溃保护）；快照是**纯文本文件**（提交内容，可打开编辑）。
   会话 / 崩溃恢复编排仍在 T-028 / T-029，本切片不扩展 schema。
7. **文本经 Bridge 传入 Store 而非让 Core 持有 Editor**：激活文档统一（注册表 ↔
   会话双向同步）随 T-024 落地；v1 最小接线避免把激活文档状态提前引入 Core（Rule 9，
   同 ADR-017 对激活文档的推迟理由）。

## 原因

- **I-002（审查问题登记）**：编辑器能开不能存——关窗即丢编辑。保存是编辑器的永久
  能力，不是可选增强。
- **为什么是 SQLite 而非磁盘文件（v1.1 反转依据）**：ADR 总纲 §5 明确 SQLite 承担
  Scratch / Session 等内部状态；§6 明确 Scratch 自动保存、无需命名、无需路径
  （"不是 Save As，而是 Attach Path"）。用户指定路径的磁盘存储属于未来文件系统
  切片；v1.0 直接写回绑定路径违反了"先问架构、不做未来路线"的切片纪律。
- **为什么放 Store 而非 DocumentManager（v1.1）**：保存目标是 SQLite 内部存储
  （ADR-013），归属 Store；DocumentManager 的路径绑定（ADR-001）只在未来文件系统
  切片消费。

## 审计

### Single Responsibility

DocumentManager 新增「写回存储目标」职责，与「注册 + 生命周期 + 路径绑定」
（ADR-001）同域；不混入渲染、命令分发或编辑语义。

### 循环依赖

`store → rusqlite`；`document_manager → buffer / error`（单向）；`bridge → store /
document_manager`；`app → bridge → core`。无反向。

## 新增 Public API

| API | 职责 |
| --- | --- |
| `Snapshot::new(dir: PathBuf)` | 快照目录句柄（纯文本快照文件的管理者） |
| `Snapshot::create_next(&self) -> Result<i64, io::Error>` | Cmd+N：创建 `<dir>/aster-YYYY-MM-DD-<seq>.txt` 并返回 seq |
| `Snapshot::write(&self, seq: i64, content: &str) -> Result<(), io::Error>` | Cmd+S：合并缓冲文本到指定序号快照 |
| `Snapshot::read(&self, seq: i64) -> Result<String, io::Error>` | 读取快照内容（T-028 / 测试） |
| `Snapshot::latest_seq(&self) -> Result<Option<i64>, io::Error>` | 当日最高序号（恢复入口） |
| Bridge `snapshot_new(dir: String) -> Snapshot` | 建立快照目录句柄 |
| Bridge `snapshot_create_next(snapshot: &Snapshot) -> Result<usize, String>` | Cmd+N（usize 透传） |
| Bridge `snapshot_write(snapshot: &Snapshot, seq: usize, content: String) -> Result<(), String>` | Cmd+S 合并 |
| Bridge `snapshot_read(snapshot: &Snapshot, seq: usize) -> Result<String, String>` | 读回（T-028 / 测试） |
| Bridge `store_open_buffer(dir: String) -> Result<Store, String>` | 启动时打开缓冲文件（自动保存用） |
| Bridge `store_save_scratch(store: &mut Store, id: usize, content: String) -> Result<(), String>` | Cmd+S 保存点（id 以 usize 透传，ADR-014 惯例） |
| Bridge `store_load_scratch(store: &Store, id: usize) -> Result<String, String>` | 读取保存内容（测试 / T-028 接线用） |

> v1.0 的 `DocumentManager::save_text` + `NoPath` / `SaveFailed` 已随反转撤销
> （Rule 14：无消费者接口不得滞留；未来文件系统切片重新引入并配真实消费者）。

## 影响模块

- **core（新增 snapshot 模块）**：`Snapshot`（纯文本快照：日期 + 序号轮转、
  创建 / 写 / 读 / latest）；当日文件列表按序号数值排序（不依赖词法序）；civil
  date 换算复用 store 的 `today_iso`（pub(crate)）。**为什么独立模块而非塞进
  Store（Rule 3 SRP）**：Store 的职责是 SQLite（ADR-013），快照是纯文本文件，
  混在一起违反单一职责。
- **core（store）**：移除 v1.2/v1.3 的 SQLite 快照 API（`next_snapshot` /
  `open_snapshot` / `open_latest`，Rule 12/14：无消费者立即删除）；`open_buffer`
  保留。
- **core（bridge）**：新增 Snapshot FFI 5 项；撤销 `document_manager_save_text`。
- **core（document_manager）**：撤销 v1.0 的 save_text + 2 错误变体（Rule 14）；
  `Document.path` 回到仅测试读取，恢复 dead_code expect（未来文件系统切片消费）。
- **app**：AppDelegate 启动打开缓冲 Store；Cmd+N 新建快照（重置编辑会话）；
  内容变更自动写缓冲 + 置 dirty；Cmd+S 合并缓冲 → 当前快照；dirty 标题与退出
  保护（默认 Buffer 也接线，修复未接线 bug）；AppMenu 增加「新建」；
  EditorModel 增加 bufferId 暴露（App 模块内）。
- **docs**：changelog / roadmap / audits / benchmarks 同步。

## 复杂度预算（宪法 Rule 9）

1. **增加了哪些复杂度？** Core 新增 `snapshot` 模块（~120 行：日期 + 序号轮转、
   创建 / 写 / 读 / latest）+ Snapshot FFI 5 项；App 侧薄胶水（新建 / 自动保存 /
   合并 / dirty 标题 / 关闭保护，约 90 行）；0 抽象层、0 新依赖。
2. **是否永久？** 是——保存是编辑器的永久能力；dirty 与关闭保护是"不静默丢数据"
   的最小产品语义。
3. **有没有更简单方案？** 只有快照没有缓冲——崩溃时最后一次自动保存前的编辑仍
   会丢，违背"防止程序意外崩溃损失编辑"的硬要求；自动保存直接写快照——每次按键
   都产生新文件，快照爆炸。结论：缓冲（连续写）+ 快照（Cmd+N 建、Cmd+S 合并）是
   满足"崩溃保护 + 提交语义 + 日期序号轮转"的最简分工。

## 备注

- **Deferred（Rule 13）**：磁盘文件写回（用户指定路径存储）——未来文件系统切片，
  重新引入 `DocumentManager` 的路径写回 API 并配真实消费者；复评条件 = 文件系统
  切片排期（Roadmap）。
- 打开第二个文件替换当前会话时，前一个文档的未保存编辑仍会丢弃（既有行为，
  随 T-024 激活文档统一）；本切片先提供保存能力与关闭保护。
- 日期为 UTC（跨时区确定性、纯 Rust 可测）；本地时区午夜轮转随配置系统细化。
- 保存成功不弹窗（系统惯例）；失败经 NSAlert 可见（ADR-004）。
