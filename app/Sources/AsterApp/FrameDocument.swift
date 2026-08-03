//! Frame 级文档关联（T-074，ADR-025 frame 域收拢；App 层）。
//!
//! 决策依据：frame ↔ 文档的关联此前散在 AppDelegate.frames / frameFileName
//! 字典 / view.model.bufferIdValue（I-013），标题 / 保存 / 关闭决策 / 窗口
//! 关闭 / 内容变更 5+ 处各自推导；收拢为单一结构——不变量 = 每个打开的 frame
//! 恰好一条登记（makeFrame / ⌘N / ⌘O / 恢复更新，windowWillClose 移除），由
//! AppDelegate.setFrameDocument 与 windowWillClose 方法保证（Rule 17 / 18）。

import AppKit

/// 一个 frame（广义窗口）与其当前文档的关联。
struct FrameDocument {
  let window: NSWindow
  let documentId: UInt
  var fileName: String?
}
