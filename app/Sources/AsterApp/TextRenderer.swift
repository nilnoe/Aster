//! Metal 文本渲染器（T-012，ADR-016）。
//!
//! 决策依据：
//! - CoreText shaping（CTLine/CTRun）→ 字形图集纹理 → 每字形 6 顶点 quad，
//!   顶点流 = NDC 位置(2×Float) + UV(2×Float) + 前景色(4×Float)，32B/顶点（ADR-016）。
//! - 前景色走顶点：为 T-014 接 Core Theme 模型（T-006）预留，不改变管线形状。
//! - 事件驱动刷新：只在文本变化后由 MetalView 置 `needsDisplay`，无轮询
//!   （ADR Performance Goals：一切事件驱动）。
//! - shader 以源码内嵌编译：保持 SPM 纯 Swift 构建，不引入 Xcode 资源包
//!   （宪法 Rule 9：spike 不需要资产管线）。

import AppKit
import CoreText
import MetalKit

@MainActor
final class TextRenderer: NSObject, MTKViewDelegate {
  private let device: MTLDevice
  private let commandQueue: MTLCommandQueue
  private let pipeline: MTLRenderPipelineState
  private let sampler: MTLSamplerState
  private let atlas: GlyphAtlas
  private let model: EditorModel
  private let font: NSFont

  init(device: MTLDevice, model: EditorModel) {
    guard let commandQueue = device.makeCommandQueue(),
      let library = try? device.makeLibrary(source: Self.shaderSource, options: nil),
      let pipeline = Self.makePipeline(device: device, library: library),
      let sampler = Self.makeSampler(device: device)
    else {
      preconditionFailure("Metal 渲染管线初始化失败（T-012，ADR-016）")
    }
    self.device = device
    self.commandQueue = commandQueue
    self.pipeline = pipeline
    self.sampler = sampler
    self.atlas = GlyphAtlas(device: device)
    self.model = model
    // 系统字体：CoreText 的 cascade 列表自动覆盖 CJK（PingFang），无需逐字体指定
    // （Principle 4：字形选择交给系统）。
    self.font = NSFont.systemFont(ofSize: 16)
    super.init()
  }

  // MARK: - MTKViewDelegate

  func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

  func draw(in view: MTKView) {
    guard let drawable = view.currentDrawable,
      let pass = view.currentRenderPassDescriptor,
      view.bounds.width > 0, view.bounds.height > 0
    else { return }

    let scale = view.drawableSize.width / view.bounds.width
    let viewSize = view.drawableSize
    var vertices: [Float] = []

    let lineHeight =
      (CTFontGetAscent(font) + CTFontGetDescent(font) + CTFontGetLeading(font)) * scale
    let leftPad = 12 * scale
    // 首行基线：顶边距（spike 固定 12pt，随 T-013 布局接管）+ ascent，从视图顶向下。
    var baseline = viewSize.height - 12 * scale - CTFontGetAscent(font) * scale

    for lineText in model.lines {
      baseline = appendLine(
        lineText, baseline: baseline, leftPad: leftPad, scale: scale,
        viewSize: viewSize, vertices: &vertices)
      baseline -= lineHeight
    }
    if model.hasMarkedText {
      // 组合文本作为末行渲染，并画系统风格下划线（IME 标记，ADR-016）。
      baseline = appendLine(
        model.composition, baseline: baseline, leftPad: leftPad, scale: scale,
        viewSize: viewSize, vertices: &vertices, underline: true)
    }

    guard !vertices.isEmpty else { return }
    let vertexBuffer = vertices.withUnsafeBytes { bytes in
      device.makeBuffer(bytes: bytes.baseAddress!, length: bytes.count, options: [])
    }

    let commandBuffer = commandQueue.makeCommandBuffer()!
    guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }
    encoder.setRenderPipelineState(pipeline)
    encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
    encoder.setFragmentTexture(atlas.texture, index: 0)
    encoder.setFragmentSamplerState(sampler, index: 0)
    encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertices.count / 8)
    encoder.endEncoding()

    commandBuffer.present(drawable)
    commandBuffer.commit()
  }

  // MARK: - 顶点构建

  /// 对一行文本做 CoreText shaping，生成字形 quad 顶点；返回下一行基线 y（视图 y 向上）。
  @discardableResult
  private func appendLine(
    _ text: String,
    baseline: CGFloat,
    leftPad: CGFloat,
    scale: CGFloat,
    viewSize: CGSize,
    vertices: inout [Float],
    underline: Bool = false
  ) -> CGFloat {
    let attributes: [NSAttributedString.Key: Any] = [.font: font]
    let line = CTLineCreateWithAttributedString(
      NSAttributedString(string: text, attributes: attributes))
    let runs = CTLineGetGlyphRuns(line) as? [CTRun] ?? []
    let descent = CTFontGetDescent(font) * scale
    let white = SIMD4<Float>(1, 1, 1, 1)

    for run in runs {
      let count = CTRunGetGlyphCount(run)
      guard count > 0 else { continue }
      var glyphs = [CGGlyph](repeating: 0, count: count)
      var positions = [CGPoint](repeating: .zero, count: count)
      CTRunGetGlyphs(run, CFRange(location: 0, length: count), &glyphs)
      CTRunGetPositions(run, CFRange(location: 0, length: count), &positions)
      // CTRunGetFont 未导出到 Swift（macOS 26 SDK），经 run attributes 取实际
      // 字体——含 cascade fallback（CJK → PingFang），栅格化必须用该字体。
      let attributes = CTRunGetAttributes(run) as NSDictionary
      let runFont = attributes[kCTFontAttributeName] as! CTFont

      for i in 0..<count {
        let atlasRect = atlas.rect(for: runFont, glyph: glyphs[i])
        guard atlasRect.width > 0, atlasRect.height > 0 else { continue }
        var bounds = CGRect.zero
        CTFontGetBoundingRectsForGlyphs(runFont, .horizontal, [glyphs[i]] as [CGGlyph], &bounds, 1)
        let x = leftPad + positions[i].x * scale + bounds.minX * scale
        let y = baseline + bounds.minY * scale
        appendQuad(
          x: x, y: y,
          width: bounds.width * scale,
          height: bounds.height * scale,
          uv: atlasRect,
          color: white,
          viewSize: viewSize,
          vertices: &vertices
        )
      }
    }

    if underline {
      let width = CTLineGetTypographicBounds(line, nil, nil, nil)
      appendQuad(
        x: leftPad,
        y: baseline - descent - 2 * scale,
        width: width * scale,
        height: max(1.5 * scale, 1),
        uv: atlas.solidRect,
        color: white,
        viewSize: viewSize,
        vertices: &vertices
      )
    }
    return baseline
  }

  /// 把一个字形 quad（6 顶点 = 两个三角形）追加进顶点流；坐标先转像素再转 NDC。
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

    // 三个顶点（底左 / 顶左 / 底右）+（顶左 / 顶右 / 底右），y 向上视图空间。
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

  // MARK: - Metal 资源

  private static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct VertexIn {
        float2 position [[attribute(0)]];
        float2 uv [[attribute(1)]];
        float4 color [[attribute(2)]];
    };

    struct VertexOut {
        float4 position [[position]];
        float2 uv;
        float4 color;
    };

    vertex VertexOut vertex_main(VertexIn in [[stage_in]]) {
        VertexOut out;
        out.position = float4(in.position, 0.0, 1.0);
        out.uv = in.uv;
        out.color = in.color;
        return out;
    }

    fragment float4 fragment_main(VertexOut in [[stage_in]],
                                  texture2d<float> atlas [[texture(0)]],
                                  sampler atlas_sampler [[sampler(0)]]) {
        float4 tex = atlas.sample(atlas_sampler, in.uv);
        // 图集为预乘 alpha：顶点色 × 纹理色即得正确的预乘输出（ADR-016 备注）。
        return float4(in.color.rgb * tex.rgb, in.color.a * tex.a);
    }
    """

  private static func makePipeline(device: MTLDevice, library: MTLLibrary)
    -> MTLRenderPipelineState?
  {
    let descriptor = MTLRenderPipelineDescriptor()
    descriptor.vertexFunction = library.makeFunction(name: "vertex_main")
    descriptor.fragmentFunction = library.makeFunction(name: "fragment_main")

    let layout = descriptor.vertexDescriptor!.layouts[0]!
    layout.stride = 32
    layout.stepFunction = .perVertex
    let attrs = descriptor.vertexDescriptor!.attributes
    attrs[0].format = .float2
    attrs[0].offset = 0
    attrs[0].bufferIndex = 0
    attrs[1].format = .float2
    attrs[1].offset = 8
    attrs[1].bufferIndex = 0
    attrs[2].format = .float4
    attrs[2].offset = 16
    attrs[2].bufferIndex = 0

    let attachment = descriptor.colorAttachments[0]!
    attachment.pixelFormat = .bgra8Unorm
    // 预乘 alpha 混合：源一次、目标一减源 alpha（字形纹理 RGB 已含 alpha）。
    attachment.isBlendingEnabled = true
    attachment.rgbBlendOperation = .add
    attachment.alphaBlendOperation = .add
    attachment.sourceRGBBlendFactor = .one
    attachment.sourceAlphaBlendFactor = .one
    attachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
    attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha

    return try? device.makeRenderPipelineState(descriptor: descriptor)
  }

  private static func makeSampler(device: MTLDevice) -> MTLSamplerState? {
    let descriptor = MTLSamplerDescriptor()
    descriptor.minFilter = .linear
    descriptor.magFilter = .linear
    descriptor.sAddressMode = .clampToEdge
    descriptor.tAddressMode = .clampToEdge
    return device.makeSamplerState(descriptor: descriptor)
  }
}
