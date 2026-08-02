//! 字形图集（T-012，ADR-016）。
//!
//! 决策依据：
//! - 单张 RGBA8 纹理 + 按需栅格化：字形经 CoreText（CTFontDrawGlyphs）画入
//!   CGBitmapContext，再以 CPU 上传到 Metal 纹理——复用系统光栅化，不自研字形渲染
//!   （宪法 Rule 11；ADR-016 GPU 缓冲格式）。
//! - 分配坐标语义：x 向右、y 向下（纹理行方向）。CGBitmapContext 默认 y 向上，
//!   图集矩形 (x, y, w, h) 对应默认用户空间 y ∈ [H-y-h, H-y)，上传行与纹理行一致，
//!   无需翻转（推导见 ADR-016 备注的像素坐标映射）。
//! - 图集满 → 整表重建（spike 文本远小于 2048²；增量失效随 T-013 细化）。
//! - BUG-001 修复：字形必须按「像素尺寸」栅格化（16pt × scale=2 → 32px 位图），
//!   否则 quad 放大采样导致模糊；缓存键含 pixelSize，1× / 2× 分开缓存。

import CoreGraphics
import CoreText
import Metal

@MainActor
final class GlyphAtlas {
  static let size = 2048

  let texture: MTLTexture
  private let device: MTLDevice
  private var context: CGContext
  private var packer = AtlasPacker(width: size, height: size)
  private var entries: [GlyphKey: GlyphPlacement] = [:]
  /// 纯白 1×1 区域，供下划线等纯色 quad 采样（UV 指向此处）。
  private let whiteRect: CGRect

  /// 字形放置信息：图集矩形（纹理坐标，像素）+ 字形 bbox（像素，原点在基线）。
  struct GlyphPlacement {
    let atlasRect: CGRect
    let bounds: CGRect
  }

  /// 图集键：字体名 + 像素尺寸 + 字形 id。
  ///
  /// 决策依据（BUG-001）：字形编码依赖具体字体面（CJK fallback 逐 run 字体不同），
  /// 位图尺寸依赖像素尺寸；用字符串键避免持有 CTFont 指针的生命周期问题。
  struct GlyphKey: Hashable {
    let fontName: String
    let pixelSize: Int
    let glyph: CGGlyph
  }

  init(device: MTLDevice) {
    self.device = device
    self.texture = Self.makeTexture(device: device)
    self.context = Self.makeContext()
    let white = CGRect(x: 0, y: 0, width: 1, height: 1)
    self.whiteRect = white
    // 白像素必须经 packer 预留，否则首个字形会分配到 (0,0) 覆盖它（BUG-001 顺带修复）。
    _ = packer.allocate(width: 1, height: 1)
    fillWhite(in: white)
  }

  /// 返回字形的图集矩形与像素 bbox；无轮廓字形（如空格）返回 `nil`。
  func placement(for font: CTFont, glyph: CGGlyph, scale: CGFloat) -> GlyphPlacement? {
    let pixelSize = Int((CTFontGetSize(font) * scale).rounded())
    guard pixelSize > 0 else { return nil }
    let key = GlyphKey(fontName: fontName(of: font), pixelSize: pixelSize, glyph: glyph)
    if let cached = entries[key] {
      return cached
    }

    // BUG-001 根因修复：以像素尺寸复制字体再取 bbox 与栅格化；字形 id 属于字体面，
    // 尺寸变化不影响 id，可直接用 run 的字形。
    let pixelFont = CTFontCreateCopyWithAttributes(font, CTFontGetSize(font) * scale, nil, nil)
    var bounds = CGRect.zero
    CTFontGetBoundingRectsForGlyphs(pixelFont, .horizontal, [glyph] as [CGGlyph], &bounds, 1)
    let w = Int(ceil(bounds.width)) + 2
    let h = Int(ceil(bounds.height)) + 2
    guard w > 2, h > 2 else { return nil }  // 空字形（空格等）无可见轮廓，不占图集

    guard let rect = packer.allocate(width: w, height: h) else {
      // 图集满：整表重建后重试一次（ADR-016：spike 规模下整表重建可接受）。
      reset()
      guard let retried = packer.allocate(width: w, height: h) else { return nil }
      rasterize(font: pixelFont, glyph: glyph, bounds: bounds, rect: retried)
      let placement = GlyphPlacement(atlasRect: retried, bounds: bounds)
      entries[key] = placement
      return placement
    }
    rasterize(font: pixelFont, glyph: glyph, bounds: bounds, rect: rect)
    let placement = GlyphPlacement(atlasRect: rect, bounds: bounds)
    entries[key] = placement
    return placement
  }

  /// 纯白像素矩形（UV 采样用）。
  var solidRect: CGRect { whiteRect }

  private func fontName(of font: CTFont) -> String {
    CTFontCopyPostScriptName(font) as String
  }

  private func rasterize(font: CTFont, glyph: CGGlyph, bounds: CGRect, rect: CGRect) {
    // 字形 bbox（字形空间，原点在基线）放进图集矩形：默认用户空间 y 向上，
    // 基线位于 `H - rect.maxY - bounds.minY`（推导见文件头注释）。
    context.saveGState()
    context.translateBy(
      x: rect.minX - bounds.minX,
      y: CGFloat(Self.size) - rect.maxY - bounds.minY
    )
    var origin = CGPoint.zero
    CTFontDrawGlyphs(font, [glyph] as [CGGlyph], &origin, 1, context)
    context.restoreGState()
    upload(region: rect)
  }

  private func upload(region: CGRect) {
    guard let base = context.data else { return }
    let bytes = base.advanced(
      by: Int(region.minY) * context.bytesPerRow + Int(region.minX) * 4
    )
    texture.replace(
      region: MTLRegionMake2D(
        Int(region.minX), Int(region.minY), Int(region.width), Int(region.height)),
      mipmapLevel: 0,
      withBytes: bytes,
      bytesPerRow: context.bytesPerRow
    )
  }

  private func reset() {
    context = Self.makeContext()
    packer.reset()
    entries.removeAll(keepingCapacity: false)
    _ = packer.allocate(width: 1, height: 1)
    fillWhite(in: whiteRect)
  }

  private func fillWhite(in rect: CGRect) {
    // BUG-002 根因修复：CGBitmapContext 默认 y 向上，纹理行 r ↔ 用户 y = H - r；
    // 纯色 quad 采样纹理行 0（rect=(0,0,1,1)），因此白色必须画在用户 y = H-1..H，
    // 而不是用户 y=0（那会落在纹理最后一行，导致光标 / 选区高亮 / 下划线全不可见）。
    let userRect = CGRect(
      x: rect.minX,
      y: CGFloat(Self.size) - rect.maxY,
      width: rect.width,
      height: rect.height
    )
    context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    context.fill(userRect)
    upload(region: rect)
  }

  private static func makeContext() -> CGContext {
    let space = CGColorSpaceCreateDeviceRGB()
    guard
      let context = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: size * 4,
        space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      )
    else {
      preconditionFailure("无法创建字形图集位图上下文（T-012，ADR-016）")
    }
    return context
  }

  private static func makeTexture(device: MTLDevice) -> MTLTexture {
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: .rgba8Unorm,
      width: size,
      height: size,
      mipmapped: false
    )
    descriptor.usage = [.shaderRead]
    guard let texture = device.makeTexture(descriptor: descriptor) else {
      preconditionFailure("无法创建字形图集纹理（T-012，ADR-016）")
    }
    return texture
  }
}
