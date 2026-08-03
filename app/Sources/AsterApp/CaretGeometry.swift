//! 光标几何换算（T-073，ADR-026 同款收拢；App 视图层纯几何）。
//!
//! 决策依据：光标 x/y 换算此前在 MetalView.scrollCursorIntoView /
//! MetalView+Input.firstRect / VertexBuilder 三处各写一份（I-011），scrollX
//! 补偿位置不一致（firstRect 减、scrollCursorIntoView 交给 ensureCursorVisible）；
//! 收拢为纯几何类型，输入输出全为点 / 字节，不碰字体 / Metal，可离屏单测
//! （docs/testing.md）。本类型只产出**内容坐标**（不含 scrollX / scrollY）——
//! 屏幕坐标的视口偏移由调用方按用途施加（firstRect / 渲染减，钳制不减）。

import CoreGraphics

/// 光标几何：内容坐标下的行顶 y 与光标 x。
struct CaretGeometry {
  let lineHeightPts: CGFloat
  let leftPadPts: CGFloat

  /// 行顶 y（内容坐标，点）。
  func lineTop(line: Int) -> CGFloat {
    CGFloat(line) * lineHeightPts
  }

  /// 光标 x（内容坐标，点）：左留白 + 行内 shaping 偏移。
  ///
  /// `caretByte` 为显示文本内字节偏移（EditorModel.caretDisplayByte），
  /// `lineRange` 为该行字节区间（EditorModel.lineByteRanges）。
  func contentX(lineRange: Range<Int>, caretByte: Int, layout: LineLayout) -> CGFloat {
    leftPadPts + layout.xOffset(atByteOffset: caretByte - lineRange.lowerBound)
  }
}
