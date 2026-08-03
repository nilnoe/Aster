//! EditorModel 的 IME 区间换算扩展（T-075 拆分，Rule 3：EditorModel 306 行
//! 超限——MetalView+Input 同款模式）。决策依据：UTF-16 ↔ UTF-8 换算只依赖
//! internal 成员（bufferText），extension 跨文件可用；换算语义仍唯一在
//! EditorModel（ADR-017 备注：IME 区间是 UTF-16 语义，Core 是字节）。

import Foundation

@MainActor
extension EditorModel {
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
}
