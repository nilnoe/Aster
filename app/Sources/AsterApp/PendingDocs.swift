//! 多文档未提交状态登记（T-046，ADR-013 v1.4）。
//!
//! 决策依据：
//! - 进程生命周期内**所有**文档的未提交状态都要检查：打开另一个文件不得抛弃
//!   前一个文件，退出提示覆盖全部未决文档（用户指示 2026-08-02）。
//! - 纯值类型、可单测（docs/testing.md：抽出的逻辑）；不依赖视图 / 存储。
//! - 与 Core `Selection` 同类：把「一组布尔状态」收拢为一个小型值类型，
//!   避免 AppDelegate 里散落的 Set 操作（Rule 9：状态语义集中一处）。

/// 未提交文档 id 集合（以 BufferId 为键，App 模块内）。
struct PendingDocs {
  private(set) var ids: Set<UInt> = []

  var isEmpty: Bool { ids.isEmpty }
  var count: Int { ids.count }

  /// 内容变更 → 置为未提交（onChange）。
  mutating func mark(_ id: UInt) {
    ids.insert(id)
  }

  /// 合并成功（⌘S）→ 移除（内容已固化到快照）。
  mutating func commit(_ id: UInt) {
    ids.remove(id)
  }

  /// 明确丢弃（退出「不保存」）→ 移除。
  mutating func discard(_ id: UInt) {
    ids.remove(id)
  }

  /// 退出「全部不保存」→ 清空。
  mutating func discardAll() {
    ids.removeAll()
  }

  func contains(_ id: UInt) -> Bool {
    ids.contains(id)
  }
}
