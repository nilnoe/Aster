//! LineLayout 契约测试（T-013，ADR-017）。
//!
//! 断言字体无关的不变量（docs/testing.md）：x 单调、端点钳制、反向命中边界；
//! 具体像素值依赖系统字体，不做断言。

import AppKit
import XCTest

@testable import AsterApp

final class LineLayoutTests: XCTestCase {
  private let font = NSFont.systemFont(ofSize: 16)

  func testXOffsetIsMonotonicAcrossByteOffsets() {
    let layout = LineLayout(text: "你好 abc xyz", font: font)
    var last: CGFloat = 0
    for byte in stride(from: 0, through: layout.text.utf8.count, by: 3) {
      let x = layout.xOffset(atByteOffset: byte)
      XCTAssertGreaterThanOrEqual(x, last)
      last = x
    }
  }

  func testXOffsetAtEndEqualsWidth() {
    let layout = LineLayout(text: "hello", font: font)
    XCTAssertEqual(layout.xOffset(atByteOffset: 5), layout.width, accuracy: 0.01)
  }

  func testByteOffsetClampsAtEdges() {
    let layout = LineLayout(text: "你好 world", font: font)
    XCTAssertEqual(layout.byteOffset(atX: -10), 0)
    XCTAssertEqual(layout.byteOffset(atX: 1_000_000), layout.text.utf8.count)
  }

  func testByteOffsetAtZero() {
    let layout = LineLayout(text: "ab你好", font: font)
    XCTAssertEqual(layout.byteOffset(atX: 0), 0)
  }

  func testCJKWidthPositiveAndMonotonic() {
    let layout = LineLayout(text: "你好", font: font)
    XCTAssertGreaterThan(layout.width, 0)
    XCTAssertLessThanOrEqual(layout.xOffset(atByteOffset: 3), layout.xOffset(atByteOffset: 6))
  }
}
