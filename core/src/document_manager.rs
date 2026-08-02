//! DocumentManager（ADR-001）。
//!
//! 决策依据：
//! - Buffer 是唯一第一公民，但生命周期必须有一个统一所有者，否则会散落到 UI / 插件层，
//!   违反"Core 不允许依赖具体 UI"（ADR）。
//! - 本模块只负责注册、生命周期与存储目标绑定；布局、渲染、命令分发不进入本模块（SRP）。
//! - 激活状态（active buffer）由 T-013 决定，本模块不锁定。

use std::collections::HashMap;
use std::io;
use std::path::PathBuf;

use crate::buffer::{Buffer, BufferId};

/// 文档来源。
///
/// 决策依据：显式枚举，不猜测调用方意图；`Disk` 表示 Attach Path 语义，
/// `Scratch` 表示无路径暂存（SQLite 落盘由 T-009 / T-021 接入）。
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum DocumentSource {
    Disk(PathBuf),
    Scratch,
}

/// DocumentManager 操作的失败类型。
///
/// 决策依据：失败必须可见且可区分（ADR-004）；读取错误保留路径与错误种类，
/// 便于 UI 层向用户给出可操作信息。
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum DocumentManagerError {
    /// 操作的 BufferId 不存在于注册表。
    UnknownBuffer(BufferId),
    /// 磁盘文件读取失败（不存在、无权限或非 UTF-8）。
    ReadFailed { path: PathBuf, kind: io::ErrorKind },
}

/// 注册表条目：Buffer 与存储目标。
///
/// 决策依据：字段当前仅由单元测试读取；`path` 与内容是 ADR-001 定义的注册状态，
/// 将在 T-007（Command）/ T-013（编辑循环）切片中被消费，届时移除 expect。
// 决策依据：非测试构建中字段暂无读取方；测试构建中单元测试会读取，故仅对非测试构建声明预期。
#[cfg_attr(not(test), expect(dead_code))]
#[derive(Debug)]
struct Document {
    buffer: Buffer,
    /// `None` 表示 Scratch（无路径）；`Some` 表示绑定磁盘文件。
    path: Option<PathBuf>,
}

/// 所有 Document / Buffer 的统一注册表与生命周期所有者（ADR-001）。
#[derive(Debug)]
pub struct DocumentManager {
    documents: HashMap<BufferId, Document>,
    /// 决策依据：从 1 开始分配，保留 0 作为"无 buffer"的哨兵值。
    next_id: u64,
}

impl DocumentManager {
    pub fn new() -> Self {
        Self {
            documents: HashMap::new(),
            next_id: 1,
        }
    }

    /// 打开磁盘文件（读取内容并绑定路径）或创建 Scratch，返回新 Buffer 的 id。
    ///
    /// 决策依据：返回 `Result` 而非裸 id——磁盘读取可能失败，失败必须可见（ADR-004）；
    /// 文件内容经 `Buffer::insert` 唯一写入入口加载（ADR-005），不另设内容赋值 API。
    pub fn open(&mut self, source: DocumentSource) -> Result<BufferId, DocumentManagerError> {
        let id = BufferId::new(self.next_id);
        self.next_id += 1;

        let (content, path) = match source {
            DocumentSource::Scratch => (String::new(), None),
            DocumentSource::Disk(path) => {
                let content = std::fs::read_to_string(&path).map_err(|e| {
                    DocumentManagerError::ReadFailed {
                        path: path.clone(),
                        kind: e.kind(),
                    }
                })?;
                (content, Some(path))
            }
        };

        let mut buffer = Buffer::new(id);
        if !content.is_empty() {
            // 新 buffer 为空，偏移 0 必然合法；unwrap 是结构性不变量，而非运行时错误。
            buffer
                .insert(0, &content)
                .expect("empty buffer accepts insert at offset 0");
        }

        self.documents.insert(id, Document { buffer, path });
        Ok(id)
    }

    /// 关闭并移除 Buffer 及其注册信息。
    ///
    /// 决策依据：未知 id 返回错误而非静默成功，调用方才能发现悬空引用（ADR-004）。
    pub fn close(&mut self, id: BufferId) -> Result<(), DocumentManagerError> {
        if self.documents.remove(&id).is_none() {
            return Err(DocumentManagerError::UnknownBuffer(id));
        }
        Ok(())
    }

    /// 按 id 返回注册 Buffer 的文本（T-015：Bridge 读取后建 Editor 会话）。
    ///
    /// 决策依据：`pub(crate)` 而非 `pub`——只供 Bridge 模块使用，不构成公共
    /// API（宪法 Rule 12：任何 `pub` 都是决策，须先 ADR）；未知 id 返回 `None`
    /// 让调用方显式处理（ADR-004：失败可见）。
    pub(crate) fn text(&self, id: BufferId) -> Option<&str> {
        self.documents.get(&id).map(|doc| doc.buffer.text())
    }
}

impl Default for DocumentManager {
    /// 决策依据：与 `new()` 语义一致（空注册表），符合标准库惯例
    /// （clippy::new-without-default）。
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::Path;
    use std::sync::atomic::{AtomicU64, Ordering};

    static COUNTER: AtomicU64 = AtomicU64::new(0);

    fn temp_file(content: &str) -> PathBuf {
        let mut p = std::env::temp_dir();
        p.push(format!(
            "aster-dm-unit-{}-{}.txt",
            std::process::id(),
            COUNTER.fetch_add(1, Ordering::Relaxed)
        ));
        std::fs::write(&p, content).unwrap();
        p
    }

    fn temp_file_bytes(data: &[u8]) -> PathBuf {
        let mut p = std::env::temp_dir();
        p.push(format!(
            "aster-dm-unit-bytes-{}-{}.bin",
            std::process::id(),
            COUNTER.fetch_add(1, Ordering::Relaxed)
        ));
        std::fs::write(&p, data).unwrap();
        p
    }

    #[test]
    fn ids_start_at_one() {
        let mut dm = DocumentManager::new();
        assert_eq!(dm.open(DocumentSource::Scratch).unwrap().as_u64(), 1);
    }

    #[test]
    fn open_disk_loads_content_into_buffer() {
        let mut dm = DocumentManager::new();
        let path = temp_file("你好，世界");
        let id = dm.open(DocumentSource::Disk(path.clone())).unwrap();
        let doc = dm.documents.get(&id).unwrap();
        assert_eq!(doc.buffer.text(), "你好，世界");
        assert_eq!(doc.path.as_deref(), Some(Path::new(&path)));
    }

    #[test]
    fn open_scratch_has_no_path() {
        let mut dm = DocumentManager::new();
        let id = dm.open(DocumentSource::Scratch).unwrap();
        assert_eq!(dm.documents.get(&id).unwrap().path, None);
        assert_eq!(dm.documents.get(&id).unwrap().buffer.text(), "");
    }

    #[test]
    fn open_non_utf8_disk_file_fails() {
        let mut dm = DocumentManager::new();
        let path = temp_file_bytes(&[0xff, 0xfe, 0x00]);
        let err = dm.open(DocumentSource::Disk(path.clone())).unwrap_err();
        assert!(matches!(
            err,
            DocumentManagerError::ReadFailed { path: ref p, kind: io::ErrorKind::InvalidData } if p == &path
        ));
    }

    #[test]
    fn close_removes_document() {
        let mut dm = DocumentManager::new();
        let id = dm.open(DocumentSource::Scratch).unwrap();
        dm.close(id).unwrap();
        assert!(!dm.documents.contains_key(&id));
    }

    #[test]
    fn text_accessor_returns_registered_content() {
        let mut dm = DocumentManager::new();
        let path = temp_file("你好，世界");
        let id = dm.open(DocumentSource::Disk(path)).unwrap();
        assert_eq!(dm.text(id), Some("你好，世界"));
        assert_eq!(dm.text(BufferId::new(999)), None, "未知 id 必须返回 None");
    }
}
