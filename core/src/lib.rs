//! Aster 编辑器 Rust Core（T-001 骨架）。
//!
//! 平台无关的编辑核心。决策依据：ADR 要求 Core 不得依赖
//! AppKit / SwiftUI / NSView / NSWindow，本 crate 保持纯 Rust。
//!
//! 结构（ADR-005）：`Buffer` 是第一公民，`BufferId` 是唯一标识，
//! `BufferError` 精确表达失败原因。

mod buffer;
mod document_manager;
mod error;
mod history;
mod layout;
mod selection;

pub use buffer::{Buffer, BufferId};
pub use document_manager::{DocumentManager, DocumentManagerError, DocumentSource};
pub use error::BufferError;
pub use history::{EditOp, History};
pub use layout::Layout;
pub use selection::Selection;
