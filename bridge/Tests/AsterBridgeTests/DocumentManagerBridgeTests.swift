//! DocumentManager 桥接契约测试（T-015，ADR-001 v1.1）。
//!
//! 验证 Swift → Rust → Swift 的文件打开闭环：Disk 源读入文本（含 CJK）、
//! 按 id 取回内容、错误可见（ADR-004：路径不存在必须 throws）。

import XCTest

@testable import AsterBridge

final class DocumentManagerBridgeTests: XCTestCase {
  private func makeTempFile(_ content: String) throws -> String {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("aster-dm-bridge-\(UUID().uuidString).txt")
    try content.write(to: url, atomically: true, encoding: .utf8)
    return url.path
  }

  func testOpenDiskReturnsIdAndText() throws {
    let path = try makeTempFile("你好，世界\nHello Aster")
    let dm = document_manager_new()

    let id = try document_manager_open_disk(dm, path)

    XCTAssertEqual(id, 1, "首个文档 id 从 1 开始（ADR-001）")
    XCTAssertEqual(document_manager_text(dm, id).toString(), "你好，世界\nHello Aster")
  }

  func testOpenNonexistentPathFailsVisible() {
    let dm = document_manager_new()
    // 错误必须跨语言可见（ADR-004：失败可见，不允许静默空文档）。
    XCTAssertThrowsError(
      try document_manager_open_disk(dm, "/nonexistent/aster-\(UUID().uuidString).txt")
    )
  }
}
