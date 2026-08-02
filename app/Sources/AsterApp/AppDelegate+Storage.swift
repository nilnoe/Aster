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
  /// 随 T-029 会话完整恢复。
  func presentRecoveryIfNeeded() {
    guard needsRecoveryPrompt, let store = bufferStore else { return }
    let ids = store_scratch_ids(store)
    guard let latest = ids.max() else { return }
    let alert = NSAlert()
    alert.messageText = "检测到异常退出"
    alert.informativeText =
      "上次会话未正常退出，发现 \(ids.count) 个未提交文档。要恢复最近的一个吗？"
      + "（未恢复的内容仍保留在缓冲中）"
    alert.addButton(withTitle: "恢复")
    alert.addButton(withTitle: "忽略")
    guard alert.runModal() == .alertFirstButtonReturn else { return }
    do {
      let text = try store_load_scratch(store, latest).toString()
      let id = try document_manager_open_scratch(documentManager)
      let buffer = Buffer(BufferId(UInt64(id)))
      _ = try buffer_insert(buffer, 0, text)
      let model = makeModel(buffer)
      if let view = mainWindow?.contentView as? MetalView {
        view.load(model)
      }
      currentSnapshotSeq = UInt(try snapshot_create_next(snapshot))
      currentFileName = nil
      isDirty = true
      updateWindowTitle()
      // T-045（ADR-013 v1.3）：被恢复内容已载入新文档（新 id 接管自动保存），
      // 删除被恢复的旧缓冲行，避免已处置内容继续滞留。
      _ = try? store_delete_scratch(store, latest)
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
    guard let view = mainWindow?.contentView as? MetalView,
      let seq = currentSnapshotSeq
    else {
      presentSaveError("当前没有快照可合并")
      return false
    }
    do {
      // Cmd+S = 合并：缓冲文本覆盖写进当前快照（提交 / 固化，ADR-023 v1.4）。
      try snapshot_write(snapshot, seq, view.model.bufferText)
      // T-045：合并成功 = 内容已固化到快照，缓冲副本冗余 → 删该文档行；失败只
      // 遗留冗余行（幂等无害），不阻塞保存结果。
      if let buffer = bufferStore {
        _ = try? store_delete_scratch(buffer, UInt(view.model.bufferIdValue))
      }
      isDirty = false
      updateWindowTitle()
      return true
    } catch {
      NSLog("保存文档失败：\(error)")
      presentSaveError("\(error)")
      return false
    }
  }

  /// 内容变更：置脏 + 更新标题 + 自动写缓冲（ADR-023 v1.3）。
  ///
  /// 决策依据：EditorModel.onChange 在 makeModel 统一接线（修复启动默认 Buffer
  /// 未接线导致无 dirty / 退出保护失效的 bug）；缓冲写失败不阻塞编辑（日志可见，
  /// ADR-004 精神：失败不静默，但不打断输入流）。
  func onContentChanged() {
    isDirty = true
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

  /// 丢弃当前文档缓冲行（退出提示「不保存」时调用；T-045，ADR-013 v1.3）。
  ///
  /// 决策依据：删除失败只遗留冗余行（幂等、无害），不阻塞退出（ADR-004 精神）。
  func discardCurrentBufferRow() {
    guard let store = bufferStore,
      let view = mainWindow?.contentView as? MetalView
    else { return }
    _ = try? store_delete_scratch(store, UInt(view.model.bufferIdValue))
  }
}
