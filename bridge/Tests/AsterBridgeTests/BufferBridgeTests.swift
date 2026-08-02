//! Swift Bridge spike 契约测试（T-010，ADR-014）。
//!
//! 验证 Swift → Rust → Swift 往返：String、opaque 类型、usize、
//! &str 参数 / 返回、Result（throws）、错误可见（ADR-004）。

import XCTest

@testable import AsterBridge

final class BufferBridgeTests: XCTestCase {
  func testCoreVersionRoundTrip() {
    XCTAssertEqual(core_version().toString(), "0.1.0")
  }

  func testBufferCreateInsertTextRoundTrip() throws {
    let id = BufferId(1)
    let buffer = Buffer(id)
    XCTAssertTrue(buffer.is_empty())

    let len = try buffer_insert(buffer, 0, "你好")
    // "你好" 的 UTF-8 字节数 = 6。
    XCTAssertEqual(len, 6)
    XCTAssertEqual(buffer.text().toString(), "你好")
    XCTAssertEqual(buffer.len(), 6)
    XCTAssertEqual(buffer.id().as_u64(), 1)
  }

  func testBufferInsertInvalidBoundaryFailsVisible() throws {
    let buffer = Buffer(BufferId(2))
    _ = try buffer_insert(buffer, 0, "你")
    // 偏移 1 落在多字节字符中间 → 错误跨语言可见（ADR-004）。
    XCTAssertThrowsError(try buffer_insert(buffer, 1, "x"))
  }
}
