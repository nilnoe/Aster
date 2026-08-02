# ADR-013 — SQLite 存储层（Store）

  v1.1 备注（T-043）：新增崩溃恢复原语——`meta` 表存放 `clean_exit` 哨兵
  （干净退出 = "1"，启动时清空；崩溃后为缺省值），`list_scratch` 枚举缓冲文档；
  恢复流程 = App 启动检测哨兵 + 缓冲内容 → 提示恢复（消费方 = AppDelegate，
  T-043）。Session 多文档完整恢复仍在 T-029。

- **Status:** Accepted
- **Date:** 2026-08-02
- **Version:** 1.3
- **新增 Public API:** `Store`（7 方法）+ `SessionDocument`（2 公共字段）+ `StoreError`（1 变体）+ 新增依赖 **rusqlite**（宪法 Rule 7 / 8）
- **影响模块:** Core（新增 store 模块）
- **是否违反 Single Responsibility:** 否
- **是否增加循环依赖:** 否

---

## 决策

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

## 缓冲数据生命周期（v1.3，T-045）

缓冲（`scratch` 表）的语义是「未提交且未明确丢弃的编辑」，不是存档。规则如下：

### 保留

1. **存在未提交编辑**（缓冲 ≠ 快照）——崩溃保护的唯一目的，任何时候都保留。
2. **崩溃后未处理**：异常退出 → 哨兵非干净，缓冲原样保留，下次启动提示恢复。
3. **恢复选「忽略」**：内容暂留，等待用户以后处置（期间再崩溃会再次提示）。
4. **干净退出**：哨兵写 `true` **但不删数据**——未决行跨会话保留（它们是
   「用户还没决定」的内容，不是垃圾；哨兵只负责不误提示）。

### 删除（三个明确时机）

1. **Cmd+S 合并成功**：内容已固化到快照 `.txt`，缓冲副本冗余 → 删该文档行。
2. **崩溃恢复选「恢复」**：内容载入新文档（新 id 接管自动保存）→ 删被恢复的旧行。
3. **退出提示选「不保存」**：用户明确丢弃当前文档 → 删该行。

### 不变量与边界

- **不变量**：缓冲行存在 ⟺ 存在未提交且未明确丢弃的编辑。每一行最终由用户处置：
  合并 → 删 / 丢弃 → 删 / 未决 → 留。
- **哨兵只记录退出状态，不承担数据清理**：干净退出不清空缓冲，异常退出不写入。
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
