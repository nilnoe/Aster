//! SQLite 存储层（ADR-013）。
//!
//! 决策依据：
//! - SQLite 是 ADR 总纲第 5 节确定的内部状态存储；rusqlite 是同步、最小依赖的
//!   成熟绑定（Rule 11；sqlx 异步过重、裸 FFI 是 unsafe 重复造轮子）。
//! - `bundled` 从源码编译 SQLite，构建封闭、版本锁定（与 ADR-012 mlua vendored 同理）。
//! - 本切片只交付存储原语（scratch / session 两张表）；Scratch 工作流接线在 T-019，
//!   Session / Crash Recovery 编排在 T-021（ADR-001 备注）。

use std::fmt;
use std::path::Path;

use rusqlite::{params, Connection, OptionalExtension};

/// 会话中的一条文档记录。
///
/// 决策依据：`path: None` 即 Scratch（与 ADR-001 `Document.path` 语义一致）；
/// 磁盘文档必有路径，路径有无天然区分类型，无需冗余 kind 列。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SessionDocument {
    pub id: u64,
    pub path: Option<String>,
}

/// 存储层错误。
#[derive(Debug)]
pub enum StoreError {
    /// SQLite 操作失败（打开、写入、查询）。
    Sqlite(rusqlite::Error),
}

/// SQLite 存储层：Scratch 内容与会话记录（ADR-013）。
pub struct Store {
    conn: Connection,
}

impl fmt::Debug for Store {
    /// Connection 不实现 Debug；只暴露数据库路径便于定位。
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("Store")
            .field("db", &self.conn.path())
            .finish()
    }
}

impl Store {
    /// 打开（不存在则创建）数据库并初始化 v1 schema。
    pub fn open(path: &Path) -> Result<Self, StoreError> {
        let conn = Connection::open(path).map_err(StoreError::Sqlite)?;
        init_schema(&conn)?;
        Ok(Self { conn })
    }

    /// 内存数据库（测试 / 临时会话）。
    pub fn in_memory() -> Result<Self, StoreError> {
        let conn = Connection::open_in_memory().map_err(StoreError::Sqlite)?;
        init_schema(&conn)?;
        Ok(Self { conn })
    }

    /// 保存 / 覆盖 Scratch 内容（upsert）。
    pub fn save_scratch(&mut self, id: u64, content: &str) -> Result<(), StoreError> {
        self.conn
            .execute(
                "INSERT OR REPLACE INTO scratch (id, content) VALUES (?1, ?2)",
                params![id as i64, content],
            )
            .map_err(StoreError::Sqlite)?;
        Ok(())
    }

    /// 读取 Scratch 内容；不存在返回 `None`。
    pub fn load_scratch(&self, id: u64) -> Result<Option<String>, StoreError> {
        self.conn
            .query_row(
                "SELECT content FROM scratch WHERE id = ?1",
                params![id as i64],
                |row| row.get(0),
            )
            .optional()
            .map_err(StoreError::Sqlite)
    }

    /// 删除 Scratch；不存在返回 `false`（幂等，UI 销毁路径不报错）。
    pub fn delete_scratch(&mut self, id: u64) -> Result<bool, StoreError> {
        let changed = self
            .conn
            .execute("DELETE FROM scratch WHERE id = ?1", params![id as i64])
            .map_err(StoreError::Sqlite)?;
        Ok(changed > 0)
    }

    /// 整表替换会话记录。
    ///
    /// 决策依据：单事务保证原子性——写入失败时旧会话保持完整，
    /// 这是 Crash Recovery（T-021）的存储层前提（ADR-013 备注）。
    pub fn save_session(&mut self, documents: &[SessionDocument]) -> Result<(), StoreError> {
        let tx = self.conn.transaction().map_err(StoreError::Sqlite)?;
        tx.execute("DELETE FROM session", [])
            .map_err(StoreError::Sqlite)?;
        for (position, doc) in documents.iter().enumerate() {
            tx.execute(
                "INSERT INTO session (position, id, path) VALUES (?1, ?2, ?3)",
                params![position as i64, doc.id as i64, doc.path.as_deref()],
            )
            .map_err(StoreError::Sqlite)?;
        }
        tx.commit().map_err(StoreError::Sqlite)
    }

    /// 读取会话，按保存时的顺序（position）返回。
    pub fn load_session(&self) -> Result<Vec<SessionDocument>, StoreError> {
        let mut stmt = self
            .conn
            .prepare("SELECT id, path FROM session ORDER BY position")
            .map_err(StoreError::Sqlite)?;
        let rows = stmt
            .query_map([], |row| {
                Ok(SessionDocument {
                    // 决策依据：rusqlite 未实现 u64 的 FromSql，读取按 i64 再转型；
                    // 写入侧同样以 i64 存储（save_session / save_scratch）。
                    id: row.get::<_, i64>(0)? as u64,
                    path: row.get(1)?,
                })
            })
            .map_err(StoreError::Sqlite)?;
        rows.collect::<Result<Vec<_>, _>>()
            .map_err(StoreError::Sqlite)
    }
}

/// 初始化 v1 schema；`user_version` 作为未来迁移的锚点（T-021）。
fn init_schema(conn: &Connection) -> Result<(), StoreError> {
    conn.execute_batch(
        "PRAGMA user_version = 1;
         CREATE TABLE IF NOT EXISTS scratch (
             id INTEGER PRIMARY KEY,
             content TEXT NOT NULL
         );
         CREATE TABLE IF NOT EXISTS session (
             position INTEGER PRIMARY KEY,
             id INTEGER NOT NULL,
             path TEXT
         );",
    )
    .map_err(StoreError::Sqlite)
}
