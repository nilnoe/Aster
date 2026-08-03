//! MetalView 的 IME 客户端实现（T-018 拆分，Rule 3）。
//!
//! 决策依据：
//! - 系统输入管线（NSTextInputClient）与视图骨架（滚动 / 菜单 / 闪烁）分离，
//!   保持单一职责并守住 300 行上限（宪法 Rule 3）。被访问成员从 private 提升为
//!   internal 仅为跨文件扩展访问：仍在 App 模块内，不构成公共 API（Rule 4 /
//!   Rule 12 的封装在模块边界内成立）。
//! - `firstRect` 用真实光标 x（含 scrollX 补偿，T-018）：横向滚动后 IME 候选框
//!   跟随光标列，不再用视口中央近似（ADR-019）。

import AppKit

@MainActor
extension MetalView: @MainActor NSTextInputClient {
  func insertText(_ string: Any, replacementRange: NSRange) {
    guard let text = Self.text(from: string) else { return }
    do {
      try model.insertText(text, replacementUTF16: replacementRange)
    } catch {
      NSLog("insertText 写入 Core 失败：\(error)")
    }
    scrollCursorIntoView()
    needsDisplay = true
  }

  func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
    do {
      // T-052（BUG-014）：按协议用 replacementRange 替换选区（选中文本输入
      // 拼音时组合落在替换位置）；替换失败必须可见（ADR-004）。
      try model.setMarkedText(Self.text(from: string) ?? "", replacementUTF16: replacementRange)
    } catch {
      NSLog("setMarkedText 替换失败：\(error)")
    }
    // BUG-007：组合文本延伸（拼音逐字增长）必须同步滚动，组合末尾光标
    // （BUG-004 语义：光标 + 组合长度）保持在右缘留白内；此前只有提交
    // （insertText）滚动，组合期间超出右缘不自动横向滚动。
    scrollCursorIntoView()
    needsDisplay = true
  }

  func unmarkText() {
    model.unmarkText()
    needsDisplay = true
  }

  func selectedRange() -> NSRange {
    if model.hasMarkedText {
      // 组合期间光标在组合文本之后（UTF-16）。
      return NSRange(
        location: model.markedUTF16Range.location + model.composition.utf16.count, length: 0)
    }
    return model.utf16Range(fromByteRange: model.selectionStartByte..<model.selectionEndByte)
  }

  func markedRange() -> NSRange {
    model.markedUTF16Range
  }

  func hasMarkedText() -> Bool { model.hasMarkedText }

  func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?)
    -> NSAttributedString?
  {
    nil  // 无选区文本访问需求（T-013 选择渲染经 Core 选区，不读 attributed text）
  }

  func validAttributesForMarkedText() -> [NSAttributedString.Key] {
    []
  }

  func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
    actualRange?.pointee = range
    // 候选框跟随光标所在行的真实列（T-018 起含 scrollX 补偿；组合期间光标在
    // 组合文本末尾，BUG-004 语义）。
    let line = model.lineIndex(ofByteOffset: model.cursorByte)
    let lineRange = model.lineByteRanges[line]
    let layout = LineLayout(text: model.lineText(line), font: renderer.font)
    let caretByte = model.cursorByte + (model.hasMarkedText ? model.composition.utf8.count : 0)
    let caretX =
      renderer.leftPadPts + layout.xOffset(atByteOffset: caretByte - lineRange.lowerBound)
      - viewport.scrollX
    let lineTop = CGFloat(line) * renderer.lineHeightPts - viewport.scrollY
    let caret = NSRect(
      x: caretX,
      y: bounds.maxY - lineTop - renderer.lineHeightPts * 0.5,
      width: 2,
      height: renderer.lineHeightPts * 0.8
    )
    return window?.convertToScreen(convert(caret, to: nil)) ?? caret
  }

  func characterIndex(for point: NSPoint) -> Int {
    // T-052（BUG-013）：NSTextInputClient 契约（SDK NSTextInputClient.h）——
    // point 是屏幕坐标系，返回值是文本字符索引（协议全量区间为 UTF-16 单位，
    // ADR-017 备注）。旧实现把屏幕点当视图点且返回 UTF-8 字节偏移：CJK 下
    // IME 点击定位索引错位（「你好」中字节 3 应返回 UTF-16 索引 1）。
    let viewPoint = convert(window?.convertPoint(fromScreen: point) ?? point, from: nil)
    let byte = byteOffset(at: viewPoint)
    return model.utf16Range(fromByteRange: byte..<byte).location
  }

  private static func text(from value: Any) -> String? {
    if let string = value as? String {
      return string
    }
    if let attributed = value as? NSAttributedString {
      return attributed.string
    }
    return nil
  }
}
