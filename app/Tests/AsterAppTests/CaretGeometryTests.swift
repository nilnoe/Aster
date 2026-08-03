//! 光标几何换算测试（T-073，I-011）：纯几何、不碰 Metal，按 docs/testing.md
//! 薄测试规则可离屏单测（CaretGeometry 与 Viewport 同款）。

import AppKit
import XCTest

@testable import AsterApp

final class CaretGeometryTests: XCTestCase {
  private let geometry = CaretGeometry(lineHeightPts: 20, leftPadPts: 12)

  func testLineTopScalesWithLineIndex() {
    XCTAssertEqual(geometry.lineTop(line: 0), 0)
    XCTAssertEqual(geometry.lineTop(line: 3), 60)
  }

  func testContentXAtLineStartIsLeftPad() {
    let font = NSFont.systemFont(ofSize: 16)
    let layout = LineLayout(text: "ab", font: font)
    XCTAssertEqual(geometry.contentX(lineRange: 0..<2, caretByte: 0, layout: layout), 12)
  }
}
