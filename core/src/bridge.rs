//! Swift Bridge FFI 面（T-010 spike，ADR-014）。
//!
//! 决策依据：
//! - swift-bridge 是 ADR 总纲 3.4 已定的桥接方案（拒绝手写 FFI / IPC）；
//!   本模块只声明 FFI 面，业务逻辑仍在各业务模块（SRP）。
//! - 桥接真实 Buffer / BufferId / BufferError：API 面验证才有意义，
//!   T-013 编辑循环直接复用；桥接侧只做机械类型适配（usize↔UInt 等）。
//! - opaque 类型经 `super::` 解析（下方 `use` 导入即可）；已有枚举用
//!   `already_declared` 引用真实定义，避免生成第二份类型。
//! - BufferError 结构化桥接推迟：swift-bridge 0.1.59 对 already_declared 枚举
//!   不自动生成 FFI 转换，需手写 SharedEnum + repr(C) 类型（即手写 FFI 胶水，
//!   违反总纲 3.4）；本切片经 `buffer_insert` 把错误映射为消息字符串（ADR-014 备注）。
//! - `Result` 返回与 `&str` 参数组合生成的 Swift 无法编译（0.1.59 上游 bug），
//!   桥接函数改用 `String` 参数规避（ADR-014 备注）。
// 决策依据：swift-bridge 生成的 FFI 胶水含同类型指针转换（如
// `*mut Buffer as *mut Buffer`），clippy 报 unnecessary_cast；这是代码生成器
// 输出而非手写代码，整文件允许该 lint（宪法 Rule 10：注释给出决策依据）。
#![allow(clippy::unnecessary_cast)]

use crate::buffer::{Buffer, BufferId};
use crate::document_manager::{DocumentManager, DocumentSource};
use crate::editor::{Editor, Movement};
use crate::layout::Layout;
use crate::snapshot::Snapshot;
use crate::store::Store;

/// 核心版本号（验证 String 往返；内容来自 Cargo.toml）。
pub fn core_version() -> String {
    env!("CARGO_PKG_VERSION").to_string()
}

/// 桥接适配：把 `Buffer::insert` 的错误映射为消息字符串。
///
/// 决策依据：swift-bridge 0.1.59 不自动支持桥接已存在的 payload 枚举
/// （手写 FFI repr 违反总纲 3.4）；String 错误满足 spike 的 API 面验证，
/// 结构化错误映射在 T-013（编辑循环）设计。
pub fn buffer_insert(buffer: &mut Buffer, at: usize, s: String) -> Result<usize, String> {
    buffer.insert(at, &s).map_err(|e| format!("{e:?}"))
}

/// 行起始字节偏移（首元素恒为 0），供 App 按行切分 Buffer 文本做 CoreText shaping。
///
/// 决策依据：复用 Core `Layout`（ADR-009）的行结构，App 不另造 `\n` 切分
/// （宪法 Rule 11）；字节语义与 Buffer 一致（ADR-005）。
pub fn layout_line_starts(text: String) -> Vec<usize> {
    Layout::build(&text).line_starts().to_vec()
}

// --- DocumentManager 桥接面（T-015，ADR-001 v1.1） ---
//
// 决策依据：
// - 文件打开（NSOpenPanel / 拖放）经 DocumentManager Disk 源读取内容，App 用
//   文本新建 Buffer + Editor 会话（ADR-017：Editor 消费 Buffer）。
// - id 以 usize 透传：swift-bridge 0.1.59 的 Result C 结构命名对 u64 未实现
//   （bridged_type.rs 的 todo!() 崩溃，实测）；usize 是既有验证路径
//   （ADR-014 惯例：机械适配规避生成器短板）。
// - 错误映射为消息字符串（ADR-014 惯例）。

/// 建立 DocumentManager 注册表（App 持有 opaque，首次进产品，Rule 14 处置）。
pub fn document_manager_new() -> DocumentManager {
    DocumentManager::new()
}

/// Cmd+N 新建 Scratch 文档（T-041，ADR-001 v1.2）：注册表分配唯一 id，
/// 作为缓冲 / 快照的保存键（ADR 总纲 §6：Scratch 自动保存、无需命名）。
///
/// 决策依据：Scratch 打开不涉及 IO，理论上不可失败；仍返回 Result 保持与
/// Disk 打开同构的错误面（ADR-004 精神：统一失败语义）。
pub fn document_manager_open_scratch(dm: &mut DocumentManager) -> Result<usize, String> {
    dm.open(DocumentSource::Scratch)
        .map(|id| id.as_u64() as usize)
        .map_err(|e| format!("{e:?}"))
}

/// 打开磁盘文件（ADR-001 Disk 源），返回注册的 BufferId（u64）。
pub fn document_manager_open_disk(dm: &mut DocumentManager, path: String) -> Result<usize, String> {
    dm.open(DocumentSource::Disk(path.into()))
        .map(|id| id.as_u64() as usize)
        .map_err(|e| format!("{e:?}"))
}

/// 按 id 取注册 Buffer 文本（App 建 Editor 会话用；未知 id 返回空串）。
///
/// 决策依据：调用方只查询刚由 open 返回的 id，未知 id 返回空串是最小错误面；
/// Core 侧访问器为 `pub(crate)`（ADR-001 v1.1，Rule 12）。
pub fn document_manager_text(dm: &DocumentManager, id: usize) -> String {
    dm.text(BufferId::new(id as u64)).unwrap_or("").to_string()
}

// --- Store 桥接面（T-040，ADR-023 v1.1） ---
//
// 决策依据：
// - Cmd+S 自动保存到 SQLite（按日期轮转）是本版本的保存目标；磁盘写回（用户指定
//   路径）Deferred 到未来文件系统切片（ADR-023 v1.1 决策 1）。
// - id 以 usize 透传（ADR-014 惯例）；错误映射为消息字符串（ADR-014 惯例）。

// --- Snapshot 桥接面（T-042，ADR-023 v1.4） ---
//
// 决策依据：快照是纯文本文件（用户反馈 .sqlite 无法在 Buffer 打开）；Cmd+N 创建
// 文本快照、Cmd+S 把缓冲文本合并进当前快照；错误映射为消息字符串（ADR-014 惯例）。

/// 建立快照目录句柄（App 持有 opaque）。
pub fn snapshot_new(dir: String) -> Snapshot {
    Snapshot::new(std::path::PathBuf::from(dir))
}

/// Cmd+N：创建当日下一个序号文本快照并返回 seq。
pub fn snapshot_create_next(snapshot: &Snapshot) -> Result<usize, String> {
    snapshot
        .create_next()
        .map(|seq| seq as usize)
        .map_err(|e| format!("{e:?}"))
}

/// Cmd+S：把缓冲文本合并（覆盖写）进指定序号快照（提交 / 固化）。
pub fn snapshot_write(snapshot: &Snapshot, seq: usize, content: String) -> Result<(), String> {
    snapshot
        .write(seq as i64, &content)
        .map_err(|e| format!("{e:?}"))
}

/// 读取快照内容（T-028 恢复 / 测试）。
pub fn snapshot_read(snapshot: &Snapshot, seq: usize) -> Result<String, String> {
    snapshot.read(seq as i64).map_err(|e| format!("{e:?}"))
}

/// 自动保存缓冲文件（崩溃保护；App 启动时打开并保持连接）。
pub fn store_open_buffer(dir: String) -> Result<Store, String> {
    Store::open_buffer(std::path::Path::new(&dir)).map_err(|e| format!("{e:?}"))
}

/// Cmd+S 保存点：把 Buffer 文本 upsert 进 scratch 表（ADR-023 v1.1 决策 6）。
pub fn store_save_scratch(store: &mut Store, id: usize, content: String) -> Result<(), String> {
    store
        .save_scratch(id as u64, &content)
        .map_err(|e| format!("{e:?}"))
}

/// 读取已保存内容（测试 / T-028 Scratch 接线用）；不存在返回错误。
pub fn store_load_scratch(store: &Store, id: usize) -> Result<String, String> {
    store
        .load_scratch(id as u64)
        .map_err(|e| format!("{e:?}"))?
        .ok_or_else(|| format!("scratch {id} not found"))
}
// --- Editor 桥接面（T-013，ADR-017） ---
//
// 决策依据：
// - 移动方向用 8 个独立函数而非桥接 `Movement` 枚举：swift-bridge 0.1.59 对
//   already_declared 枚举需手写 FFI 胶水（ADR-014 备注），机械拆分零风险；
//   Core 侧仍保留 Movement 供 Rust 调用方与测试使用。
// - 编辑操作的错误映射为消息字符串（ADR-014 惯例）；成功返回光标位置（head）
//   或 bool，UI 无需回读整段状态。

pub fn editor_new(buffer: Buffer) -> Editor {
    Editor::new(buffer)
}

pub fn editor_text(editor: &Editor) -> &str {
    editor.text()
}

pub fn editor_selection_start(editor: &Editor) -> usize {
    editor.selection().start()
}

pub fn editor_selection_end(editor: &Editor) -> usize {
    editor.selection().end()
}

pub fn editor_selection_head(editor: &Editor) -> usize {
    editor.selection().head()
}

pub fn editor_type_text(editor: &mut Editor, s: String) -> Result<usize, String> {
    editor.type_text(&s).map_err(|e| format!("{e:?}"))?;
    Ok(editor.selection().head())
}

pub fn editor_delete_backward(editor: &mut Editor) -> Result<usize, String> {
    editor.delete_backward().map_err(|e| format!("{e:?}"))?;
    Ok(editor.selection().head())
}

pub fn editor_undo(editor: &mut Editor) -> Result<bool, String> {
    editor.undo().map_err(|e| format!("{e:?}"))
}

pub fn editor_redo(editor: &mut Editor) -> Result<bool, String> {
    editor.redo().map_err(|e| format!("{e:?}"))
}

pub fn editor_select_all(editor: &mut Editor) {
    editor.select_all();
}

pub fn editor_set_selection(editor: &mut Editor, anchor: usize, head: usize) {
    editor.set_selection(anchor, head);
}

macro_rules! editor_move_fn {
    ($name:ident, $movement:ident) => {
        pub fn $name(editor: &mut Editor, extend: bool) {
            editor.move_cursor(Movement::$movement, extend);
        }
    };
}

editor_move_fn!(editor_move_left, Left);
editor_move_fn!(editor_move_right, Right);
editor_move_fn!(editor_move_up, Up);
editor_move_fn!(editor_move_down, Down);
editor_move_fn!(editor_move_line_start, LineStart);
editor_move_fn!(editor_move_line_end, LineEnd);
editor_move_fn!(editor_move_doc_start, DocStart);
editor_move_fn!(editor_move_doc_end, DocEnd);

#[swift_bridge::bridge]
// 决策依据：生成的 FFI 胶水含同类型指针转换（如 `*mut Buffer as *mut Buffer`），
// clippy 视其为 unnecessary_cast；这是代码生成器输出而非手写代码，允许该 lint。
#[allow(clippy::unnecessary_cast)]
mod ffi {
    extern "Rust" {
        fn core_version() -> String;
        fn buffer_insert(buffer: &mut Buffer, at: usize, s: String) -> Result<usize, String>;
        fn layout_line_starts(text: String) -> Vec<usize>;
        fn document_manager_new() -> DocumentManager;
        fn document_manager_open_scratch(dm: &mut DocumentManager) -> Result<usize, String>;
        fn document_manager_open_disk(
            dm: &mut DocumentManager,
            path: String,
        ) -> Result<usize, String>;
        fn document_manager_text(dm: &DocumentManager, id: usize) -> String;
        fn editor_new(buffer: Buffer) -> Editor;
        fn editor_text(editor: &Editor) -> &str;
        fn editor_selection_start(editor: &Editor) -> usize;
        fn editor_selection_end(editor: &Editor) -> usize;
        fn editor_selection_head(editor: &Editor) -> usize;
        fn editor_type_text(editor: &mut Editor, s: String) -> Result<usize, String>;
        fn editor_delete_backward(editor: &mut Editor) -> Result<usize, String>;
        fn editor_undo(editor: &mut Editor) -> Result<bool, String>;
        fn editor_redo(editor: &mut Editor) -> Result<bool, String>;
        fn editor_select_all(editor: &mut Editor);
        fn editor_set_selection(editor: &mut Editor, anchor: usize, head: usize);
        fn editor_move_left(editor: &mut Editor, extend: bool);
        fn editor_move_right(editor: &mut Editor, extend: bool);
        fn editor_move_up(editor: &mut Editor, extend: bool);
        fn editor_move_down(editor: &mut Editor, extend: bool);
        fn editor_move_line_start(editor: &mut Editor, extend: bool);
        fn editor_move_line_end(editor: &mut Editor, extend: bool);
        fn editor_move_doc_start(editor: &mut Editor, extend: bool);
        fn editor_move_doc_end(editor: &mut Editor, extend: bool);
        fn store_open_buffer(dir: String) -> Result<Store, String>;
        fn store_save_scratch(store: &mut Store, id: usize, content: String) -> Result<(), String>;
        fn store_load_scratch(store: &Store, id: usize) -> Result<String, String>;
        fn snapshot_new(dir: String) -> Snapshot;
        fn snapshot_create_next(snapshot: &Snapshot) -> Result<usize, String>;
        fn snapshot_write(snapshot: &Snapshot, seq: usize, content: String) -> Result<(), String>;
        fn snapshot_read(snapshot: &Snapshot, seq: usize) -> Result<String, String>;

        type BufferId;
        type DocumentManager;
        type Editor;
        type Snapshot;
        type Store;
        #[swift_bridge(init)]
        fn new(id: u64) -> BufferId;
        fn as_u64(self: &BufferId) -> u64;

        type Buffer;
        #[swift_bridge(init)]
        fn new(id: BufferId) -> Buffer;
        fn id(self: &Buffer) -> BufferId;
        fn len(self: &Buffer) -> usize;
        fn is_empty(self: &Buffer) -> bool;
        fn text(self: &Buffer) -> &str;
    }
}
