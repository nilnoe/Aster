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
    /// 非 SQLite 的 IO 失败（T-040，ADR-023 v1.1：轮转目录创建失败）。
    Io(std::io::Error),
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

    /// Cmd+N：创建当日下一个序号快照文件并返回 seq（T-041，ADR-023 v1.3 决策 2）。
    ///
    /// 决策依据：
    /// - 快照文件 = 文档的提交版本；每次 Cmd+N 新文档 = 当日下一个序号文件
    ///   （`aster-YYYY-MM-DD-<seq>.sqlite`），seq = 当日最大 + 1（容忍缺号）。
    /// - 目录不存在则创建（默认路径首次启动可能不存在；失败经 `StoreError::Io`
    ///   可见，ADR-004）。
    /// - 日期用 UTC（纯 Rust 标准库可算，跨时区确定、可测试）；本地时区午夜轮转
    ///   随配置系统细化（ADR-023 v1.3 备注）。
    /// - civil date 换算用 Howard Hinnant days-from-civil 标准算法，不引入 chrono
    ///   （Rule 7：标准库可解决；新依赖需 ADR）。
    pub fn next_snapshot(dir: &Path) -> Result<i64, StoreError> {
        std::fs::create_dir_all(dir).map_err(StoreError::Io)?;
        let next = daily_seq_paths(dir).last().map_or(0, |(seq, _)| *seq) + 1;
        let path = dir.join(format!("aster-{}-{next:03}.sqlite", today_iso()));
        Self::open(&path)?;
        Ok(next)
    }

    /// Cmd+S 合并目标：打开指定序号快照文件（T-041，ADR-023 v1.3 决策 2）。
    ///
    /// 决策依据：合并 = 把缓冲内容 upsert 进当前快照（提交 / 固化），不是新建
    /// 文件；序号由 App 在 Cmd+N 时记录。
    pub fn open_snapshot(dir: &Path, seq: i64) -> Result<Self, StoreError> {
        let path = dir.join(format!("aster-{}-{seq:03}.sqlite", today_iso()));
        Self::open(&path)
    }

    /// 自动保存缓冲文件 `<dir>/buffer.sqlite`（T-041，ADR-023 v1.3 决策 2）。
    ///
    /// 决策依据：缓冲 = 崩溃保护的连续工作副本（每次内容变更写入，无需用户
    /// 按保存）；独立于快照文件，避免每次按键产生新快照。固定文件名不按日期
    /// 轮转（缓冲是当前会话的临时工作区，跨天保留由 T-029 会话恢复编排）。
    pub fn open_buffer(dir: &Path) -> Result<Self, StoreError> {
        std::fs::create_dir_all(dir).map_err(StoreError::Io)?;
        Self::open(&dir.join("buffer.sqlite"))
    }

    /// 打开当日最高序号快照文件（读取 / 继续；T-040，ADR-023 v1.2 决策 2）。
    ///
    /// 决策依据：无文件返回 `None`（调用方显式处理，ADR-004）；序号按数值排序，
    /// 不依赖零填充的宽度（缺号 / 超 999 都正确）。
    pub fn open_latest(dir: &Path) -> Result<Option<Self>, StoreError> {
        let Some((_, path)) = daily_seq_paths(dir).last().cloned() else {
            return Ok(None);
        };
        Self::open(&path).map(Some)
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

/// 今日日期 `YYYY-MM-DD`（UTC，T-040，ADR-023 v1.1）。
///
/// 决策依据：`pub(crate)` 不构成公共 API（Rule 12）；单元测试直接校验
/// `civil_from_days` 的已知 epoch 值，避免"用实现验证实现"。
pub(crate) fn today_iso() -> String {
    let secs = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs() as i64;
    let days = secs.div_euclid(86_400);
    let (y, m, d) = civil_from_days(days);
    format!("{y:04}-{m:02}-{d:02}")
}

/// 当日 `aster-YYYY-MM-DD-<seq>.sqlite` 文件列表，按 seq 数值升序。
///
/// 决策依据：序号以数值排序而非词法序（零填充 3 位在 >999 时词法序会错）；
/// 非当日 / 非本命名规范的文件（如用户放入的其他文件）一律忽略。
fn daily_seq_paths(dir: &Path) -> Vec<(i64, std::path::PathBuf)> {
    let prefix = format!("aster-{}-", today_iso());
    let Ok(entries) = std::fs::read_dir(dir) else {
        return Vec::new();
    };
    let mut files = entries
        .flatten()
        .filter_map(|entry| {
            let name = entry.file_name().into_string().ok()?;
            if !name.starts_with(&prefix) || !name.ends_with(".sqlite") {
                return None;
            }
            let seq: i64 = name[prefix.len()..name.len() - ".sqlite".len()]
                .parse()
                .ok()?;
            Some((seq, entry.path()))
        })
        .collect::<Vec<_>>();
    files.sort_by_key(|(seq, _)| *seq);
    files
}

/// 天数（自 1970-01-01）→ (年, 月, 日)，UTC。
///
/// Howard Hinnant 的 civil_from_days 标准算法（与 days_from_civil 互逆），
/// 广泛验证过的民用历法换算；Rule 11 注释：这是标准算法而非自研轮子。
fn civil_from_days(z: i64) -> (i64, u32, u32) {
    let z = z + 719_468;
    let era = if z >= 0 { z } else { z - 146_096 } / 146_097;
    let doe = z - era * 146_097;
    let yoe = (doe - doe / 1_460 + doe / 36_524 - doe / 146_096) / 365;
    let y = yoe + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = (doy - (153 * mp + 2) / 5 + 1) as u32;
    let m = if mp < 10 { mp + 3 } else { mp - 9 } as u32;
    let y = if m <= 2 { y + 1 } else { y };
    (y, m, d)
}

#[cfg(test)]
mod tests {
    use super::civil_from_days;

    /// 已知 epoch 天数 → 日期（数值来自 UTC 历法，2026-08-02 = 20667 等）。
    #[test]
    fn civil_from_days_known_epochs() {
        assert_eq!(civil_from_days(0), (1970, 1, 1));
        assert_eq!(civil_from_days(20_667), (2026, 8, 2));
        assert_eq!(civil_from_days(19_782), (2024, 2, 29), "闰年 2/29");
        assert_eq!(civil_from_days(19_783), (2024, 3, 1));
        assert_eq!(civil_from_days(11_016), (2000, 2, 29), "400 年闰 2000");
        assert_eq!(civil_from_days(-25_509), (1900, 2, 28), "100 年不闰 1900");
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
