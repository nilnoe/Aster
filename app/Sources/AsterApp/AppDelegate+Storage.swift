//! AppDelegate 存储 / 保存 / 恢复扩展（T-045 拆分，Rule 3；T-070 起全经 Session）。
//!
//! 决策依据：
//! - 与 MetalView + MetalView+Input 同一拆分模式（T-018）：壳（生命周期 / 窗口 /
//!   菜单动作）留在 AppDelegate.swift，本文件只承载存储 / 保存 / 崩溃恢复接线。
//! - T-070（ADR-025）：文档生命周期状态与持久化编排全部收拢进 Core `Session`，
//!   本扩展只剩薄胶水（session FFI 调用 + 失败提示），不再持有任何账本——
//!   旧三张平行账本 + 全局失败布尔是 BUG-010~018 的温床。

import AppKit
import AsterBridge

@MainActor
extension AppDelegate {
  /// 桥接错误 → 可读文本（RustString 需 toString 渲染内容，ADR-014 惯例；
  /// 旧代码 `"\(error)"` 插值不显示消息体）。
  func errorText(_ error: Error) -> String {
    (error as? RustString)?.toString() ?? "\(error)"
  }

  /// 启动存储：打开会话（缓冲 + 快照 + 注册表），读哨兵并清哨兵，决定是否提示恢复。
  ///
  /// 决策依据（T-054，BUG-015）：存储初始化失败必须启动即提示（ADR-004），
  /// 但不阻止启动（可继续编辑，保存时再报「存储未就绪」）。
  func setupStorage() {
    let session = session_new(StorePaths.defaultDirectory())
    self.session = session
    let storeError = session_store_error(session).toString()
    guard storeError.isEmpty else {
      presentSaveError("存储初始化失败：\(storeError)。编辑内容将无法自动保存与崩溃恢复，且退出时无法保存。")
      return
    }
    do {
      // T-043：先读哨兵（上次是否异常退出），随即清哨兵（本次运行期间的崩溃
      // 检测基准）；再枚举缓冲文档决定是否提示恢复。
      let cleanExit = try session_is_clean_exit(session)
      try session_set_clean_exit(session, false)
      needsRecoveryPrompt = Self.shouldOfferRecovery(
        cleanExit: cleanExit,
        bufferedDocCount: session_buffered_ids(session).count
      )
    } catch {
      NSLog("存储初始化失败：\(error)")
      presentSaveError("存储初始化失败：\(error)。编辑内容将无法自动保存与崩溃恢复，且退出时无法保存。")
    }
  }

  /// 崩溃恢复提示（T-043，ADR-013 v1.1 / v1.3）：恢复最近一个缓冲文档，
  /// 忽略则全部登记为未决（内容守恒，ADR-013 v1.4 保留规则 3 / 4）。
  ///
  /// 决策依据：缓冲是崩溃保护的连续工作副本（ADR-023 v1.4）；恢复 = 载入最新
  /// 内容并置脏（用户经 Cmd+S 合并进新快照）并删除被恢复的旧行；其余缓冲文档
  /// 逐个登记未决（BUG-011 / BUG-016 泛化——不因忽略 / 只呈现最新而失管）。
  func presentRecoveryIfNeeded() {
    guard needsRecoveryPrompt, let session else { return }
    let ids = session_buffered_ids(session).map { UInt($0) }
    guard let latest = ids.max() else { return }
    let restore = presentRecoveryAlert(count: ids.count) == 1
    do {
      if restore {
        // 恢复：内容载入新文档（新 id 接管自动保存），删除被恢复的旧行。
        let text = try session_load_buffered(session, latest).toString()
        // BUG-023（T-070 暴露，双缺陷）：
        // ① id 碰撞——DM id 每进程从 1 重新分配，旧实现「typeText 写缓冲后再
        //    删 latest」会把刚写入的新行删掉（Session::open 已推进 id 游标，
        //    见 session.rs）；② 残留状态——真实路径播种的遗留行在会话内有
        //    state，恢复后行被删但未决标记残留，违反「未决 ⟺ 缓冲行」。discard
        //    先删行再清 state：跨进程遗留行（无 state）报 UnknownDoc 被容忍。
        _ = try? session_discard(session, latest)
        guard let frame = currentFrame else { return }
        let model = try makeScratchModel(in: frame)
        if let view = frame.contentView as? MetalView {
          view.load(model)
        }
        frameFileName[frame] = nil
        // 恢复内容 = 光标处输入（按 frame 的 onChange 接线：typeText 触发置脏 +
        // 自动写缓冲——BUG-011 保证「恢复内容必进缓冲」，可被 ⌘S 读取）。
        try model.typeText(text)
        // 其余未决缓冲文档登记（register_buffered 保留已登记序号）。
        for other in ids where other != latest {
          _ = try session_register_buffered(session, other)
        }
      } else {
        // 忽略：**全部**缓冲文档登记为未决（ADR-013 v1.4：不留「没被问过」
        // 的文档——旧实现只登记 latest，BUG-016）。
        for other in ids {
          _ = try session_register_buffered(session, other)
        }
      }
    } catch {
      NSLog("恢复文档失败：\(error)")
      presentSaveError(errorText(error))
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
    guard let frame = currentFrame, let view = frame.contentView as? MetalView else {
      presentSaveError("没有可保存的视图")
      return false
    }
    let id = UInt(view.model.bufferIdValue)
    // 无未提交更改时 ⌘S 是空操作（不报错）。
    guard let session, session_is_pending(session, id) else { return true }
    return mergePendingDoc(id)
  }

  /// 合并单个未决文档：缓冲内容 → 其快照（提交 / 固化）。
  ///
  /// 错误提示由 Session 的稳定消息提供（存储未就绪 / 没有可合并的快照 /
  /// 缓冲行缺失，T-054 错误分类；ADR-004 失败可见）。
  @discardableResult
  func mergePendingDoc(_ id: UInt) -> Bool {
    guard let session else {
      presentSaveError("存储未就绪，无法保存（存储初始化失败）")
      return false
    }
    do {
      try session_save(session, id)
      refreshFrameTitles()
      return true
    } catch {
      NSLog("保存文档 \(id) 失败：\(error)")
      presentSaveError(errorText(error))
      return false
    }
  }

  /// 退出「保存全部」：遍历所有未决文档逐个合并；任一失败即中止（ADR-004）。
  @discardableResult
  func saveAllPending() -> Bool {
    guard let session else { return true }
    guard !session_pending_ids(session).isEmpty else { return true }
    do {
      try session_save_all(session)
      refreshFrameTitles()
      return true
    } catch {
      NSLog("保存全部失败：\(error)")
      presentSaveError(errorText(error))
      return false
    }
  }

  /// 丢弃单个文档（窗口关闭「不保存」，T-070 per-frame 语义）。
  @discardableResult
  func discardPendingDoc(_ id: UInt) -> Bool {
    guard let session else { return false }
    do {
      try session_discard(session, id)
      refreshFrameTitles()
      return true
    } catch {
      NSLog("丢弃文档 \(id) 失败：\(error)")
      presentSaveError(errorText(error))
      return false
    }
  }

  /// 退出「全部不保存」：丢弃所有未决文档的缓冲行并清空登记。
  func discardAllPending() {
    guard let session else { return }
    do {
      try session_discard_all(session)
      refreshFrameTitles()
    } catch {
      NSLog("丢弃全部失败：\(error)")
      presentSaveError(errorText(error))
    }
  }

  /// 内容变更（按 frame，T-069）：置脏 + 更新该 frame 标题 + 自动写缓冲。
  ///
  /// 决策依据：EditorModel.onChange 在 makeModel 统一接线（T-041）；未决 /
  /// 缓冲 / 失败提示状态全部由 Session 维护（T-070，ADR-025）——本方法只转发
  /// 并呈现失败；Session 按**文档**只提示一次（T-054 防逐键弹窗，T-070 修正
  /// 旧全局布尔跨文档吞提示）。
  func onContentChanged(in frame: NSWindow) {
    guard let view = frame.contentView as? MetalView, let session else { return }
    let id = UInt(view.model.bufferIdValue)
    do {
      try session_content_changed(session, id, view.model.bufferText)
    } catch {
      NSLog("缓冲自动保存失败：\(error)")
      presentSaveError("自动保存失败：\(errorText(error))。当前编辑内容只存在于内存，崩溃或意外退出将丢失。")
    }
    updateWindowTitle(frame)
  }
}
