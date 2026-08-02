//! 顶点流构建（T-018 拆分，Rule 3）。
//!
//! 决策依据：
//! - 顶点生成 + quad 追加助手使 TextRenderer 超 300 行（Rule 3），按 ADR-016
//!   备注的既定方向拆出「顶点生成」与「管线资源」——与 MetalPipeline 拆分
//!   （T-013）同一模式；具体 struct，无 Trait / Protocol（Rule 1 / 2 不触发）。
//! - 职责单一：`EditorModel + Viewport → 顶点流`（画家算法：选区高亮在字形
//!   之下，光标 / 下划线在字形之上；前景色走顶点，ADR-016 预留）。
//! - T-018（ADR-019）：所有 x 坐标减 `viewport.scrollX`；可视行窗口用
//!   `Viewport.visibleLineRange`（与 MetalView 内容宽度测量共用，Rule of Three）。

import AppKit
import CoreText

@MainActor
struct VertexBuilder {
  let font: NSFont
  let lineHeightPts: CGFloat
  let leftPadPts: CGFloat
  let atlas: GlyphAtlas
  private let white = SIMD4<Float>(1, 1, 1, 1)
  private let highlight = SIMD4<Float>(0.24, 0.45, 0.95, 0.35)

  /// 构建全部顶点（选区高亮 → 字形 → 光标 / 下划线，画家算法）。
  func buildVertices(
    model: EditorModel,
    viewport: Viewport,
    caretVisible: Bool,
    viewSize: CGSize,
    scale: CGFloat
  ) -> [Float] {
    var vertices: [Float] = []
    let ascent = CTFontGetAscent(font)
    let lineHeightPx = lineHeightPts * scale
    let scrollX = viewport.scrollX

    let ranges = model.lineByteRanges
    let lineWindow = viewport.visibleLineRange(
      lineCount: model.lineCount,
      viewportHeightPts: viewSize.height / scale,
      lineHeightPts: lineHeightPts
    )
    guard !lineWindow.isEmpty else { return [] }
    let firstLine = lineWindow.lowerBound
    let scrollRemainderPx = (viewport.scrollY - CGFloat(firstLine) * lineHeightPts) * scale
    let selStart = model.selectionStartByte
    let selEnd = model.selectionEndByte
    let cursorByte = model.cursorByte
    // T-038（I-003）：每个可见行只 shaping 一次，选区 / 字形 / 光标三处复用；
    // 原来选区循环与字形循环各建一次 LineLayout（每行每帧两次 shaping）。
    let layouts = lineWindow.map { LineLayout(text: model.lineText($0), font: font) }

    // 1) 选区高亮（字形之下）
    for (offset, lineIndex) in lineWindow.enumerated() where selStart < selEnd {
      let lineRange = ranges[lineIndex]
      let a = max(selStart, lineRange.lowerBound)
      let b = min(selEnd, lineRange.upperBound)
      guard a < b else { continue }
      let layout = layouts[offset]
      let x0 =
        (leftPadPts + layout.xOffset(atByteOffset: a - lineRange.lowerBound) - scrollX)
        * scale
      let x1 =
        (leftPadPts + layout.xOffset(atByteOffset: b - lineRange.lowerBound) - scrollX)
        * scale
      let top = CGFloat(lineIndex) * lineHeightPx - scrollRemainderPx
      appendSolidRect(
        x: x0,
        y: viewSize.height - top - lineHeightPx,
        width: x1 - x0,
        height: lineHeightPx,
        color: highlight,
        viewSize: viewSize,
        vertices: &vertices
      )
    }

    // 2) 字形
    for (offset, lineIndex) in lineWindow.enumerated() {
      let layout = layouts[offset]
      let top = CGFloat(lineIndex) * lineHeightPx - scrollRemainderPx
      let baseline = viewSize.height - top - ascent * scale
      for glyph in layout.glyphs() {
        guard
          let placement = atlas.placement(
            for: glyph.font, glyph: glyph.glyph, scale: scale
          )
        else { continue }
        // BUG-001：图集按像素尺寸栅格化，bbox 已是像素；吸附像素网格。
        let x = ((leftPadPts + glyph.x - scrollX) * scale + placement.bounds.minX).rounded()
        let y = (baseline + placement.bounds.minY).rounded()
        appendQuad(
          x: x,
          y: y,
          width: placement.bounds.width,
          height: placement.bounds.height,
          uv: placement.atlasRect,
          color: white,
          viewSize: viewSize,
          vertices: &vertices
        )
      }
    }

    // 3) 光标（折叠选区 + 闪烁相位）与组合文本下划线（字形之上）
    let cursorLine = model.lineIndex(ofByteOffset: cursorByte)
    if lineWindow.contains(cursorLine) {
      let lineRange = ranges[cursorLine]
      let layout = layouts[cursorLine - firstLine]
      let top = CGFloat(cursorLine) * lineHeightPx - scrollRemainderPx
      if selStart == selEnd && caretVisible {
        // BUG-004：组合期间光标跟随到组合文本末尾（组合在 displayText 中内联于
        // 光标处，无换行，与光标同一行）。
        let caretByte =
          cursorByte + (model.hasMarkedText ? model.composition.utf8.count : 0)
        let x =
          (leftPadPts + layout.xOffset(atByteOffset: caretByte - lineRange.lowerBound) - scrollX)
          * scale
        appendSolidRect(
          x: x.rounded(),
          y: viewSize.height - top - lineHeightPx + 2 * scale,
          width: 2 * scale,
          height: lineHeightPx - 4 * scale,
          color: white,
          viewSize: viewSize,
          vertices: &vertices
        )
      }
      if let marked = model.markedByteRange {
        let a = max(marked.lowerBound, lineRange.lowerBound)
        let b = min(marked.upperBound, lineRange.upperBound)
        if a < b {
          let x0 =
            (leftPadPts + layout.xOffset(atByteOffset: a - lineRange.lowerBound) - scrollX)
            * scale
          let x1 =
            (leftPadPts + layout.xOffset(atByteOffset: b - lineRange.lowerBound) - scrollX)
            * scale
          let baseline = viewSize.height - top - ascent * scale
          appendSolidRect(
            x: x0,
            y: baseline - CTFontGetDescent(font) * scale - 2 * scale,
            width: x1 - x0,
            height: max(1.5 * scale, 1),
            color: white,
            viewSize: viewSize,
            vertices: &vertices
          )
        }
      }
    }
    return vertices
  }

  private func appendSolidRect(
    x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat,
    color: SIMD4<Float>, viewSize: CGSize, vertices: inout [Float]
  ) {
    appendQuad(
      x: x, y: y, width: width, height: height,
      uv: atlas.solidRect, color: color, viewSize: viewSize, vertices: &vertices
    )
  }

  /// 把一个 quad（6 顶点 = 两个三角形）追加进顶点流；坐标像素 → NDC。
  private func appendQuad(
    x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat,
    uv: CGRect, color: SIMD4<Float>,
    viewSize: CGSize, vertices: inout [Float]
  ) {
    let x0 = Float((x / viewSize.width) * 2 - 1)
    let y0 = Float((y / viewSize.height) * 2 - 1)
    let x1 = Float(((x + width) / viewSize.width) * 2 - 1)
    let y1 = Float(((y + height) / viewSize.height) * 2 - 1)
    let u0 = Float(uv.minX / CGFloat(GlyphAtlas.size))
    let v0 = Float(uv.minY / CGFloat(GlyphAtlas.size))
    let u1 = Float(uv.maxX / CGFloat(GlyphAtlas.size))
    let v1 = Float(uv.maxY / CGFloat(GlyphAtlas.size))

    // 底左 / 顶左 / 底右 + 顶左 / 顶右 / 底右（y 向上视图空间）。
    appendVertex(x0, y0, u0, v1, color, &vertices)
    appendVertex(x0, y1, u0, v0, color, &vertices)
    appendVertex(x1, y0, u1, v1, color, &vertices)
    appendVertex(x0, y1, u0, v0, color, &vertices)
    appendVertex(x1, y1, u1, v0, color, &vertices)
    appendVertex(x1, y0, u1, v1, color, &vertices)
  }

  private func appendVertex(
    _ x: Float, _ y: Float, _ u: Float, _ v: Float,
    _ color: SIMD4<Float>, _ vertices: inout [Float]
  ) {
    vertices.append(x)
    vertices.append(y)
    vertices.append(u)
    vertices.append(v)
    vertices.append(color.x)
    vertices.append(color.y)
    vertices.append(color.z)
    vertices.append(color.w)
  }
}
