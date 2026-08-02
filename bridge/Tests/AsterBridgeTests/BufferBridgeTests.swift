//! Swift Bridge spike 契约测试（T-010，ADR-014）。
//!
//! 验证 Swift → Rust → Swift 往返：String、opaque 类型、usize、
//! &str 参数 / 返回、Result（throws）、错误可见（ADR-004）。

import XCTest

@testable import AsterBridge

final class BufferBridgeTests: XCTestCase {
  func testCoreVersionRoundTrip() {
    // 版本号单一来源（core/Cargo.toml，经 Bridge 往返）。硬编码具体版本会在每次
    // 发版时失效（T-048：0.1.1 → 0.1.2 时 CI-Swift 抓出）；改为格式断言，
    // 版本与 tag 的一致性由 CI-Release 机械检查（Rule 15）。
    let version = core_version().toString()
    XCTAssertNotNil(
      version.range(of: #"^\d+\.\d+\.\d+$"#, options: .regularExpression),
      "版本号必须是 x.y.z：\(version)"
    )
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

  func testBufferCJKMultilineRoundTrip() throws {
    // CJK + ASCII 多行往返：CJK 每字 3 字节，验证跨语言字节语义一致（T-012）。
    let text = "你好，世界\nHello Aster\n下一行"
    let buffer = Buffer(BufferId(3))
    let len = try buffer_insert(buffer, 0, text)
    XCTAssertEqual(len, UInt(text.utf8.count))
    XCTAssertEqual(buffer.text().toString(), text)
    XCTAssertEqual(buffer.len(), UInt(text.utf8.count))
  }

  func testLayoutLineStartsMixedLines() {
    // 字节起点："ab"=2, '\n'=1 → 3；"你好"=6, '\n'=1 → 10。
    XCTAssertEqual(Array(layout_line_starts("ab\n你好\ne")), [0, 3, 10])
  }

  func testLayoutLineStartsEmptyText() {
    XCTAssertEqual(Array(layout_line_starts("")), [0])
  }
}
