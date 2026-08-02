//! Store 桥接契约测试（T-040，ADR-023 v1.2）。
//!
//! 验证 Swift → Rust → SQLite 的保存闭环：Cmd+S 每次保存新建「日期+序号」快照
//! 文件；当日最新快照可重新打开读回（持久化 + 同日多版本契约）。
import XCTest

@testable import AsterBridge

final class StoreBridgeTests: XCTestCase {
  private func makeTempDir(_ label: String) -> String {
    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("aster-store-bridge-\(label)-\(UUID().uuidString)")
    try? FileManager.default.removeItem(at: dir)
    return dir.path
  }

  /// T-040：open_next 保存 → open_latest 读回（跨连接持久化）。
  func testOpenNextSaveThenOpenLatestLoadRoundtrip() throws {
    let dir = makeTempDir("roundtrip")
    var store = try store_open_next(dir)

    try store_save_scratch(store, 7, "你好，SQLite 自动保存")

    let latest = try store_open_latest(dir)
    XCTAssertEqual(try store_load_scratch(latest, 7).toString(), "你好，SQLite 自动保存")
  }

  /// T-040：两次保存 = 两个序号文件；open_latest 必须返回最新（v2）。
  func testTwoSavesProduceSequencedFilesAndLatestWins() throws {
    let dir = makeTempDir("seq")
    var first = try store_open_next(dir)
    try store_save_scratch(first, 3, "v1")
    var second = try store_open_next(dir)
    try store_save_scratch(second, 3, "v2")

    let fileNames =
      (try FileManager.default.contentsOfDirectory(atPath: dir))
      .filter { $0.hasPrefix("aster-") }
      .sorted()
    XCTAssertEqual(fileNames.count, 2, "单日内两次保存 = 两个快照文件")
    XCTAssertTrue(fileNames[0].hasSuffix("-001.sqlite"))
    XCTAssertTrue(fileNames[1].hasSuffix("-002.sqlite"))

    let latest = try store_open_latest(dir)
    XCTAssertEqual(try store_load_scratch(latest, 3).toString(), "v2")
  }
}
