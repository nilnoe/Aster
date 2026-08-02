//! 输入状态机（T-012，ADR-016）。
//!
//! 决策依据：
//! - 可测逻辑放模型层（docs/testing.md）：Buffer 读写经 Bridge，IME 组合文本存于此，
//!   View 层只做事件采集与绘制（薄 UI）。
//! - spike 语义：插入点恒为文本末尾（字节偏移，与 Core 一致，ADR-005）；光标 / 选区 /
//!   替换区间状态机属 T-013 编辑循环（ADR-016 备注）。
//! - 提交走 `buffer_insert` 写回 Core——UI 不直接持有文本，Buffer 是第一公民（ADR 总纲）。

import AsterBridge

@MainActor
final class EditorModel {
  private let buffer: Buffer
  private(set) var insertionOffset: UInt
  private(set) var composition = ""

  init(buffer: Buffer) {
    self.buffer = buffer
    self.insertionOffset = buffer.len()
  }

  var hasMarkedText: Bool { !composition.isEmpty }

  var bufferText: String { buffer.text().toString() }

  /// 渲染文本 = Buffer 文本 + 组合文本（IME 未提交内容追加在末尾）。
  var displayText: String { bufferText + composition }

  /// 按 Core Layout（ADR-009）的行起点切分 Buffer 文本，供渲染逐行 shaping。
  ///
  /// 决策依据：行结构复用 Core（Rule 11，ADR-016）；UTF-8 字节偏移经
  /// `String.UTF8View.index` 换算为 `String.Index`，与 Buffer 字节语义一致（ADR-005）。
  var lines: [String] {
    let starts = layout_line_starts(bufferText)
    var result: [String] = []
    for i in starts.indices {
      let start = Int(starts[i])
      let end = i + 1 < starts.count ? Int(starts[i + 1]) - 1 : bufferText.utf8.count
      let from = bufferText.utf8.index(bufferText.utf8.startIndex, offsetBy: start)
      let to = bufferText.utf8.index(bufferText.utf8.startIndex, offsetBy: end)
      result.append(String(bufferText[from..<to]))
    }
    return result
  }

  /// 追加文本到插入点（spike：末尾）；返回新的文本长度（字节）。
  func insertText(_ text: String) throws {
    insertionOffset = try buffer_insert(buffer, insertionOffset, text)
  }

  func setMarkedText(_ text: String) {
    composition = text
  }

  func unmarkText() {
    composition = ""
  }

  /// 提交组合文本：写入 Buffer 并清空组合态（IME 提交闭环，ADR-016）。
  func commitComposition() throws {
    guard !composition.isEmpty else { return }
    try insertText(composition)
    composition = ""
  }
}
