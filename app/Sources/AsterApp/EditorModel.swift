//! 编辑状态机（T-013，ADR-017）。
//!
//! 决策依据：
//! - 编辑语义全部落在 Core `Editor`（ADR-017），本类只做桥接适配与渲染视图准备：
//!   显示文本（组合文本内联在光标处）、行切分（复用 Core Layout，ADR-009）、
//!   UTF-16 ↔ UTF-8 换算（IME 区间是 UTF-16 语义，Core 是字节，ADR-017 备注）。
//! - IME 组合文本不再作为独立尾行：插入 displayText 光标处，标记区间由渲染层
//!   画下划线；提交 = 在光标处输入（组合区间不在 Buffer 里，无需替换）。
//! - 光标移动 / 退格 / 撤销等全部经 Bridge 进 Core，UI 不做编辑决策（薄 UI）。
//! - T-038（I-003）：显示文本与行结构按编辑失效缓存——渲染帧不再做全文切分 /
//!   Bridge 全串往返（原每帧 O(n)），行结构只随内容 / 组合变化重建一次。

import AsterBridge
import Foundation

@MainActor
final class EditorModel {
  /// 移动方向（与 Core Movement 一一对应，8 个桥接函数适配）。
  enum Movement {
    case left, right, up, down, lineStart, lineEnd, docStart, docEnd
  }

  private let editor: Editor
  private(set) var composition = ""
  /// 显示文本缓存（T-038）：内容或组合变化时失效；渲染帧内多次读取零成本。
  private var displayTextCache: String?
  /// 行字节区间缓存（T-038）：由 displayText 派生，同一次失效周期只建一次。
  private var lineRangesCache: [Range<Int>]?

  init(buffer: Buffer) {
    self.editor = editor_new(buffer)
  }

  // MARK: - 渲染状态

  var bufferText: String { editor_text(editor).toString() }

  /// 光标（Buffer 字节偏移）。
  var cursorByte: Int { Int(editor_selection_head(editor)) }

  var selectionStartByte: Int { Int(editor_selection_start(editor)) }

  var selectionEndByte: Int { Int(editor_selection_end(editor)) }

  var hasMarkedText: Bool { !composition.isEmpty }

  /// 显示文本 = Buffer 文本 + 光标处内联的组合文本（ADR-017 内联组合模型）。
  var displayText: String {
    if let cached = displayTextCache { return cached }
    let text =
      composition.isEmpty
      ? bufferText
      : {
        let idx = bufferText.utf8.index(bufferText.utf8.startIndex, offsetBy: cursorByte)
        return String(bufferText[..<idx]) + composition + String(bufferText[idx...])
      }()
    displayTextCache = text
    return text
  }

  /// 组合文本在显示文本中的字节区间（渲染下划线）。
  var markedByteRange: Range<Int>? {
    guard !composition.isEmpty else { return nil }
    return cursorByte..<(cursorByte + composition.utf8.count)
  }

  /// 组合文本在显示文本中的 UTF-16 区间（系统输入上下文查询）。
  var markedUTF16Range: NSRange {
    guard !composition.isEmpty else { return NSRange(location: NSNotFound, length: 0) }
    let location = utf16Range(fromByteRange: cursorByte..<cursorByte).location
    return NSRange(location: location, length: composition.utf16.count)
  }

  /// 内容变更回调（T-037，ADR-023）：AppDelegate 维护 dirty 状态用。
  ///
  /// 决策依据：仅内容变更（type / delete / undo / redo）触发；光标移动与选区
  /// 不置脏（ADR-023 决策 4）。回调而非协议（Rule 2：无多实现方）。
  var onChange: (() -> Void)?

  var lines: [String] { Self.splitLines(displayText) }

  /// 行数（渲染高度 / 视口窗口计算；T-038 起不再依赖全文 lines）。
  var lineCount: Int { lineByteRanges.count }

  /// 显示文本每行的字节区间（光标 / 选区 / 标记映射到行内坐标）。
  ///
  /// 决策依据（T-038）：由 displayText 缓存派生，整份切分只在失效后首次访问时
  /// 发生一次；渲染帧复用同一缓存（I-003：消除每帧 O(n)）。
  var lineByteRanges: [Range<Int>] {
    if let cached = lineRangesCache { return cached }
    let ranges = Self.lineRanges(of: displayText)
    lineRangesCache = ranges
    return ranges
  }

  /// 按行号取单行文本（渲染 / 命中换算用；T-038：只切可见行，不整份 split）。
  ///
  /// 决策依据：行区间来自缓存，每次调用只复制一行子串；渲染帧内每可见行一次
  /// shaping 建一行文本，替代原来每帧对全文 split 后逐行取用。
  func lineText(_ index: Int) -> String {
    let ranges = lineByteRanges
    guard ranges.indices.contains(index) else { return "" }
    return Self.slice(displayText, ranges[index])
  }

  /// 字节偏移 → 行号（滚动与光标定位）。
  ///
  /// 决策依据（T-038）：行起点有序，二分定位替代线性扫描，万行文档下由
  /// O(n)/帧 降为 O(log n)（partitioningIndex 在当前 SDK 不可用，手写二分，
  /// Rule 11：这是标准二分而非自研算法）。
  func lineIndex(ofByteOffset offset: Int) -> Int {
    let ranges = lineByteRanges
    var low = 0
    var high = ranges.count
    while low < high {
      let mid = (low + high) / 2
      if ranges[mid].lowerBound <= offset {
        low = mid + 1
      } else {
        high = mid
      }
    }
    let firstBeyond = low
    return max(0, firstBeyond - 1)
  }

  // MARK: - 编辑操作（Bridge → Core，ADR-017）

  func typeText(_ text: String) throws {
    if hasMarkedText {
      composition = ""
    }
    _ = try editor_type_text(editor, text)
    invalidateDisplayCache()
    onChange?()
  }

  /// 系统输入回调：`replacementUTF16` 为 IME / 选区替换区间（UTF-16）。
  func insertText(_ text: String, replacementUTF16: NSRange?) throws {
    if hasMarkedText {
      // IME 提交：替换区间 = 组合区间（在显示文本中，不在 Buffer），光标处输入即可。
      try typeText(text)
      return
    }
    if let range = replacementUTF16, range.length > 0 {
      let byteRange = byteRange(fromUTF16: range)
      editor_set_selection(editor, UInt(byteRange.lowerBound), UInt(byteRange.upperBound))
    }
    try typeText(text)
  }

  func deleteBackward() throws {
    if hasMarkedText {
      composition = ""
    }
    _ = try editor_delete_backward(editor)
    invalidateDisplayCache()
    onChange?()
  }

  func move(_ movement: Movement, extend: Bool) {
    if hasMarkedText {
      composition = ""  // 移动取消组合（系统惯例）
      invalidateDisplayCache()
    }
    switch movement {
    case .left: editor_move_left(editor, extend)
    case .right: editor_move_right(editor, extend)
    case .up: editor_move_up(editor, extend)
    case .down: editor_move_down(editor, extend)
    case .lineStart: editor_move_line_start(editor, extend)
    case .lineEnd: editor_move_line_end(editor, extend)
    case .docStart: editor_move_doc_start(editor, extend)
    case .docEnd: editor_move_doc_end(editor, extend)
    }
  }

  func setMarkedText(_ text: String) {
    composition = text
    invalidateDisplayCache()
  }

  func unmarkText() {
    if !composition.isEmpty {
      composition = ""
      invalidateDisplayCache()
    }
  }

  func undo() throws {
    _ = try editor_undo(editor)
    invalidateDisplayCache()
    onChange?()
  }

  func redo() throws {
    _ = try editor_redo(editor)
    invalidateDisplayCache()
    onChange?()
  }

  /// 显示文本 / 行区间缓存失效（T-038）：内容或组合文本变化后调用；
  /// 失效只是置空缓存，下次访问时按需重建一次。
  private func invalidateDisplayCache() {
    displayTextCache = nil
    lineRangesCache = nil
  }

  func selectAll() {
    editor_select_all(editor)
  }

  func setSelection(anchor: Int, head: Int) {
    editor_set_selection(editor, UInt(anchor), UInt(head))
  }

  // MARK: - UTF-16 ↔ UTF-8（IME 区间是 UTF-16 语义，Core 是字节，ADR-017）

  func byteRange(fromUTF16 range: NSRange) -> Range<Int> {
    let text = bufferText
    let start = Self.byteOffset(ofUTF16: range.location, in: text)
    let end = Self.byteOffset(ofUTF16: range.location + range.length, in: text)
    return start..<end
  }

  func utf16Range(fromByteRange range: Range<Int>) -> NSRange {
    let text = bufferText
    let start = text.utf8.index(text.utf8.startIndex, offsetBy: range.lowerBound)
    let end = text.utf8.index(text.utf8.startIndex, offsetBy: range.upperBound)
    let location = text.utf16.distance(from: text.utf16.startIndex, to: start)
    let length = text.utf16.distance(from: start, to: end)
    return NSRange(location: location, length: length)
  }

  static func byteOffset(ofUTF16 utf16Offset: Int, in text: String) -> Int {
    let index = text.utf16.index(text.utf16.startIndex, offsetBy: utf16Offset)
    return text.utf8.distance(from: text.utf8.startIndex, to: index)
  }

  static func splitLines(_ text: String) -> [String] {
    lineRanges(of: text).map { slice(text, $0) }
  }

  static func lineRanges(of text: String) -> [Range<Int>] {
    let starts = layout_line_starts(text)
    var result: [Range<Int>] = []
    for i in starts.indices {
      let start = Int(starts[i])
      let end = i + 1 < starts.count ? Int(starts[i + 1]) - 1 : text.utf8.count
      result.append(start..<end)
    }
    return result
  }

  static func slice(_ text: String, _ range: Range<Int>) -> String {
    let from = text.utf8.index(text.utf8.startIndex, offsetBy: range.lowerBound)
    let to = text.utf8.index(text.utf8.startIndex, offsetBy: range.upperBound)
    return String(text[from..<to])
  }
}
