//! AppDelegate 菜单动作 / 打开 / 标题扩展（T-065 拆分，Rule 3：AppDelegate 308
//! 行超限——T-045 同款模式）。决策依据：弹窗 seam（presentPendingDocsAlert /
//! presentRecoveryAlert / presentSaveError）因测试子类覆写**必须留在类体**
//! （跨模块覆写要求类体方法，Swift 语言约束），故把可移至扩展的动作组拆出。

import AppKit
import AsterBridge

@MainActor
extension AppDelegate {
  @objc func showAbout(_ sender: Any?) {
    NSApp.orderFrontStandardAboutPanel(options: [
      .applicationName: AppInfo.name,
      .applicationVersion: AppInfo.version,
    ])
  }

  /// File 菜单「新建」（⌘N）：创建当日下一个快照文件 + 新的空白 Scratch 文档。
  ///
  /// 决策依据（T-041，ADR-001 v1.2 / ADR-023 v1.3）：新文档 = 新快照（日期+序号），
  /// 缓冲内容按 id 隔离自动保存；旧文档未提交编辑仍在缓冲（崩溃保护），合并由
  /// 用户回到对应会话时执行（激活文档随 T-024 统一）。
  @objc func newDocument(_ sender: Any?) {
    guard let frame = currentFrame else { return }
    do {
      let model = try makeScratchModel(in: frame)
      if let view = frame.contentView as? MetalView {
        view.load(model)
      }
      setFrameDocument(frame, documentId: UInt(model.bufferIdValue), fileName: nil)
      updateWindowTitle(frame)
    } catch {
      NSLog("新建文档失败：\(error)")
      presentSaveError(errorText(error))
    }
  }

  /// File 菜单「打开…」：NSOpenPanel 选文件（系统能力，Principle 4）。
  @objc func openDocument(_ sender: Any?) {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = false
    panel.begin { [weak self] response in
      guard response == .OK, let url = panel.url else { return }
      self?.open(url)
    }
  }

  /// 打开文件：Session Disk 源读入 → 编辑会话句柄 → 替换当前内容
  /// （T-015，ADR-001；T-075，ADR-027：App 不再构造 Buffer）。
  func open(_ url: URL) {
    guard let frame = currentFrame, let session else { return }
    do {
      let id = UInt(try session_open_disk(session, url.path))
      let editor = try session_editor(session, id)
      let model = makeModel(editor, bufferId: id, in: frame)
      if let view = frame.contentView as? MetalView {
        view.load(model)
      }
      setFrameDocument(
        frame, documentId: UInt(model.bufferIdValue), fileName: url.lastPathComponent)
      updateWindowTitle(frame)
    } catch {
      NSLog("打开文档失败：\(error)")
      presentOpenError(errorText(error))
    }
  }

  /// 统一创建 EditorModel 并接线内容变更回调（onChange → onContentChanged，
  /// 按 frame 接线，T-069）。
  ///
  /// 决策依据（T-041）：启动默认文档与打开的文件都走同一接线，杜绝此前
  /// 只在 open() 接线导致的「默认文档无 dirty / 无退出保护」；T-069 多 Frame
  /// 下弱捕获 frame，编辑各自文档状态互不污染，且避免 frame→view→model→
  /// closure→frame 循环保留。
  func makeModel(_ editor: Editor, bufferId: UInt, in frame: NSWindow) -> EditorModel {
    let model = EditorModel(editor: editor, bufferId: UInt64(bufferId))
    model.onChange = { [weak self, weak frame] in
      guard let frame else { return }
      self?.onContentChanged(in: frame)
    }
    return model
  }

  /// 标题 = 该 frame 的文件名（Scratch 显示 App 名）；未保存指示用系统原生
  /// `isDocumentEdited`（关闭按钮红点，T-067）。T-069 起按 frame 刷新——
  /// 每个 frame 反映自己的文档状态。
  ///
  /// 决策依据（T-067）：旧实现手拼「● 」前缀进标题文本；macOS 文档编辑状态的
  /// 平台约定是 `NSWindow.isDocumentEdited`——AppKit 自动在左上角关闭按钮内
  /// 画 dirty 点（TextEdit / Pages 同款），与总纲 Principle 4（不 fight 系统）
  /// 和宪法 Rule 11（系统能力优先）一致，并删除自研前缀渲染。
  func updateWindowTitle(_ frame: NSWindow) {
    let base = frameFileName(frame) ?? AppInfo.name
    let currentDirty =
      frameDocumentId(for: frame)
      .map { id -> Bool in
        // T-065：脏态 = 已冲刷未决 ∨ 防抖窗口内待冲刷（标题立即反映编辑，
        // 不等 200ms 定时器；两个来源只在此处合并为视图状态，不另建账本）。
        (session.map { session_is_pending($0, id) } ?? false)
          || autosaveDirtyIds.contains(id)
      } ?? false
    frame.title = base
    frame.isDocumentEdited = currentDirty
  }

  /// 刷新全部 frame 标题（保存全部 / 丢弃后，各 frame 反映各自文档状态，T-069）。
  func refreshFrameTitles() {
    for frameDoc in frameDocs {
      updateWindowTitle(frameDoc.window)
    }
  }

  /// 打开失败必须可见（ADR-004），不静默回退到空文档。
  func presentOpenError(_ message: String) {
    let alert = NSAlert()
    alert.messageText = "无法打开文档"
    alert.informativeText = message
    alert.alertStyle = .warning
    alert.runModal()
  }
}
