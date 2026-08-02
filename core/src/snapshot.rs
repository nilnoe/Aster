//! 纯文本快照文件（T-042，ADR-023 v1.4）。
//!
//! 决策依据：
//! - 快照 = 文档的提交产物，必须是**可打开的文本文件**（用户指出 .sqlite 无法在
//!   Buffer 打开）；命名 `aster-YYYY-MM-DD-<seq>.txt`，日期 + 序号轮转（Cmd+N
//!   创建、Cmd+S 合并、T-028 读回）。
//! - 独立模块而非塞进 Store（Rule 3 单一职责）：Store 的职责是 SQLite（ADR-013），
//!   快照是纯文本文件；目录与日期语义共享（`today_iso` 复用，pub(crate)，Rule 11）。
//! - 文件即内容：写 = 整文件覆盖（提交 / 固化语义，无增量结构）；崩溃时已合并的
//!   快照完整，未合并的编辑在 buffer.sqlite（ADR-023 v1.4 决策 2）。
use std::io;
use std::path::{Path, PathBuf};

use crate::store::today_iso;

/// 快照目录句柄：管理当日「日期+序号」纯文本快照文件。
pub struct Snapshot {
    dir: PathBuf,
}

impl Snapshot {
    pub fn new(dir: PathBuf) -> Self {
        Self { dir }
    }

    /// Cmd+N：创建当日下一个序号文本文件并返回 seq（ADR-023 v1.4 决策 2）。
    ///
    /// 决策依据：seq = 当日最大序号 + 1（容忍缺号，数值排序）；目录不存在则创建
    /// （默认目录首次启动可能不存在，失败可见，ADR-004）。
    pub fn create_next(&self) -> Result<i64, io::Error> {
        std::fs::create_dir_all(&self.dir)?;
        let next = self.latest_seq()?.map_or(0, |seq| seq) + 1;
        let path = self.path_for(next);
        std::fs::write(path, "")?;
        Ok(next)
    }

    /// Cmd+S：把缓冲文本合并（覆盖写）进指定序号快照（提交 / 固化）。
    ///
    /// 决策依据：合并不是新建文件——快照文件由 Cmd+N 创建，Cmd+S 只固化内容，
    /// 保持「一次 Cmd+N = 一个文档版本」的映射（ADR-023 v1.4）。
    pub fn write(&self, seq: i64, content: &str) -> Result<(), io::Error> {
        std::fs::write(self.path_for(seq), content)
    }

    /// 读取快照内容（T-028 恢复 / 测试）。
    pub fn read(&self, seq: i64) -> Result<String, io::Error> {
        std::fs::read_to_string(self.path_for(seq))
    }

    /// 当日最高序号（无快照返回 `None`）。
    pub fn latest_seq(&self) -> Result<Option<i64>, io::Error> {
        Ok(self.daily_files()?.last().map(|(seq, _)| *seq))
    }

    /// 删除目录中内容为空的快照文件，返回删除数量（T-047，ADR-023 v1.6）。
    ///
    /// 决策依据：启动即建的 001、⌘N 后从未输入 / 合并的空快照不应在默认目录
    /// 累积（用户指示：空文件在进程生命周期结束后删除）。只删 `aster-*.txt`
    /// 且零长度的文件（空文件无内容可丢）；目录缺失返回 0（幂等）；崩溃退出
    /// 不调用本方法（下次干净退出一并处理）。
    pub fn prune_empty(&self) -> Result<usize, io::Error> {
        let entries = match std::fs::read_dir(&self.dir) {
            Ok(entries) => entries,
            Err(e) if e.kind() == io::ErrorKind::NotFound => return Ok(0),
            Err(e) => return Err(e),
        };
        let mut deleted = 0;
        for entry in entries.flatten() {
            let Ok(name) = entry.file_name().into_string() else {
                continue;
            };
            if !name.starts_with("aster-") || !name.ends_with(".txt") {
                continue;
            }
            if entry.metadata()?.len() == 0 {
                std::fs::remove_file(entry.path())?;
                deleted += 1;
            }
        }
        Ok(deleted)
    }

    fn path_for(&self, seq: i64) -> PathBuf {
        self.dir.join(format!("aster-{}-{seq:03}.txt", today_iso()))
    }

    /// 当日 `aster-YYYY-MM-DD-<seq>.txt` 列表，按 seq 数值升序。
    ///
    /// 决策依据：序号以数值排序而非词法序（零填充 3 位在 >999 时词法序会错）；
    /// 目录缺失视为空列表（create_next 前目录不存在属正常首次启动）。
    fn daily_files(&self) -> Result<Vec<(i64, PathBuf)>, io::Error> {
        let prefix = format!("aster-{}-", today_iso());
        let entries = match std::fs::read_dir(&self.dir) {
            Ok(entries) => entries,
            Err(e) if e.kind() == io::ErrorKind::NotFound => return Ok(Vec::new()),
            Err(e) => return Err(e),
        };
        let mut files = entries
            .flatten()
            .filter_map(|entry| {
                let name = entry.file_name().into_string().ok()?;
                if !name.starts_with(&prefix) || !name.ends_with(".txt") {
                    return None;
                }
                let seq: i64 = name[prefix.len()..name.len() - ".txt".len()].parse().ok()?;
                Some((seq, entry.path()))
            })
            .collect::<Vec<_>>();
        files.sort_by_key(|(seq, _)| *seq);
        Ok(files)
    }
}

impl From<&Path> for Snapshot {
    /// 决策依据：与 `new` 等价，便于从 `&Path` 直接构造（clippy 惯例）。
    fn from(path: &Path) -> Self {
        Self::new(path.to_path_buf())
    }
}

#[cfg(test)]
mod tests {
    use super::Snapshot;
    use std::path::PathBuf;
    use std::sync::atomic::{AtomicU64, Ordering};

    static COUNTER: AtomicU64 = AtomicU64::new(0);

    fn temp_dir(label: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!(
            "aster-snapshot-{}-{}-{}",
            label,
            std::process::id(),
            COUNTER.fetch_add(1, Ordering::Relaxed)
        ));
        let _ = std::fs::remove_dir_all(&dir);
        dir
    }

    fn file_names(dir: &PathBuf) -> Vec<String> {
        let mut names = std::fs::read_dir(dir)
            .unwrap()
            .map(|e| e.unwrap().file_name().into_string().unwrap())
            .filter(|n| n.starts_with("aster-") && n.ends_with(".txt"))
            .collect::<Vec<_>>();
        names.sort();
        names
    }

    #[test]
    fn create_next_creates_dir_and_sequenced_text_files() {
        let dir = temp_dir("next");
        let snap = Snapshot::new(dir.clone());
        let seq1 = snap.create_next().unwrap();
        let seq2 = snap.create_next().unwrap();
        assert_eq!(seq2, seq1 + 1, "序号必须递增");
        let names = file_names(&dir);
        assert_eq!(names.len(), 2);
        assert!(names[0].ends_with("-001.txt") && names[1].ends_with("-002.txt"));
    }

    #[test]
    fn create_next_seq_jumps_over_gaps() {
        let dir = temp_dir("gaps");
        let snap = Snapshot::new(dir.clone());
        let _ = snap.create_next().unwrap();
        let _ = snap.create_next().unwrap();
        let names = file_names(&dir);
        let gap = names[0].replace("-001.txt", "-003.txt");
        std::fs::rename(dir.join(&names[0]), dir.join(&gap)).unwrap();
        assert_eq!(snap.create_next().unwrap(), 4, "缺号后取最大 + 1");
    }

    #[test]
    fn write_read_roundtrip_and_plain_text() {
        let dir = temp_dir("roundtrip");
        let snap = Snapshot::new(dir.clone());
        let seq = snap.create_next().unwrap();
        snap.write(seq, "第一行\n你好，世界").unwrap();
        assert_eq!(snap.read(seq).unwrap(), "第一行\n你好，世界");
        // 快照必须是可直接打开的纯文本文件（.sqlite 无法在 Buffer 打开的用户反馈）。
        let names = file_names(&dir);
        assert_eq!(names.len(), 1);
        assert_eq!(
            std::fs::read_to_string(dir.join(&names[0])).unwrap(),
            "第一行\n你好，世界"
        );
    }

    #[test]
    fn latest_seq_returns_highest_or_none() {
        let dir = temp_dir("latest");
        let snap = Snapshot::new(dir.clone());
        assert_eq!(snap.latest_seq().unwrap(), None, "空目录无快照");
        let _ = snap.create_next().unwrap();
        let s2 = snap.create_next().unwrap();
        assert_eq!(snap.latest_seq().unwrap(), Some(s2));
    }

    #[test]
    fn prune_empty_deletes_only_zero_length_snapshots() {
        let dir = temp_dir("prune");
        let snap = Snapshot::new(dir.clone());
        let empty1 = snap.create_next().unwrap();
        let _ = snap.create_next().unwrap();
        snap.write(empty1 + 1, "内容").unwrap();
        // 无关空文件不在命名规范内，不得删除。
        std::fs::write(dir.join("notes.txt"), "").unwrap();

        assert_eq!(snap.prune_empty().unwrap(), 1, "只删零长度快照");
        let names = file_names(&dir);
        assert_eq!(names.len(), 1, "只剩非空快照");
        assert_eq!(
            std::fs::read_to_string(dir.join(&names[0])).unwrap(),
            "内容"
        );
        assert!(dir.join("notes.txt").exists(), "无关文件不受影响");
    }

    #[test]
    fn prune_empty_on_missing_dir_returns_zero() {
        let dir = temp_dir("prune-none");
        let snap = Snapshot::new(dir.clone());
        assert_eq!(snap.prune_empty().unwrap(), 0, "目录缺失幂等返回 0");
    }
}
