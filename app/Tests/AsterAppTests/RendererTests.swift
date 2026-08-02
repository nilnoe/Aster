//! 渲染器离屏像素契约测试（T-017，BUG-002 回归）。
//!
//! 用真实 TextRenderer 离屏渲染后读回像素：光标列必须出现白色像素、
//! 选区必须出现蓝色调高亮——直接证明纯色覆盖层真实渲染（不再依赖肉眼）。

import AsterBridge
import Metal
import XCTest

@testable import AsterApp

@MainActor
final class RendererTests: XCTestCase {
  private func makeTexture(device: MTLDevice, width: Int, height: Int) -> MTLTexture {
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
      // 必须与 MetalPipeline 的 color attachment 格式一致（bgra8Unorm），
      // 否则编码器验证失败、整帧被丢弃（T-017 踩坑）。
      pixelFormat: .bgra8Unorm,
      width: width,
      height: height,
      mipmapped: false
    )
    descriptor.usage = [.renderTarget, .shaderRead]
    return device.makeTexture(descriptor: descriptor)!
  }

  private func readBack(_ texture: MTLTexture, width: Int, height: Int) -> [UInt8] {
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    texture.getBytes(
      &pixels,
      bytesPerRow: width * 4,
      from: MTLRegionMake2D(0, 0, width, height),
      mipmapLevel: 0
    )
    // bgra8Unorm 内存序为 B,G,R,A；统一换回 R,G,B,A 便于断言。
    for i in stride(from: 0, to: pixels.count, by: 4) {
      pixels.swapAt(i, i + 2)
    }
    return pixels
  }

  func testCaretRendersVisibleWhitePixels() throws {
    guard let device = MTLCreateSystemDefaultDevice() else {
      throw XCTSkip("Metal 不可用（CI 无 GPU 时跳过）")
    }
    let model = EditorModel(buffer: Buffer(BufferId(20)))
    try model.typeText("abc")
    model.move(.docStart, extend: false)
    let renderer = TextRenderer(device: device)
    let texture = makeTexture(device: device, width: 400, height: 100)
    renderer.renderOffscreen(
      model: model,
      scrollY: 0,
      caretVisible: true,
      into: texture,
      viewSize: CGSize(width: 400, height: 100),
      scale: 2
    )
    let pixels = readBack(texture, width: 400, height: 100)
    // 光标 x ≈ (12pt 左留白 + 0) * 2 = 24px，宽 4px。
    // 判据：2px 宽的列上有超过一半行是白色（光标是竖直线，字形不是）。
    var whiteRows = 0
    for y in 0..<100 {
      var rowWhite = false
      for x in 24..<28 {
        let i = (y * 400 + x) * 4
        if pixels[i] > 200 && pixels[i + 1] > 200 && pixels[i + 2] > 200 {
          rowWhite = true
        }
      }
      if rowWhite {
        whiteRows += 1
      }
    }
    // 光标高度 ≈ 行高 - 4pt ≈ 26 行；字形 'a' 墨迹 ≈ 11~13 行，阈值 20 可区分。
    XCTAssertGreaterThan(whiteRows, 20, "光标必须是贯穿行高的竖直线（BUG-002）")
  }

  func testSelectionRendersBlueHighlight() throws {
    guard let device = MTLCreateSystemDefaultDevice() else {
      throw XCTSkip("Metal 不可用（CI 无 GPU 时跳过）")
    }
    let model = EditorModel(buffer: Buffer(BufferId(21)))
    try model.typeText("abcdef")
    model.selectAll()
    let renderer = TextRenderer(device: device)
    let texture = makeTexture(device: device, width: 400, height: 100)
    renderer.renderOffscreen(
      model: model,
      scrollY: 0,
      caretVisible: false,
      into: texture,
      viewSize: CGSize(width: 400, height: 100),
      scale: 2
    )
    let pixels = readBack(texture, width: 400, height: 100)
    var found = false
    for i in stride(from: 0, to: pixels.count, by: 4) {
      let r = pixels[i]
      let g = pixels[i + 1]
      let b = pixels[i + 2]
      if b > 200 && b > r + 100 && b > g + 60 {
        found = true
      }
    }
    XCTAssertTrue(found, "选区高亮必须渲染蓝色调像素（BUG-002）")
  }
}
