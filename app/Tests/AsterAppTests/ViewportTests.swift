//! 视口滚动状态测试（T-018，ADR-019）。
//!
//! 视口是纯几何状态（不碰字体 / Metal），按 docs/testing.md 的薄测试规则可
//! 离屏单测；渲染层的 x 平移与滚轮接线分别在 RendererTests / MetalViewTests
//! 覆盖（T-018，ADR-019 决策 1）。

import XCTest

@testable import AsterApp

final class ViewportTests: XCTestCase {
  private let content = CGSize(width: 400, height: 800)
  private let viewportSize = CGSize(width: 300, height: 600)
  private let lineHeight: CGFloat = 40

  func testPanClampsVerticalToContentBounds() {
    var vp = Viewport()
    vp.pan(deltaX: 0, deltaY: 1000, contentSize: content, viewportSize: viewportSize)
    XCTAssertEqual(vp.scrollY, 200, "内容 800 / 视口 600：最大纵向偏移 200")
    vp.pan(deltaX: 0, deltaY: -2000, contentSize: content, viewportSize: viewportSize)
    XCTAssertEqual(vp.scrollY, 0, "向上越界钳回 0")
  }

  func testPanClampsHorizontalToContentWidth() {
    var vp = Viewport()
    vp.pan(deltaX: 500, deltaY: 0, contentSize: content, viewportSize: viewportSize)
    XCTAssertEqual(vp.scrollX, 100, "内容 400 / 视口 300：最大横向偏移 100")
    vp.pan(deltaX: -600, deltaY: 0, contentSize: content, viewportSize: viewportSize)
    XCTAssertEqual(vp.scrollX, 0)
  }

  func testNarrowContentKeepsHorizontalScrollZero() {
    var vp = Viewport(scrollX: 80)
    vp.clamp(contentSize: CGSize(width: 100, height: 800), viewportSize: viewportSize)
    XCTAssertEqual(vp.scrollX, 0, "内容窄于视口不允许横向滚动（ADR-019）")
  }

  func testEnsureCursorVisibleScrollsRightWhenCursorBeyondRightEdge() {
    var vp = Viewport()
    vp.ensureCursorVisible(
      cursorX: 350, lineTop: 0, lineHeightPts: lineHeight,
      leftPadPts: 12, rightPadPts: 12,
      contentSize: content, viewportSize: viewportSize
    )
    XCTAssertEqual(vp.scrollX, 62, "光标 350 必须停在右缘 12pt 内 → scrollX = 350 - (300 - 12)")
  }

  func testEnsureCursorVisibleScrollsLeftWhenCursorLeftOfViewport() {
    var vp = Viewport(scrollX: 120)
    vp.ensureCursorVisible(
      cursorX: 30, lineTop: 0, lineHeightPts: lineHeight,
      leftPadPts: 12, rightPadPts: 12,
      contentSize: content, viewportSize: viewportSize
    )
    XCTAssertEqual(vp.scrollX, 18, "光标 30 必须停在左缘 12pt 内 → scrollX = 30 - 12")
  }

  func testEnsureCursorVisibleKeepsVerticalBehavior() {
    var up = Viewport(scrollY: 500)
    up.ensureCursorVisible(
      cursorX: 0, lineTop: 300, lineHeightPts: lineHeight,
      leftPadPts: 12, rightPadPts: 12,
      contentSize: content, viewportSize: viewportSize
    )
    XCTAssertEqual(up.scrollY, 200, "行顶 300 < scrollY 500 → 滚到行顶 300，再被内容上限 800-600=200 钳制（行仍在视野内）")
    var down = Viewport(scrollY: 100)
    down.ensureCursorVisible(
      cursorX: 0, lineTop: 700, lineHeightPts: lineHeight,
      leftPadPts: 12, rightPadPts: 12,
      contentSize: content, viewportSize: viewportSize
    )
    XCTAssertEqual(down.scrollY, 140, "行底 740 > 视口底 700 → scrollY = 740 - 600")
  }

  /// BUG-006 回归：光标必须停在左右边缘的留白内，而不是贴边（贴边时 2pt 宽的
  /// 光标 quad 在视口外，行末光标会整体消失）。
  func testEnsureCursorVisibleKeepsCaretInsideHorizontalMargins() {
    var right = Viewport()
    right.ensureCursorVisible(
      cursorX: 350, lineTop: 0, lineHeightPts: lineHeight,
      leftPadPts: 12, rightPadPts: 12,
      contentSize: content, viewportSize: viewportSize
    )
    XCTAssertEqual(right.scrollX, 62, "光标 x - scrollX 必须 ≤ 视口宽 - 右留白 12")
    var left = Viewport(scrollX: 120)
    left.ensureCursorVisible(
      cursorX: 30, lineTop: 0, lineHeightPts: lineHeight,
      leftPadPts: 12, rightPadPts: 12,
      contentSize: content, viewportSize: viewportSize
    )
    XCTAssertEqual(left.scrollX, 18, "光标 x - scrollX 必须 ≥ 左留白 12")
  }

  func testVisibleLineRangeCoversPartialEdges() {
    let vp = Viewport(scrollY: 250)
    XCTAssertEqual(
      vp.visibleLineRange(lineCount: 10, viewportHeightPts: 100, lineHeightPts: lineHeight),
      6..<10,
      "scrollY 250 / 行高 40：首行 6，可视 2.5 行 + 1 余量"
    )
    XCTAssertEqual(
      Viewport().visibleLineRange(lineCount: 0, viewportHeightPts: 100, lineHeightPts: lineHeight),
      0..<0
    )
  }
}
