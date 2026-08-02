# ADR-023 — 保存语义（SQLite 自动保存，按日期 + 序号轮转）

- **Status:** Accepted
- **Date:** 2026-08-02
- **Version:** 1.2
- **新增 Public API:** v1.2：`Store::open_next` / `Store::open_latest` 2 方法 +
  `StoreError::Io` 变体 + Bridge FFI 4 项（store_open_next / store_open_latest /
  store_save_scratch / store_load_scratch）
- **影响模块:** core（store、bridge）、app（AppDelegate、AppMenu、EditorModel）、docs
- **是否违反 Single Responsibility:** 否
- **是否增加循环依赖:** 否

---

## 决策

1. **保存 = 自动持久化到 SQLite（v1.1 反转 v1.0 的磁盘写回）**。`Cmd+S` 把当前
   编辑文本写入 SQLite，**不需要用户指定路径**（ADR 总纲 §5/§6：SQLite 承担
   Scratch / 会话等内部状态；Scratch 自动保存、无需命名）。磁盘文件（用户指定
   路径存储）是未来文件系统切片的能力，**本版本不实现**（见备注，Rule 13 显式
   Deferred）。反转经项目所有者确认（2026-08-02 用户指示：T-037 把未来路线
   提前实现，方向修正）。
2. **按日期 + 序号轮转（v1.2）**：文件名 `aster-YYYY-MM-DD-<seq>.sqlite`——**单日内
   可写入多个文件**（用户指示 2026-08-02），seq 从 1 递增（下一个 = 当日最大序号 + 1，
   容忍中间缺号）。**每次 Cmd+S 写入一个新快照文件**（同一天的保存历史 = 多个版本文件）；
   读取 / 继续 = 当日最高 seq（`Store::open_latest`）。日期为 UTC（本地时区午夜轮转随
   配置系统细化）。旧日文件自然留存；**保留期 / 自动清理属未来配置切片，本版本不做
   自动删除**（Rule 9）。
3. **默认路径可指定（v1.1）**：默认目录 = `~/Library/Application Support/Aster`；
   v1 经环境变量 `ASTER_STORE_DIR` 覆盖（最小实现，无配置系统），Config DSL / Lua
   配置切片落地后迁移为配置项。
4. **错误全部可见（ADR-004）**：目录创建失败 → `StoreError::Io`；
   SQLite 操作失败 → `StoreError::Sqlite`（既有变体）；App 经 NSAlert 呈现，不静默吞掉。
5. **App 侧最小可用集**：File 菜单「保存」（⌘S）；dirty 状态由 `EditorModel.onChange`
   回调维护（type_text / delete_backward / undo / redo 成功才触发，光标移动与选区
   不置脏），窗口标题加「●」；关闭 / 退出时存在未保存编辑 → NSAlert 三选（保存 /
   不保存 / 取消）；保存键 = BufferId（初始演示 Buffer 也可保存，无"必须打开过磁盘
   文件"的前置条件）。
6. **保存数据模型**：复用 ADR-013 `Store.scratch` 表（id + content）；每个快照文件
   承载一次保存的内容。会话 / 崩溃恢复编排仍在 T-028 / T-029，本切片不扩展 schema。
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
| `Store::open_next(dir: &Path) -> Result<Self, StoreError>` | 创建当日下一个序号文件 `<dir>/aster-YYYY-MM-DD-<seq>.sqlite`（seq = 当日现有文件数 + 1） |
| `Store::open_latest(dir: &Path) -> Result<Option<Self>, StoreError>` | 打开当日最高 seq 文件（无文件返回 None；读取 / 继续用） |
| `StoreError::Io(std::io::Error)` | 目录创建失败等非 SQLite 错误 |
| Bridge `store_open_next(dir: String) -> Result<Store, String>` | Cmd+S：新建当日下一个序号快照文件 |
| Bridge `store_open_latest(dir: String) -> Result<Store, String>` | 打开当日最新快照（无文件报错；测试 / T-028 用） |
| Bridge `store_save_scratch(store: &mut Store, id: usize, content: String) -> Result<(), String>` | Cmd+S 保存点（id 以 usize 透传，ADR-014 惯例） |
| Bridge `store_load_scratch(store: &Store, id: usize) -> Result<String, String>` | 读取保存内容（测试 / T-028 接线用） |

> v1.0 的 `DocumentManager::save_text` + `NoPath` / `SaveFailed` 已随反转撤销
> （Rule 14：无消费者接口不得滞留；未来文件系统切片重新引入并配真实消费者）。

## 影响模块

- **core（store）**：新增 `open_next` / `open_latest`（日期 + 序号轮转）+ `StoreError::Io`；
  当日文件列表按序号数值排序（不依赖词法序）；civil date 换算用标准算法
  （Howard Hinnant days-from-civil），不引 chrono（Rule 7：标准库可解决，新依赖需 ADR）。
- **core（bridge）**：新增 Store FFI 4 项；撤销 `document_manager_save_text`。
- **core（document_manager）**：撤销 v1.0 的 save_text + 2 错误变体（Rule 14）；
  `Document.path` 回到仅测试读取，恢复 dead_code expect（未来文件系统切片消费）。
- **app**：AppDelegate 启动建 Store（默认目录 / `ASTER_STORE_DIR` 覆盖），
  saveDocument 写 Store；dirty 标题与关闭保护保留；AppMenu「保存」保留；
  EditorModel 增加 bufferId 暴露（App 模块内）。
- **docs**：changelog / roadmap / audits / benchmarks 同步。

## 复杂度预算（宪法 Rule 9）

1. **增加了哪些复杂度？** Core `open_next` / `open_latest` + 序号解析 + civil date
   换算（~60 行）+ 1 错误变体 + Store FFI 4 项；App 侧薄胶水（菜单项、dirty 标题、
   关闭保护，约 50 行）；
   0 抽象层、0 新依赖。
2. **是否永久？** 是——保存是编辑器的永久能力；dirty 与关闭保护是"不静默丢数据"
   的最小产品语义。
3. **有没有更简单方案？** 每天单文件（v1.1）——实现更简单但不符合"单日内可写入
   多个文件、日期后加序号"的既定要求；每次保存新文件即同日多版本快照，天然保留
   保存历史（未来版本浏览可直接复用）。只做保存、不做 dirty/关闭保护——会保留
   I-002 的"关窗静默丢编辑"主诉。结论：当前是满足"能保存 + 日期+序号轮转 +
   不静默丢数据"的最简集。

## 备注

- **Deferred（Rule 13）**：磁盘文件写回（用户指定路径存储）——未来文件系统切片，
  重新引入 `DocumentManager` 的路径写回 API 并配真实消费者；复评条件 = 文件系统
  切片排期（Roadmap）。
- 打开第二个文件替换当前会话时，前一个文档的未保存编辑仍会丢弃（既有行为，
  随 T-024 激活文档统一）；本切片先提供保存能力与关闭保护。
- 日期为 UTC（跨时区确定性、纯 Rust 可测）；本地时区午夜轮转随配置系统细化。
- 保存成功不弹窗（系统惯例）；失败经 NSAlert 可见（ADR-004）。
