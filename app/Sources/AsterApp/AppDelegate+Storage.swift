//! AppDelegate 存储 / 保存 / 恢复扩展（T-045 拆分，Rule 3：AppDelegate 334 行超限）。
//!
//! 决策依据：
//! - 与 MetalView + MetalView+Input 同一拆分模式（T-018）：壳（生命周期 / 窗口 /
//!   菜单动作）留在 AppDelegate.swift，本文件只承载存储 / 保存 / 崩溃恢复逻辑。
//! - 跨文件访问的成员从 private 提升为 internal（App 模块内封装，Rule 4 / 12 在
//!   模块边界内成立；T-018 先例）。
//! - 缓冲生命周期（ADR-013 v1.3）：合并 / 恢复 / 明确丢弃后删除缓冲行；
//!   未决内容保留（崩溃保护）。

import AppKit
import AsterBridge

@MainActor
extension AppDelegate {
  /// 启动存储：打开缓冲文件 + 创建当日第一个快照（隐式新文档）。
  ///
  /// 决策依据（ADR-023 v1.3）：缓冲连接保持整个会话；快照序号供 Cmd+S 合并。
  /// 初始化失败必须可见（ADR-004），但不阻止启动（可继续编辑，保存时再报）。
  func setupStorage() {
    do {
      let dir = StorePaths.defaultDirectory()
      let store = try store_open_buffer(dir)
      bufferStore = store
      currentSnapshotSeq = UInt(try snapshot_create_next(snapshot))
      // T-043：先读哨兵（上次是否异常退出），随即清哨兵（本次运行期间的崩溃
      // 检测基准）；再枚举缓冲文档决定是否提示恢复。
      let cleanExit = try store_is_clean_exit(store)
      try store_set_clean_exit(store, false)
      needsRecoveryPrompt = Self.shouldOfferRecovery(
        cleanExit: cleanExit,
        bufferedDocCount: store_scratch_ids(store).count
      )
    } catch {
      NSLog("存储初始化失败：\(error)")
    }
  }

  /// 崩溃恢复提示（T-043，ADR-013 v1.1 / v1.3）：恢复最近一个缓冲文档，
  /// 忽略则保留在缓冲（未决内容守恒，ADR-013 v1.3 保留规则 3）。
  ///
  /// 决策依据：缓冲是崩溃保护的连续工作副本（ADR-023 v1.4）；恢复 = 载入最新
  /// 内容并置脏（用户经 Cmd+S 合并进新快照）并删除被恢复的旧行；其余缓冲文档
  /// 随 T-029 会话完整恢复。「忽略」= 保留内容并登记为未决文档（退出时可一并
  /// 保存或丢弃，ADR-013 v1.4：不因切换 / 忽略而失管）。
  func presentRecoveryIfNeeded() {
    guard needsRecoveryPrompt, let store = bufferStore else { return }
    let ids = store_scratch_ids(store)
    guard let latest = ids.max() else { return }
    let alert = NSAlert()
    alert.messageText = "检测到异常退出"
    alert.informativeText =
      "上次会话未正常退出，发现 \(ids.count) 个未提交文档。要恢复最近的一个吗？"
      + "（未恢复的内容会登记为未决文档，退出时可一并保存或丢弃）"
    alert.addButton(withTitle: "恢复")
    alert.addButton(withTitle: "忽略")
    let restore = alert.runModal() == .alertFirstButtonReturn
    do {
      if restore {
        // 恢复：内容载入新文档（新 id 接管自动保存），删除被恢复的旧行。
        let text = try store_load_scratch(store, latest).toString()
        let id = try document_manager_open_scratch(documentManager)
        let buffer = Buffer(BufferId(UInt64(id)))
        _ = try buffer_insert(buffer, 0, text)
        let model = makeModel(buffer)
        if let view = mainWindow?.contentView as? MetalView {
          view.load(model)
        }
        currentSnapshotSeq = UInt(try snapshot_create_next(snapshot))
        snapshotSeqByDocId[id] = currentSnapshotSeq
        currentFileName = nil
        pendingDocs.mark(id)
        updateWindowTitle()
        _ = try? store_delete_scratch(store, latest)
      } else {
        // 忽略：内容保留在缓冲，登记为未决文档并分配快照序号（退出可合并）。
        snapshotSeqByDocId[latest] = UInt(try snapshot_create_next(snapshot))
        pendingDocs.mark(latest)
      }
    } catch {
      NSLog("恢复文档失败：\(error)")
      presentSaveError("\(error)")
    }
  }

  /// 保存当前文档（⌘S / 退出保护共用）：成功返回 true。
  ///
  /// 决策依据（T-041，ADR-023 v1.3）：Cmd+S = 把缓冲内容合并进当前快照（提交 /
  /// 固化），不是新建文件；合并成功后删除缓冲行（ADR-013 v1.3）并清除 dirty。
  @objc func saveDocument(_ sender: Any?) {
    _ = saveCurrentDocument()
  }

  @discardableResult
  func saveCurrentDocument() -> Bool {
    guard let view = mainWindow?.contentView as? MetalView else {
      presentSaveError("没有可保存的视图")
      return false
    }
    let id = UInt(view.model.bufferIdValue)
    // 无未提交更改时 ⌘S 是空操作（不报错）。
    guard pendingDocs.contains(id) else { return true }
    return mergePendingDoc(id)
  }

  /// 合并单个未决文档：缓冲内容 → 其快照，成功后删除缓冲行并移除未决标记。
  ///
  /// 决策依据（T-046，ADR-013 v1.4）：缓冲行是未决内容的唯一持久来源（当前
  /// 视图只显示一个文档，其余文档的内容只在缓冲里）；合并 = 提交 / 固化。
  @discardableResult
  private func mergePendingDoc(_ id: UInt) -> Bool {
    guard let store = bufferStore, let seq = snapshotSeqByDocId[id] else {
      presentSaveError("文档没有可合并的快照")
      return false
    }
    do {
      let text = try store_load_scratch(store, id).toString()
      try snapshot_write(snapshot, seq, text)
      _ = try? store_delete_scratch(store, id)
      pendingDocs.commit(id)
      updateWindowTitle()
      return true
    } catch {
      NSLog("保存文档 \(id) 失败：\(error)")
      presentSaveError("\(error)")
      return false
    }
  }

  /// 退出「保存全部」：遍历所有未决文档逐个合并；任一失败即中止（ADR-004）。
  @discardableResult
  func saveAllPending() -> Bool {
    guard !pendingDocs.isEmpty else { return true }
    for id in pendingDocs.ids.sorted() {
      if !mergePendingDoc(id) { return false }
    }
    return true
  }

  /// 退出「全部不保存」：丢弃所有未决文档的缓冲行并清空登记。
  func discardAllPending() {
    guard let store = bufferStore else { return }
    for id in pendingDocs.ids {
      _ = try? store_delete_scratch(store, id)
    }
    pendingDocs.discardAll()
    updateWindowTitle()
  }

  /// 内容变更：置脏 + 更新标题 + 自动写缓冲（ADR-023 v1.3）。
  ///
  /// 决策依据：EditorModel.onChange 在 makeModel 统一接线（修复启动默认 Buffer
  /// 未接线导致无 dirty / 退出保护失效的 bug）；缓冲写失败不阻塞编辑（日志可见，
  /// ADR-004 精神：失败不静默，但不打断输入流）。
  func onContentChanged() {
    guard let view = mainWindow?.contentView as? MetalView else { return }
    pendingDocs.mark(UInt(view.model.bufferIdValue))
    updateWindowTitle()
    autoSaveToBuffer()
  }

  /// 自动保存：当前编辑内容写入缓冲文件（崩溃保护）。
  func autoSaveToBuffer() {
    guard let store = bufferStore,
      let view = mainWindow?.contentView as? MetalView
    else { return }
    do {
      try store_save_scratch(store, UInt(view.model.bufferIdValue), view.model.bufferText)
    } catch {
      NSLog("缓冲自动保存失败：\(error)")
    }
  }

}
