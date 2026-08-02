//! Store 桥接契约测试（T-041，ADR-023 v1.3）。
//!
//! 验证 Swift → Rust → SQLite 的三文件模型：Cmd+N 建快照（返回序号递增）、
//! 缓冲自动保存（buffer.sqlite 读回）、Cmd+S 合并（快照读回最新提交）。
import XCTest

@testable import AsterBridge

final class StoreBridgeTests: XCTestCase {
  private func makeTempDir(_ label: String) -> String {
    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("aster-store-bridge-\(label)-\(UUID().uuidString)")
    try? FileManager.default.removeItem(at: dir)
    return dir.path
  }

  /// T-041：Cmd+N 快照序号递增；Cmd+S 合并（open_snapshot 写）后读回。
  func testNewSnapshotMergesBufferIntoCurrentSnapshot() throws {
    let dir = makeTempDir("merge")
    let seq1 = try store_next_snapshot(dir)
    let seq2 = try store_next_snapshot(dir)
    XCTAssertEqual(seq2, seq1 + 1, "Cmd+N 每次新建快照，序号递增")

    // Cmd+S：把缓冲内容合并进当前快照（seq2）。
    var snapshot = try store_open_snapshot(dir, seq2)
    try store_save_scratch(snapshot, 7, "提交内容 你好")

    let reopened = try store_open_snapshot(dir, seq2)
    XCTAssertEqual(try store_load_scratch(reopened, 7).toString(), "提交内容 你好")
    // 当日最高序号快照即最新提交（T-028 恢复入口）。
    let latest = try store_open_latest(dir)
    XCTAssertEqual(try store_load_scratch(latest, 7).toString(), "提交内容 你好")
  }

  /// T-041：缓冲文件自动保存（不按保存键也持久化，崩溃保护）。
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
