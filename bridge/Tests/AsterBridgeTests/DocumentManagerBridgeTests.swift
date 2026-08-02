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

  /// T-037（ADR-023）：保存写回绑定路径，注册表读路径返回最新文本。
  func testSaveTextWritesBackToDiskAndRegistry() throws {
    let path = try makeTempFile("old")
    let dm = document_manager_new()
    let id = try document_manager_open_disk(dm, path)

    let savedId = try document_manager_save_text(dm, id, "new 你好")

    XCTAssertEqual(savedId, id, "成功返回同一 id（usize 透传惯例，ADR-014）")
    XCTAssertEqual(document_manager_text(dm, id).toString(), "new 你好")
    XCTAssertEqual(
      try String(contentsOfFile: path, encoding: .utf8), "new 你好",
      "磁盘文件必须被写回（ADR-023 决策 1）"
    )
  }

  /// T-037（ADR-023）：未知 id 保存必须失败可见。
  func testSaveTextUnknownIdFailsVisible() {
    let dm = document_manager_new()
    XCTAssertThrowsError(try document_manager_save_text(dm, 999, "x"))
  }
}
