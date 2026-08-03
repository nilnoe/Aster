//! 渲染器离屏像素契约测试（T-017，BUG-002 回归；T-018 横向滚动）。
//!
//! 用真实 TextRenderer 离屏渲染后读回像素：光标列必须出现白色像素、
//! 选区必须出现蓝色调高亮——直接证明纯色覆盖层真实渲染（不再依赖肉眼）；
//! 横向滚动（ADR-019）后字形质心必须整体左移 scrollX × scale。

import AppKit
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
      viewport: Viewport(),
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
      viewport: Viewport(),
      caretVisible: false,
      into: texture,
      viewSize: CGSize(width: 400, height: 100),
      scale: 2
    )
    let pixels = readBack(texture, width: 400, height: 100)
    var found = false
    for i in stride(from: 0, to: pixels.count, by: 4) {
      // UInt8 直接参与 `r + 100` 会溢出（255+100）——先转 Int（测试自身踩坑）。
      let r = Int(pixels[i])
      let g = Int(pixels[i + 1])
      let b = Int(pixels[i + 2])
      if b > 200 && b > r + 100 && b > g + 60 {
        found = true
      }
    }
    XCTAssertTrue(found, "选区高亮必须渲染蓝色调像素（BUG-002）")
  }

  /// T-018（ADR-019）：全部顶点 x 减 scrollX——字形质心左移 scrollX × scale。
  func testHorizontalScrollShiftsGlyphCentroidLeft() throws {
    guard let device = MTLCreateSystemDefaultDevice() else {
      throw XCTSkip("Metal 不可用（CI 无 GPU 时跳过）")
    }
    let model = EditorModel(buffer: Buffer(BufferId(23)))
    try model.typeText("abcdefghijklmnopqrstuvwxyz")
    let renderer = TextRenderer(device: device)
    let texture = makeTexture(device: device, width: 800, height: 100)
    renderer.renderOffscreen(
      model: model,
      viewport: Viewport(),
      caretVisible: false,
      into: texture,
      viewSize: CGSize(width: 800, height: 100),
      scale: 2
    )
    let unscrolled = readBack(texture, width: 800, height: 100)
    renderer.renderOffscreen(
      model: model,
      viewport: Viewport(scrollX: 6),
      caretVisible: false,
      into: texture,
      viewSize: CGSize(width: 800, height: 100),
      scale: 2
    )
    let scrolled = readBack(texture, width: 800, height: 100)
    // scrollX=6pt @2x → 左移 12px；6pt 小于左留白 12pt，整行仍在屏内，
    // 质心差应精确等于 12（无裁切干扰）。
    let c0 = glyphCentroid(unscrolled, width: 800, height: 100)
    let c6 = glyphCentroid(scrolled, width: 800, height: 100)
    XCTAssertEqual(c6.x, c0.x - 12, accuracy: 2, "字形质心必须左移 scrollX×scale")
  }

  /// BUG-006 回归：长行末尾光标在横向滚动后必须渲染在右缘留白内（视口内），
  /// 而不是被滚出右边缘整体消失。
  func testCaretAtLineEndStaysInsideRightMargin() throws {
    guard let device = MTLCreateSystemDefaultDevice() else {
      throw XCTSkip("Metal 不可用（CI 无 GPU 时跳过）")
    }
    let model = EditorModel(buffer: Buffer(BufferId(24)))
    try model.typeText(String(repeating: "abcdefghijklmnopqrstuvwxyz", count: 3))
    model.move(.docEnd, extend: false)
    let renderer = TextRenderer(device: device)
    let layout = LineLayout(text: model.lineText(0), font: renderer.font)
    let cursorX = renderer.leftPadPts + layout.width
    let viewportWidthPts: CGFloat = 600
    var viewport = Viewport()
    viewport.ensureCursorVisible(
      cursorX: cursorX, lineTop: 0, lineHeightPts: renderer.lineHeightPts,
      leftPadPts: renderer.leftPadPts, rightPadPts: renderer.rightPadPts,
      contentSize: CGSize(
        width: renderer.leftPadPts + layout.width + renderer.rightPadPts, height: 100
      ),
      viewportSize: CGSize(width: viewportWidthPts, height: 100)
    )
    // 离屏纹理按像素尺寸（600pt × 2）；光标列 = (600 - 12)pt × 2 = 1176px。
    let texture = makeTexture(device: device, width: 1200, height: 200)
    renderer.renderOffscreen(
      model: model,
      viewport: viewport,
      caretVisible: true,
      into: texture,
      viewSize: CGSize(width: 1200, height: 200),
      scale: 2
    )
    let pixels = readBack(texture, width: 1200, height: 200)
    // 光标是 4px 宽的纯白竖线；四列全白才计数，字形墨迹（≤ ~11 行）与右缘
    // 反锯齿边缘不会整列全白，阈值 20 可区分。
    var whiteRows = 0
    for y in 0..<200 {
      var allWhite = true
      for x in 1176..<1180 {
        let i = (y * 1200 + x) * 4
        if pixels[i] <= 200 || pixels[i + 1] <= 200 || pixels[i + 2] <= 200 {
          allWhite = false
        }
      }
      if allWhite {
        whiteRows += 1
      }
    }
    XCTAssertGreaterThan(whiteRows, 20, "末尾光标必须渲染在右缘 12pt 留白内（BUG-006）")
  }

  /// 回归（BUG-004）：组合期间光标渲染在组合文本末尾，而不是组合起点。
  func testCaretFollowsCompositionEnd() throws {
    guard let device = MTLCreateSystemDefaultDevice() else {
      throw XCTSkip("Metal 不可用（CI 无 GPU 时跳过）")
    }
    let model = EditorModel(buffer: Buffer(BufferId(22)))
    try model.typeText("ab")
    model.move(.docEnd, extend: false)
    model.setMarkedText("你好")
    let renderer = TextRenderer(device: device)
    let texture = makeTexture(device: device, width: 600, height: 100)
    renderer.renderOffscreen(
      model: model,
      viewport: Viewport(),
      caretVisible: true,
      into: texture,
      viewSize: CGSize(width: 600, height: 100),
      scale: 2
    )
    let pixels = readBack(texture, width: 600, height: 100)
    // 期望光标列 = (12pt 左留白 + "ab你好" 宽) × 2。
    let layout = LineLayout(text: "ab你好", font: NSFont.systemFont(ofSize: 16))
    let caretX0 = Int((12 + layout.width) * 2)
    var whiteRows = 0
    for y in 0..<100 {
      var rowWhite = false
      for x in caretX0..<(caretX0 + 4) {
        let i = (y * 600 + x) * 4
        if pixels[i] > 200 && pixels[i + 1] > 200 && pixels[i + 2] > 200 {
          rowWhite = true
        }
      }
      if rowWhite {
        whiteRows += 1
      }
    }
    XCTAssertGreaterThan(whiteRows, 20, "组合期间光标必须跟随到组合文本末尾（BUG-004）")
  }

  /// 白色字形像素的质心（x 轴）：用于横向滚动位移断言，抗抗锯齿边缘噪声。
  private func glyphCentroid(_ pixels: [UInt8], width: Int, height: Int) -> (x: Double, y: Double) {
    var sumX = 0.0
    var sumY = 0.0
    var count = 0.0
    for y in 0..<height {
      for x in 0..<width {
        let i = (y * width + x) * 4
        if pixels[i] > 200 && pixels[i + 1] > 200 && pixels[i + 2] > 200 {
          sumX += Double(x)
          sumY += Double(y)
          count += 1
        }
      }
    }
    return (sumX / count, sumY / count)
  }
}
