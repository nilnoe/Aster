//! 单行文本的 CoreText shaping 数据（T-013，ADR-017）。
//!
//! 决策依据：
//! - 字形渲染、光标 x、鼠标命中、标记下划线共享同一个 CTLine——一次 shaping 多次
//!   查询（Rule 11：不重复造 shaping）；字节偏移语义与 Core 一致（ADR-005）。
//! - 行内偏移是相对行首的字节偏移；跨行映射（行起点换算）由调用方负责。

import AppKit
import CoreText

struct LineLayout {
  let text: String
  let line: CTLine
  private let runs: [CTRun]

  init(text: String, font: NSFont) {
    let attributes: [NSAttributedString.Key: Any] = [.font: font]
    self.text = text
    self.line = CTLineCreateWithAttributedString(
      NSAttributedString(string: text, attributes: attributes)
    )
    self.runs = CTLineGetGlyphRuns(line) as? [CTRun] ?? []
  }

  var width: CGFloat {
    CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
  }

  /// 渲染用字形流：实际字体（含 cascade fallback）+ 字形 + 行内 x（点）。
  func glyphs() -> [(font: CTFont, glyph: CGGlyph, x: CGFloat)] {
    var result: [(font: CTFont, glyph: CGGlyph, x: CGFloat)] = []
    for run in runs {
      let count = CTRunGetGlyphCount(run)
      guard count > 0 else { continue }
      var glyphs = [CGGlyph](repeating: 0, count: count)
      var positions = [CGPoint](repeating: .zero, count: count)
      CTRunGetGlyphs(run, CFRange(location: 0, length: count), &glyphs)
      CTRunGetPositions(run, CFRange(location: 0, length: count), &positions)
      let attributes = CTRunGetAttributes(run) as NSDictionary
      let font = attributes[kCTFontAttributeName] as! CTFont
      for i in 0..<count {
        result.append((font, glyphs[i], CGFloat(positions[i].x)))
      }
    }
    return result
  }

  /// 行内字节偏移 → x（相对行起点，点）；偏移必须落在字符边界。
  func xOffset(atByteOffset byteOffset: Int) -> CGFloat {
    guard byteOffset > 0 else { return 0 }
    let utf16Target = utf16Index(ofByte: byteOffset)
    for run in runs {
      let count = CTRunGetGlyphCount(run)
      guard count > 0 else { continue }
      var positions = [CGPoint](repeating: .zero, count: count)
      var indices = [CFIndex](repeating: 0, count: count)
      CTRunGetPositions(run, CFRange(location: 0, length: count), &positions)
      CTRunGetStringIndices(run, CFRange(location: 0, length: count), &indices)
      // 光标停在字符起始：第一个字形起始 ≥ 目标即返回其位置（行内坐标）。
      for i in 0..<count where Int(indices[i]) >= utf16Target {
        return CGFloat(positions[i].x)
      }
    }
    return width
  }

  /// x → 行内字节偏移（鼠标命中反查）；越界钳制到 [0, len]。
  func byteOffset(atX x: CGFloat) -> Int {
    guard x > 0 else { return 0 }
    for run in runs {
      let count = CTRunGetGlyphCount(run)
      guard count > 0 else { continue }
      var glyphs = [CGGlyph](repeating: 0, count: count)
      var positions = [CGPoint](repeating: .zero, count: count)
      var indices = [CFIndex](repeating: 0, count: count)
      CTRunGetGlyphs(run, CFRange(location: 0, length: count), &glyphs)
      CTRunGetPositions(run, CFRange(location: 0, length: count), &positions)
      CTRunGetStringIndices(run, CFRange(location: 0, length: count), &indices)
      let attributes = CTRunGetAttributes(run) as NSDictionary
      let font = attributes[kCTFontAttributeName] as! CTFont
      for i in 0..<count {
        var advance = CGSize.zero
        CTFontGetAdvancesForGlyphs(font, .horizontal, [glyphs[i]] as [CGGlyph], &advance, 1)
        if x < CGFloat(positions[i].x) + advance.width {
          return byteOffset(ofUTF16: Int(indices[i]))
        }
      }
    }
    return text.utf8.count
  }

  private func utf16Index(ofByte byte: Int) -> Int {
    let index = text.utf8.index(text.utf8.startIndex, offsetBy: byte)
    return text.utf16.distance(from: text.utf16.startIndex, to: index)
  }

  private func byteOffset(ofUTF16 utf16: Int) -> Int {
    let index = text.utf16.index(text.utf16.startIndex, offsetBy: utf16)
    return text.utf8.distance(from: text.utf8.startIndex, to: index)
  }
}
