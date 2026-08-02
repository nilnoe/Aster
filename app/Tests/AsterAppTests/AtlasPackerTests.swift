//! 字形图集分配器契约测试（T-012，ADR-016）。
//!
//! 分配策略是纯几何逻辑（水平条带 + 换行 + 满判定），不依赖 GPU，可在测试中验证。

import XCTest

@testable import AsterApp

final class AtlasPackerTests: XCTestCase {
  func testSequentialAllocsStayInRow() {
    var packer = AtlasPacker(width: 100, height: 100)
    let first = packer.allocate(width: 10, height: 20)
    let second = packer.allocate(width: 5, height: 20)
    XCTAssertEqual(first, CGRect(x: 0, y: 0, width: 10, height: 20))
    XCTAssertEqual(second, CGRect(x: 10, y: 0, width: 5, height: 20))
    XCTAssertFalse(packer.isFull)
  }

  func testWrapStartsNewRow() {
    var packer = AtlasPacker(width: 20, height: 100)
    _ = packer.allocate(width: 15, height: 10)
    let wrapped = packer.allocate(width: 10, height: 10)
    XCTAssertEqual(wrapped, CGRect(x: 0, y: 10, width: 10, height: 10))
  }

  func testFullAtlasReturnsNil() {
    var packer = AtlasPacker(width: 20, height: 10)
    // 15 宽占满当前行，第二个 10 宽先换行，再超出高度 → 满。
    _ = packer.allocate(width: 15, height: 6)
    XCTAssertNil(packer.allocate(width: 10, height: 6))
    XCTAssertTrue(packer.isFull)
  }

  func testAllocatedRectsNeverOverlap() {
    var packer = AtlasPacker(width: 64, height: 64)
    var rects: [CGRect] = []
    for _ in 0..<50 {
      if let rect = packer.allocate(width: 5, height: 8) {
        rects.append(rect)
      }
    }
    for (i, a) in rects.enumerated() {
      for b in rects[(i + 1)...] where a.intersects(b) {
        XCTFail("overlap: \(a) vs \(b)")
      }
    }
    XCTAssertFalse(packer.isFull)
  }

  func testResetClearsState() {
    var packer = AtlasPacker(width: 20, height: 10)
    _ = packer.allocate(width: 10, height: 6)
    packer.reset()
    XCTAssertEqual(packer.allocate(width: 10, height: 6), CGRect(x: 0, y: 0, width: 10, height: 6))
    XCTAssertFalse(packer.isFull)
  }
}
