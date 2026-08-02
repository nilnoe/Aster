//! 字形图集像素契约测试（T-012，ADR-016）。
//!
//! spike 的核心风险是「CoreText 栅格化 → 位图内存 → Metal 纹理上传」的坐标映射；
//! 该测试用真实 GlyphAtlas 栅格化 CJK 字形并读回纹理像素，证明链路可用
//! （View 层最终取向仍以手动验证为准，docs/testing.md）。

import CoreText
import Metal
import XCTest

@testable import AsterApp

@MainActor
final class GlyphAtlasTests: XCTestCase {
  func testCJKGlyphRasterizesIntoAtlas() throws {
    guard let device = MTLCreateSystemDefaultDevice() else {
      throw XCTSkip("Metal 不可用（CI 无 GPU 时跳过像素验证）")
    }
    let atlas = GlyphAtlas(device: device)
    let font = CTFontCreateWithName("PingFang SC" as CFString, 16, nil)
    var glyphs = [CGGlyph](repeating: 0, count: 1)
    let chars: [UniChar] = Array("你".utf16)
    CTFontGetGlyphsForCharacters(font, chars, &glyphs, chars.count)
    XCTAssertNotEqual(glyphs[0], 0, "PingFang SC 必须能映射 CJK 字形")

    let placement = try XCTUnwrap(atlas.placement(for: font, glyph: glyphs[0], scale: 2))
    let rect = placement.atlasRect
    XCTAssertGreaterThan(rect.width, 0)
    XCTAssertGreaterThan(rect.height, 0)

    // 读回字形区域的纹理像素：必须存在非零 alpha（字形被实际栅格化并上传）。
    let width = Int(rect.width)
    let height = Int(rect.height)
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    atlas.texture.getBytes(
      &pixels,
      bytesPerRow: width * 4,
      from: MTLRegionMake2D(Int(rect.minX), Int(rect.minY), width, height),
      mipmapLevel: 0
    )
    let ink = pixels.enumerated().filter { $0.offset % 4 == 3 && $0.element > 0 }.count
    XCTAssertGreaterThan(ink, 0, "字形区域必须包含非空像素")
  }

  /// 回归测试（BUG-001）：Retina（scale=2）下字形必须以像素尺寸栅格化——
  /// 2× 的图集矩形与 bbox 必须明显大于 1×，否则 quad 放大采样导致模糊。
  func testAtlasRasterizesAtPixelScale() throws {
    guard let device = MTLCreateSystemDefaultDevice() else {
      throw XCTSkip("Metal 不可用（CI 无 GPU 时跳过像素验证）")
    }
    let atlas = GlyphAtlas(device: device)
    let font = CTFontCreateWithName("PingFang SC" as CFString, 16, nil)
    var glyphs = [CGGlyph](repeating: 0, count: 1)
    let chars: [UniChar] = Array("你".utf16)
    CTFontGetGlyphsForCharacters(font, chars, &glyphs, chars.count)

    let at1x = try XCTUnwrap(atlas.placement(for: font, glyph: glyphs[0], scale: 1))
    let at2x = try XCTUnwrap(atlas.placement(for: font, glyph: glyphs[0], scale: 2))
    XCTAssertGreaterThan(at2x.atlasRect.height, at1x.atlasRect.height)
    XCTAssertGreaterThan(at2x.bounds.height, at1x.bounds.height)
  }

  /// 信息性基准（无断言）：记录 spike 首帧字形栅格化 + 上传耗时，基线写入
  /// docs/benchmarks.md（T-012；正式渲染基准在 T-020 用 criterion/统一计时建立）。
  func testRasterizeSampleGlyphsBaseline() throws {
    guard let device = MTLCreateSystemDefaultDevice() else {
      throw XCTSkip("Metal 不可用（CI 无 GPU 时跳过基准）")
    }
    let atlas = GlyphAtlas(device: device)
    let font = CTFontCreateWithName("PingFang SC" as CFString, 16, nil)
    let chars = Array("你好世界HelloAster0123".utf16)
    var glyphs = [CGGlyph](repeating: 0, count: chars.count)
    CTFontGetGlyphsForCharacters(font, chars, &glyphs, chars.count)
    let unique = Set(glyphs.filter { $0 != 0 })
    XCTAssertFalse(unique.isEmpty)

    let start = DispatchTime.now()
    for glyph in unique {
      _ = atlas.placement(for: font, glyph: glyph, scale: 2)
    }
    let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
    print(
      "T-012 baseline: rasterize+upload \(unique.count) glyphs @2x = \(String(format: "%.2f", elapsed)) ms"
    )
  }
}
