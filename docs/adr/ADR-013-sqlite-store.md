# ADR-013 — SQLite 存储层（Store）

  v1.1 备注（T-043）：新增崩溃恢复原语——`meta` 表存放 `clean_exit` 哨兵
  （干净退出 = "1"，启动时清空；崩溃后为缺省值），`list_scratch` 枚举缓冲文档；
  恢复流程 = App 启动检测哨兵 + 缓冲内容 → 提示恢复（消费方 = AppDelegate，
  T-043）。Session 多文档完整恢复仍在 T-029。

- **Status:** Accepted
- **Date:** 2026-08-02
- **Version:** 1.0
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
