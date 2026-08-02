//! Metal 文本渲染器（T-012 ADR-016 + T-013 ADR-017 + T-017 光标 + T-018 横向滚动）。
//!
//! 决策依据：
//! - 管线不变：CoreText shaping → 字形图集 → 每字形 6 顶点 quad（32B/顶点，
//!   位置 + UV + 前景色，ADR-016）。
//! - 本文件只负责管线资源与帧编码；顶点生成（model + viewport → 顶点流）在
//!   `VertexBuilder`（Rule 3 拆分，T-018——与 MetalPipeline 拆分同一模式，
//!   ADR-016 备注）。
//! - 事件驱动：只在文本变化 / 滚动 / 选区变化 / 光标相位变化后由视图置
//!   `needsDisplay`（无轮询）。
//! - `renderOffscreen` 与 `render(in:)` 共享同一套顶点构建 + 编码：测试可离屏
//!   读回像素（T-017 回归：光标 / 选区高亮必须真实渲染；T-018：横向滚动位移）。

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
  private let vertexBuilder: VertexBuilder
  /// 渲染字体（视图做鼠标命中换算需要，内部可见）。
  let font: NSFont
  /// 行高（点）：视图滚动 / 光标可见性计算使用。
  let lineHeightPts: CGFloat

  /// 行左留白（点）（视图做鼠标命中换算需要，内部可见）。
  let leftPadPts: CGFloat = 12

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
    self.vertexBuilder = VertexBuilder(
      font: font,
      lineHeightPts: lineHeightPts,
      leftPadPts: leftPadPts,
      atlas: atlas
    )
  }

  /// 渲染一帧：可视行窗口内画字形 + 选区 / 光标 / 组合标记。
  func render(
    in view: MTKView, model: EditorModel, viewport: Viewport, caretVisible: Bool
  ) {
    guard let drawable = view.currentDrawable,
      let pass = view.currentRenderPassDescriptor,
      view.bounds.width > 0, view.bounds.height > 0
    else { return }

    let scale = view.drawableSize.width / view.bounds.width
    let vertices = vertexBuilder.buildVertices(
      model: model,
      viewport: viewport,
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
    viewport: Viewport,
    caretVisible: Bool,
    into texture: MTLTexture,
    viewSize: CGSize,
    scale: CGFloat
  ) {
    let vertices = vertexBuilder.buildVertices(
      model: model,
      viewport: viewport,
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
}
