//! 快照 + 缓冲桥接契约测试（T-042，ADR-023 v1.4）。
//!
//! 快照 = 纯文本文件（Cmd+N 创建、Cmd+S 合并），必须能在 Buffer 打开；
//! 缓冲 = SQLite（自动保存崩溃保护）。
import XCTest

@testable import AsterBridge

final class SnapshotBridgeTests: XCTestCase {
  private func makeTempDir(_ label: String) -> String {
    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("aster-snapshot-bridge-\(label)-\(UUID().uuidString)")
    try? FileManager.default.removeItem(at: dir)
    return dir.path
  }

  /// T-042：Cmd+N 创建纯文本快照；Cmd+S 合并缓冲内容后可直接读回。
  func testCreateNextThenWriteReadRoundtrip() throws {
    let dir = makeTempDir("merge")
    let snapshot = snapshot_new(dir)
    let seq1 = try snapshot_create_next(snapshot)
    let seq2 = try snapshot_create_next(snapshot)
    XCTAssertEqual(seq2, seq1 + 1, "Cmd+N 每次创建新快照，序号递增")

    // Cmd+S：把缓冲文本合并进当前快照（seq2）。
    try snapshot_write(snapshot, seq2, "合并后的内容 你好")

    XCTAssertEqual(try snapshot_read(snapshot, seq2).toString(), "合并后的内容 你好")
  }

  /// T-042：快照文件必须是 .txt 纯文本（.sqlite 无法在 Buffer 打开的用户反馈）。
  func testSnapshotFilesArePlainTextTxt() throws {
    let dir = makeTempDir("txt")
    let snapshot = snapshot_new(dir)
    _ = try snapshot_create_next(snapshot)

    let names =
      (try FileManager.default.contentsOfDirectory(atPath: dir))
      .filter { $0.hasPrefix("aster-") }
    XCTAssertEqual(names.count, 1)
    XCTAssertTrue(names[0].hasSuffix(".txt"), "快照必须是文本文件：\(names)")
  }

  /// T-041/T-042：缓冲文件（SQLite）自动保存，不按保存也持久化（崩溃保护）。
  func testBufferAutoSaveRoundtrip() throws {
    let dir = makeTempDir("buffer")
    var buffer = try store_open_buffer(dir)
    try store_save_scratch(buffer, 3, "未按保存的编辑内容")

    let reopened = try store_open_buffer(dir)
    XCTAssertEqual(try store_load_scratch(reopened, 3).toString(), "未按保存的编辑内容")
    XCTAssertTrue(
      FileManager.default.fileExists(atPath: dir + "/buffer.sqlite"),
      "缓冲文件必须固定为 buffer.sqlite"
    )
  }
}
