//! 会话层错误类型（T-070，ADR-025）。
//!
//! 决策依据：与业务模块拆分同构（Rule 3：session.rs 保持状态机主体 ≤300 行）；
//! 错误经 Bridge 统一映射为消息字符串（ADR-014 惯例）。

use crate::document_manager::DocumentManagerError;
use crate::store::StoreError;

/// 会话层错误。
#[derive(Debug)]
pub enum SessionError {
    /// 文档不在会话登记（id 非法或已被关闭）。
    UnknownDoc(u64),
    /// 缓冲存储未就绪（启动打开失败 / 损坏），保存 / 恢复不可用。
    StoreNotReady,
    /// 文档没有可合并的快照（存储故障时创建的容忍路径，ADR-023 v1.3）。
    NoSnapshot(u64),
    /// 缓冲行缺失（保存 / 恢复读取不到内容）。
    MissingBuffer(u64),
    /// DocumentManager 打开失败（磁盘读取，ADR-001）。
    DocumentManager(DocumentManagerError),
    /// 缓冲层失败（SQLite）。
    Store(StoreError),
    /// 快照文件层失败（IO）。
    Io(std::io::Error),
}

impl From<StoreError> for SessionError {
    fn from(e: StoreError) -> Self {
        SessionError::Store(e)
    }
}

impl From<DocumentManagerError> for SessionError {
    fn from(e: DocumentManagerError) -> Self {
        SessionError::DocumentManager(e)
    }
}

impl From<std::io::Error> for SessionError {
    fn from(e: std::io::Error) -> Self {
        SessionError::Io(e)
    }
}
