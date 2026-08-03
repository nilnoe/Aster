# ADR-013 — SQLite 存储层（Store）

  v1.1 备注（T-043）：新增崩溃恢复原语——`meta` 表存放 `clean_exit` 哨兵
  （干净退出 = "1"，启动时清空；崩溃后为缺省值），`list_scratch` 枚举缓冲文档；
  恢复流程 = App 启动检测哨兵 + 缓冲内容 → 提示恢复（消费方 = AppDelegate，
  T-043）。Session 多文档完整恢复仍在 T-029。

  v1.5 备注（T-070，ADR-025）：`store_*` Bridge FFI（7 项）随文档生命周期收拢至
  `Session` 撤销——缓冲 / 哨兵 / 枚举经 `session_*` 统一入口暴露；缓冲生命周期
  编排（未决 ⟺ 缓冲行、删除三时机）由 Session 承接（原 AppDelegate 三账本收拢
  处，ADR-025）。本 ADR 头部的 FFI 计数由 ADR-024 机械校验承接。

- **Status:** Accepted
- **Date:** 2026-08-02
- **Version:** 1.6
- **新增 Public API:** `Store`（7 方法）+ `SessionDocument`（2 公共字段）+ `StoreError`（1 变体）+ 新增依赖 **rusqlite**（宪法 Rule 7 / 8）
- **影响模块:** Core（新增 store 模块）
- **是否违反 Single Responsibility:** 否
- **是否增加循环依赖:** 否

---

## 决策

> **v1.6 备注（T-066，2026-08-03）**：文件库启用 `PRAGMA journal_mode = WAL`
> + `PRAGMA synchronous = NORMAL`——rollback journal 每次提交写整页 journal +
> 主库（写放大），WAL 只顺序追加。基准（Rule 16）：10k 小 upsert 1.683s →
> 59ms（−96.5%，缓冲自动保存的真实写模式）；1MB 单次大 blob +57%（WAL 周期
> checkpoint 摊还，非热路径）。崩溃保护语义复核：WAL 下 `synchronous=NORMAL`
> 保证**进程级**崩溃 / kill 不丢已提交数据（-wal 持久、重开自动恢复，store
> 单测 + T-056 全绿）；仅 OS 崩溃 / 断电可能丢最近提交——编辑器崩溃保护范围
> 是进程级（本 ADR 决策 4 不变），可接受。

在 Rust Core 中新增 `store` 模块：`Store` 封装 rusqlite（SQLite 3，`bundled`），负责 Scratch 内容与会话记录的持久化原语。

v1 schema（`PRAGMA user_version = 1`）：

```sql
CREATE TABLE scratch (id INTEGER PRIMARY KEY, content TEXT NOT NULL);
CREATE TABLE session (position INTEGER PRIMARY KEY, id INTEGER NOT NULL, path TEXT);
```

会话写入为**整表替换 + 单事务**（原子性）；`path` 有无即文档类型（`None` = Scratch，与 ADR-001 `Document.path` 语义一致），无需冗余 kind 列。

## SQLite 的角色与保留论证（v1.2，T-044）

### 角色边界

- **文档 = 文本文件**：用户可打开、可编辑、可移动（快照 `.txt`，ADR-023 v1.4；
  未来用户指定路径的磁盘文件同样是文本）。
- **SQLite = 编辑器内部状态**：Scratch 缓冲、Session、Recent Files、Workspace、
  Undo 持久化（总纲 §5）。两者永不混用。

### 保留论证

1. **崩溃保护要求事务性写入**：缓冲文件的存在意义是「防崩溃丢编辑」，而
   `std::fs::write` 覆盖写非原子——写入中途崩溃会截断 / 损坏缓冲本身。SQLite 的
   事务 + journal/WAL 保证缓冲任何时刻要么旧内容要么新内容，绝不半截（对比：
   快照 `.txt` 合并写目前也非原子，属已识别改进，见守则 c）。
2. **缓冲是多文档状态**：每个 Cmd+N 文档在 `scratch` 表一行；T-029 会话恢复要
   恢复全部文档。纯文本方案要么 N 个文件 + 第二套命名 / 扫描约定（与快照重复造
   文件管理，Rule 11 Rule of Three），要么自研分隔格式（Rule 11 自研轮子）。
3. **既定路线已为 SQLite 排期**：总纲 §5 已定 SQLite 承担 Scratch / Session /
   Recent Files / Workspace / Undo 持久化；T-028 / T-029 等待消费。现在拆 =
   未来再装 = Rule 13 / 14 的来回 churn；rusqlite bundled 已锁定版本且 Rule 7 / 8
   论证已付，拆除不退款，回来要再付。

### 反面与拆除条件

若项目所有者决定砍掉会话恢复 / 最近文件 / 工作区 / Undo 持久化路线，退化为
「只开文本文件」的最小形态，则 SQLite 的边际价值只剩缓冲写入原子性，可用原子
覆盖文本文件（tmp + rename）替代；届时按 ADR 反转流程拆除 rusqlite（约省
2.4MB 静态库 + clean build 时间 + 6 个 FFI）。**2026-08-02 决议：保留。**

### 守则

- a) **边界永不混用**：文档走文本文件，状态走 SQLite；新切片违反此边界即架构违规。
- b) **`session` 表不许悬挂**：T-029 必须消费（多文档会话恢复），否则显式
  Deferred 并删表（Rule 12 / 13：死表是债务不是资产）。
- c) **快照 `.txt` 合并写应改原子写（tmp + rename）**：已识别改进，未排期，
  随文件系统切片或保存打磨切片评估（非 Accepted 决策，Rule 13 不触发）。

## 缓冲的角色与生命周期（v1.4，T-045 / T-046）

**缓冲只服务边界情况**（系统强杀 / 意外退出，用户指示 2026-08-02）：它是崩溃
保护的连续工作副本，不是正常文档管理机制。正常退出路径由**多文档未提交状态
登记**（App `PendingDocs`）驱动：进程生命周期内**所有**文档的状态都会被检查，
切换视图 / 打开新文件不抛弃前一个文档（用户指示）。

缓冲（`scratch` 表）的语义是「未提交且未明确丢弃的编辑」，不是存档。规则如下：

### 保留

1. **存在未提交编辑**（缓冲 ≠ 快照）——崩溃保护的唯一目的，任何时候都保留。
2. **崩溃后未处理**：异常退出 → 哨兵非干净，缓冲原样保留，下次启动提示恢复。
3. **恢复选「忽略」**：内容保留在缓冲并**登记为未决文档**（分配快照序号，
   进入退出「保存全部 / 全部不保存」的覆盖范围，T-046）——不因忽略而失管。
4. **干净退出**：退出提示覆盖**全部**未决文档（保存全部 / 全部不保存 / 取消，
   T-046）——任一未决文档都会被决定 → **干净退出后缓冲清空**；未决只发生在
   「取消退出」或「崩溃」。（v1.4 修订 v1.3：此前退出提示只覆盖当前文档，
   未决行跨会话滞留；多文档登记落地后不再存在「没被问过」的文档。）

### 删除（三个明确时机）

1. **Cmd+S 合并成功**：内容已固化到快照 `.txt`，缓冲副本冗余 → 删该文档行。
2. **崩溃恢复选「恢复」**：内容载入新文档（新 id 接管自动保存）→ 删被恢复的旧行。
3. **退出提示选「全部不保存」**：用户明确丢弃全部未决文档 → 删全部行。

### 不变量与边界

- **不变量**：缓冲行存在 ⟺ 存在未提交且未明确丢弃的编辑。每一行最终由用户处置：
  合并 → 删 / 丢弃 → 删 / 未决（取消退出或崩溃）→ 留。
- **哨兵只记录退出状态，不承担数据清理**：数据清理由「合并 / 丢弃」决定时刻
  完成；v1.4 起干净退出经「全部未决决定」后缓冲清空，异常退出原样保留。
- **已知限制（T-029 之前）**：恢复 v1 只呈现「最新一个」缓冲文档；其余未决行的
  完整清单与逐个处置随 T-029（scratch 列表 / 会话恢复）落地；在此之前的遗留行
  不是 bug，是「未决」的守恒结果。

## 原因

- **Rule 7（为什么标准库不能解决）：** Rust 标准库没有嵌入式数据库 / 持久化存储能力；SQLite 是 ADR 总纲第 5 节已确定的内部状态存储（负责 Scratch、Session、Recent Files、Undo History、Crash Recovery；拒绝 JSON / YAML）。
- **Rule 11（复用优先）+ Rule 8（第三方库 ADR）：** rusqlite 是同步、最小依赖的成熟绑定（MIT / Apache-2.0），编辑器单线程事件循环不需要异步；拒绝 sqlx（异步运行时重量级）、裸 `sqlite3-sys` FFI（unsafe、重复造轮子）、diesel（ORM 过重）。
- **`bundled` 理由：** 从源码编译 SQLite，构建封闭、版本锁定、不依赖系统 SQLite（与 ADR-012 mlua `vendored` 同理由）。
- **本切片只交付存储原语：** Scratch 自动保存工作流是 T-019，Session / Crash Recovery 的恢复编排是 T-021（ADR-001 备注同步更新）；Undo 持久化边界仍为 ADR-006 未确定项（T-021）。

## 审计

### Single Responsibility — 否（不违反）

store 模块只负责 SQLite 的打开、schema 初始化与 Scratch / Session 的读写；不持有 Buffer、不负责恢复编排、不进入编辑热路径。

### 循环依赖 — 否（不违反）

store 模块不依赖任何其他 Core 模块；依赖方向：`T-019 / T-021 → store`。

## 新增 Public API

| API | 职责 |
| --- | --- |
| `Store::open(&Path) -> Result<Self, StoreError>` | 打开（不存在则创建）数据库并初始化 schema |
| `Store::in_memory() -> Result<Self, StoreError>` | 内存数据库（测试 / 临时会话） |
| `save_scratch(id: u64, content: &str) -> Result<(), StoreError>` | upsert Scratch 内容 |
| `load_scratch(id: u64) -> Result<Option<String>, StoreError>` | 读取 Scratch 内容；不存在返回 `None` |
| `delete_scratch(id: u64) -> Result<bool, StoreError>` | 删除 Scratch；不存在返回 `false`（幂等） |
| `save_session(&[SessionDocument]) -> Result<(), StoreError>` | 整表替换会话记录（单事务原子写入） |
| `load_session() -> Result<Vec<SessionDocument>, StoreError>` | 按保存顺序读取会话 |
| `SessionDocument { id: u64, path: Option<String> }` | 会话中的一条文档；`path: None` 即 Scratch |
| `StoreError::Sqlite(rusqlite::Error)` | 存储层错误（打开 / 写入 / 查询） |

## 影响模块

- **T-019（Scratch 工作流）** — `Cmd+N → save_scratch → Attach Path`，经 `Store` 落盘。
- **T-021（Crash Recovery / Session 恢复）** — 读取 `load_session` + `load_scratch` 编排恢复；schema 迁移以 `user_version` 为锚。
- **ADR-001（DocumentManager）** — 备注更新：存储层由 T-009 交付，接线随上述工作流切片。

## 复杂度预算（宪法 Rule 9）

1. **增加了哪些复杂度？** 1 个模块、1 个依赖（rusqlite bundled）、2 张表、7 个方法、1 个错误变体；0 抽象层。
2. **是否是永久性的？** 是——SQLite 存储层是 ADR 总纲第 5 节的永久结构；schema 只随功能切片增量演进（以 `user_version` 管理）。
3. **有没有更简单但同样满足需求的方案？** JSON 文件更简单但 ADR 总纲已拒绝（复杂状态不可管理）；内存态不做持久化则无法满足 Scratch / Session / Crash Recovery 的既定方向。rusqlite + bundled 是最简单合规方案。

结论：1 模块 / 1 依赖 / 7 方法 / 0 抽象层，未触及红线。

## 备注

- **事务原子性即崩溃恢复的存储前提**：会话整表替换失败时旧会话保持完整（回滚），不会出现半写会话。
- 磁盘文档恢复时的 BufferId 重分配（`DocumentManager::open` 递增分配）属 T-021 编排问题，本层只按保存的 id + path 记录。
- rusqlite 版本锁定于 `Cargo.lock`（docs/dependencies.md 政策）；major 升级需新 ADR。
