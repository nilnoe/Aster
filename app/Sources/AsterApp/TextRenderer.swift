//! Metal 文本渲染器（T-012 ADR-016 + T-013 ADR-017 扩展 + T-017 光标）。
//!
//! 决策依据：
//! - 管线不变：CoreText shaping → 字形图集 → 每字形 6 顶点 quad（32B/顶点，
//!   位置 + UV + 前景色，ADR-016）。T-013 增加：可视行窗口（滚动）、选区高亮、
//!   光标、组合文本下划线——全部复用同一顶点流（前景色走顶点，ADR-016 预留）。
//! - 绘制顺序 = 画家算法：选区高亮在字形之下，光标 / 下划线在字形之上。
//! - 事件驱动：只在文本变化 / 滚动 / 选区变化 / 光标相位变化后由视图置
//!   `needsDisplay`（无轮询）。
//! - `renderOffscreen` 与 `render(in:)` 共享同一套顶点构建 + 编码：测试可离屏
//!   读回像素（T-017 回归：光标 / 选区高亮必须真实渲染）。

import AppKit
import CoreText
import MetalKit

@MainActor
final class TextRenderer {
  private let device: MTLDevice
  private let commandQueue: MTLCommandQueue
  private let pipeline: MTLRenderPipelineState
  private let sampler: MTLSamplerState
  private let atlas: GlyphAtlas
  /// 渲染字体（视图做鼠标命中换算需要，内部可见）。
  let font: NSFont
  /// 行高（点）：视图滚动 / 光标可见性计算使用。
  let lineHeightPts: CGFloat

  /// 行左留白（点）（视图做鼠标命中换算需要，内部可见）。
  let leftPadPts: CGFloat = 12
  private let white = SIMD4<Float>(1, 1, 1, 1)
  private let highlight = SIMD4<Float>(0.24, 0.45, 0.95, 0.35)

  init(device: MTLDevice) {
    guard let commandQueue = device.makeCommandQueue(),
      let library = try? device.makeLibrary(source: MetalPipeline.shaderSource, options: nil),
      let pipeline = MetalPipeline.makePipeline(device: device, library: library),
      let sampler = MetalPipeline.makeSampler(device: device)
    else {
      preconditionFailure("Metal 渲染管线初始化失败（T-012，ADR-016）")
    }
    self.device = device
    self.commandQueue = commandQueue
    self.pipeline = pipeline
    self.sampler = sampler
    self.atlas = GlyphAtlas(device: device)
    // 系统字体：CoreText cascade 覆盖 CJK（PingFang），无需逐字体指定（ADR-016）。
    self.font = NSFont.systemFont(ofSize: 16)
    self.lineHeightPts =
      CTFontGetAscent(font) + CTFontGetDescent(font) + CTFontGetLeading(font)
  }

  /// 渲染一帧：可视行窗口内画字形 + 选区 / 光标 / 组合标记。
  func render(in view: MTKView, model: EditorModel, scrollY: CGFloat, caretVisible: Bool) {
    guard let drawable = view.currentDrawable,
      let pass = view.currentRenderPassDescriptor,
      view.bounds.width > 0, view.bounds.height > 0
    else { return }

    let scale = view.drawableSize.width / view.bounds.width
    let vertices = buildVertices(
      model: model,
      scrollY: scrollY,
      caretVisible: caretVisible,
      viewSize: view.drawableSize,
      scale: scale
    )
    guard !vertices.isEmpty else { return }
    let commandBuffer = commandQueue.makeCommandBuffer()!
    encode(vertices: vertices, pass: pass, commandBuffer: commandBuffer)
    commandBuffer.present(drawable)
    commandBuffer.commit()
  }

  /// 离屏渲染（测试 / 基准用）：与 `render(in:)` 共享顶点构建与编码（T-017）。
  func renderOffscreen(
    model: EditorModel,
    scrollY: CGFloat,
    caretVisible: Bool,
    into texture: MTLTexture,
    viewSize: CGSize,
    scale: CGFloat
  ) {
    let vertices = buildVertices(
      model: model,
      scrollY: scrollY,
      caretVisible: caretVisible,
      viewSize: viewSize,
      scale: scale
    )
    guard !vertices.isEmpty else { return }
    let pass = MTLRenderPassDescriptor()
    pass.colorAttachments[0].texture = texture
    pass.colorAttachments[0].loadAction = .clear
    pass.colorAttachments[0].storeAction = .store
    pass.colorAttachments[0].clearColor = MTLClearColor(
      red: 0.13, green: 0.13, blue: 0.15, alpha: 1
    )
    let commandBuffer = commandQueue.makeCommandBuffer()!
    encode(vertices: vertices, pass: pass, commandBuffer: commandBuffer)
    commandBuffer.commit()
    // 离屏路径用于测试读回：必须等 GPU 完成，否则 getBytes 读到未初始化数据。
    commandBuffer.waitUntilCompleted()
  }

  /// 构建全部顶点（选区高亮 → 字形 → 光标 / 下划线，画家算法）。
  private func buildVertices(
    model: EditorModel,
    scrollY: CGFloat,
    caretVisible: Bool,
    viewSize: CGSize,
    scale: CGFloat
  ) -> [Float] {
    var vertices: [Float] = []
    let ascent = CTFontGetAscent(font)
    let lineHeightPx = lineHeightPts * scale

    let lines = model.lines
    let ranges = model.lineByteRanges
    guard let lastLine = ranges.indices.last else { return [] }
    let firstLine = min(max(0, Int(scrollY / lineHeightPts)), lastLine)
    let viewportHeightPts = viewSize.height / scale
    let visibleCount = Int(ceil(viewportHeightPts / lineHeightPts)) + 1
    let lineWindow = firstLine...min(lastLine, firstLine + visibleCount)
    let scrollRemainderPx = (scrollY - CGFloat(firstLine) * lineHeightPts) * scale
    let selStart = model.selectionStartByte
    let selEnd = model.selectionEndByte
    let cursorByte = model.cursorByte

    // 1) 选区高亮（字形之下）
    for lineIndex in lineWindow where selStart < selEnd {
      let lineRange = ranges[lineIndex]
      let a = max(selStart, lineRange.lowerBound)
      let b = min(selEnd, lineRange.upperBound)
      guard a < b else { continue }
      let layout = LineLayout(text: lines[lineIndex], font: font)
      let x0 = (leftPadPts + layout.xOffset(atByteOffset: a - lineRange.lowerBound)) * scale
      let x1 = (leftPadPts + layout.xOffset(atByteOffset: b - lineRange.lowerBound)) * scale
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
    for lineIndex in lineWindow {
      let layout = LineLayout(text: lines[lineIndex], font: font)
      let top = CGFloat(lineIndex) * lineHeightPx - scrollRemainderPx
      let baseline = viewSize.height - top - ascent * scale
      for glyph in layout.glyphs() {
        guard
          let placement = atlas.placement(
            for: glyph.font, glyph: glyph.glyph, scale: scale
          )
        else { continue }
        // BUG-001：图集按像素尺寸栅格化，bbox 已是像素；吸附像素网格。
        let x = ((leftPadPts + glyph.x) * scale + placement.bounds.minX).rounded()
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
      let layout = LineLayout(text: lines[cursorLine], font: font)
      let top = CGFloat(cursorLine) * lineHeightPx - scrollRemainderPx
      if selStart == selEnd && caretVisible {
        // BUG-004：组合期间光标跟随到组合文本末尾（组合在 displayText 中内联于
        // 光标处，无换行，与光标同一行）。
        let caretByte =
          cursorByte + (model.hasMarkedText ? model.composition.utf8.count : 0)
        let x =
          (leftPadPts + layout.xOffset(atByteOffset: caretByte - lineRange.lowerBound))
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
            (leftPadPts + layout.xOffset(atByteOffset: a - lineRange.lowerBound))
            * scale
          let x1 =
            (leftPadPts + layout.xOffset(atByteOffset: b - lineRange.lowerBound))
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

  private func encode(
    vertices: [Float],
    pass: MTLRenderPassDescriptor,
    commandBuffer: MTLCommandBuffer
  ) {
    let vertexBuffer = vertices.withUnsafeBytes { bytes in
      device.makeBuffer(bytes: bytes.baseAddress!, length: bytes.count, options: [])
    }
    guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }
    encoder.setRenderPipelineState(pipeline)
    encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
    encoder.setFragmentTexture(atlas.texture, index: 0)
    encoder.setFragmentSamplerState(sampler, index: 0)
    encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertices.count / 8)
    encoder.endEncoding()
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
