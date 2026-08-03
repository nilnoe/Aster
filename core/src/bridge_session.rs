//! Session 桥接适配（T-070 拆分，Rule 3：bridge.rs 超 300 行——T-045 同款模式）。
//!
//! 决策依据：
//! - 文档生命周期状态收拢为 Core Session 单一入口，App 不再持有任何账本
//!   （ADR-025；取代 document_manager_* / store_* / snapshot_* FFI——旧面无
//!   生产消费者，Rule 14）。
//! - id 以 usize 透传（ADR-014 惯例：swift-bridge 0.1.59 对 Result<u64, _>
//!   的 C 结构命名未实现，实测 todo!() 崩溃）。
//! - 错误映射为消息字符串（ADR-014 惯例）；`session_err` 保持关键短语稳定
//!   （「存储未就绪」「文档没有可合并的快照」「not found」被 App 测试断言）。

use crate::editor::Editor;
use crate::session::Session;
use crate::session_error::SessionError;

/// 错误映射：稳定关键短语（T-054 / T-070 测试契约，勿随意改文案）。
fn session_err(e: SessionError) -> String {
    match e {
        SessionError::StoreNotReady => "存储未就绪，无法保存（存储初始化失败）".to_string(),
        SessionError::NoSnapshot(_) => "文档没有可合并的快照".to_string(),
        SessionError::MissingBuffer(id) => format!("scratch {id} not found"),
        SessionError::UnknownDoc(id) => format!("未知文档 id={id}"),
        SessionError::DocumentManager(e) => format!("{e:?}"),
        SessionError::Store(e) => format!("{e:?}"),
        SessionError::Io(e) => format!("{e:?}"),
    }
}

/// 打开（或创建）会话：缓冲 + 快照 + 注册表（存储故障不阻止，错误见
/// `session_store_error`，ADR-004 启动即提示）。
pub fn session_new(dir: String) -> Session {
    Session::open(std::path::Path::new(&dir))
}

/// 启动时缓冲打开失败的消息（空串 = 存储就绪）。
pub fn session_store_error(session: &Session) -> String {
    session.store_error().unwrap_or("").to_string()
}

/// 干净退出哨兵（ADR-013 v1.1）。
pub fn session_is_clean_exit(session: &Session) -> Result<bool, String> {
    session.is_clean_exit().map_err(session_err)
}

/// 设置干净退出哨兵（正常退出 true / 启动清 false）。
pub fn session_set_clean_exit(session: &mut Session, clean: bool) -> Result<(), String> {
    session.set_clean_exit(clean).map_err(session_err)
}

/// 缓冲文档 id 列表（崩溃恢复枚举；最新 = 最大 id）。
pub fn session_buffered_ids(session: &Session) -> Vec<usize> {
    session
        .buffered_ids()
        .into_iter()
        .map(|id| id as usize)
        .collect()
}

/// Cmd+N / 新 Frame / 恢复：注册 Scratch 文档并分配快照序号；`seed` 为启动
/// 样例文本（Core 注入共享缓冲，不进历史 / 不置脏，ADR-027）。
pub fn session_open_scratch(session: &mut Session, seed: String) -> Result<usize, String> {
    session
        .open_scratch(&seed)
        .map(|id| id as usize)
        .map_err(session_err)
}

/// 打开磁盘文件并登记（ADR-001 Disk 源）；失败可见（ADR-004）。
pub fn session_open_disk(session: &mut Session, path: String) -> Result<usize, String> {
    session
        .open_disk(&path)
        .map(|id| id as usize)
        .map_err(session_err)
}

/// 按 id 取注册文本（App 建 Editor 会话）；未知 id 显式报错。
pub fn session_text(session: &Session, id: usize) -> Result<String, String> {
    session.text(id as u64).map_err(session_err)
}

/// 取文档编辑会话句柄（ADR-027）：与注册表共享 Buffer——编辑即注册表内容。
pub fn session_editor(session: &Session, id: usize) -> Result<Editor, String> {
    session.editor(id as u64).map_err(session_err)
}

/// 内容变更（onChange 唯一入口）：未决标记 + 缓冲自动保存（ADR-023 v1.3）；
/// 内容直接读注册表活文（ADR-027：App 不再推全文过 Bridge）。
pub fn session_content_changed(session: &mut Session, id: usize) -> Result<(), String> {
    session.content_changed(id as u64).map_err(session_err)
}

/// Cmd+S：合并缓冲内容 → 当前快照（提交 / 固化）。
pub fn session_save(session: &mut Session, id: usize) -> Result<(), String> {
    session.save(id as u64).map_err(session_err)
}

/// 退出「保存全部」：逐个合并，任一失败即中止。
pub fn session_save_all(session: &mut Session) -> Result<(), String> {
    session.save_all().map_err(session_err)
}

/// 丢弃单个文档（窗口关闭「不保存」）。
pub fn session_discard(session: &mut Session, id: usize) -> Result<(), String> {
    session.discard(id as u64).map_err(session_err)
}

/// 退出「全部不保存」。
pub fn session_discard_all(session: &mut Session) -> Result<(), String> {
    session.discard_all().map_err(session_err)
}

/// 未决文档 id 列表（退出提示 / 标题 dirty / 审计）。
pub fn session_pending_ids(session: &Session) -> Vec<usize> {
    session
        .pending_ids()
        .into_iter()
        .map(|id| id as usize)
        .collect()
}

/// 未决判定（标题 dirty / 关闭拦截 / ⌘S 空操作）。
pub fn session_is_pending(session: &Session, id: usize) -> bool {
    session.is_pending(id as u64)
}

/// 快照序号查询（测试 / 审计断言）。
pub fn session_snapshot_seq(session: &Session, id: usize) -> Result<usize, String> {
    session
        .snapshot_seq(id as u64)
        .map(|seq| seq as usize)
        .map_err(session_err)
}

/// 读取缓冲内容（崩溃恢复载入）。
pub fn session_load_buffered(session: &Session, id: usize) -> Result<String, String> {
    session.load_buffered(id as u64).map_err(session_err)
}

/// 删除缓冲行（恢复载入后清理旧行，ADR-013 v1.3 删除时机 2）。
pub fn session_delete_buffered(session: &mut Session, id: usize) -> Result<bool, String> {
    session.delete_buffered(id as u64).map_err(session_err)
}

/// 崩溃遗留行登记：分配序号（已登记保留原序号）+ 置未决（BUG-011 / 016）。
pub fn session_register_buffered(session: &mut Session, id: usize) -> Result<usize, String> {
    session
        .register_buffered(id as u64)
        .map(|seq| seq as usize)
        .map_err(session_err)
}

/// 干净退出清理空快照（T-047，ADR-023 v1.6）。
pub fn session_prune_empty(session: &Session) -> Result<usize, String> {
    session.prune_empty().map_err(session_err)
}

/// 关闭文档（窗口关闭后）：注册表移除（ADR-001 生命周期）。
pub fn session_close_document(session: &mut Session, id: usize) -> Result<(), String> {
    session.close_document(id as u64).map_err(session_err)
}
