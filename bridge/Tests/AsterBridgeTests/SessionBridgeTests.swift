//! Session 桥接契约测试（T-070，ADR-025）。
//!
//! 决策依据：T-070 把文档生命周期 FFI 收敛为 session_* 单一入口（取代
//! document_manager_* / store_* / snapshot_*）；本文件把旧 Store / Snapshot /
//! DocumentManager 桥接契约（T-042 / T-043 / T-045 / T-047 / T-015）平移为
//! Session 面，覆盖同一批行为：快照创建 / 缓冲自动保存 / 哨兵 / 删除 /
//! 空快照清理 / 磁盘打开 / Scratch id 递增。

import XCTest

@testable import AsterBridge

final class SessionBridgeTests: XCTestCase {
  private func makeTempDir(_ label: String) -> String {
    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("aster-session-bridge-\(label)-\(UUID().uuidString)")
    try? FileManager.default.removeItem(at: dir)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir.path
  }

  /// T-042 / ADR-023 v1.4：Cmd+N 创建纯文本快照（.txt，序号递增）；内容变更 +
  /// Cmd+S 合并后可直接读回。
  func testOpenScratchThenContentChangedSaveRoundtrip() throws {
    let dir = makeTempDir("merge")
    let session = session_new(dir)
    let id1 = try session_open_scratch(session)
    let id2 = try session_open_scratch(session)
    XCTAssertEqual(id2, id1 + 1, "Cmd+N 每次创建新文档，id 递增")
    XCTAssertEqual(try session_snapshot_seq(session, id2), 2, "快照序号递增")

    try session_content_changed(session, id2, "合并后的内容 你好")
    XCTAssertTrue(session_is_pending(session, id2), "编辑后未决")
    try session_save(session, id2)
    XCTAssertFalse(session_is_pending(session, id2), "保存后未决清空")

    let names =
      (try FileManager.default.contentsOfDirectory(atPath: dir))
      .filter { $0.hasPrefix("aster-") }
    XCTAssertEqual(names.count, 2)
    XCTAssertTrue(names.allSatisfy { $0.hasSuffix(".txt") }, "快照必须是文本文件：\(names)")
    XCTAssertEqual(
      try String(
        contentsOfFile: dir + "/" + names.filter { $0.contains("-002.txt") }[0],
        encoding: .utf8),
      "合并后的内容 你好"
    )
  }

  /// T-041 / ADR-023 v1.3：缓冲（SQLite）自动保存——不按保存也持久化（崩溃保护）；
  /// 重开会话后缓冲行可读。
  func testBufferAutoSaveRoundtripAcrossSessions() throws {
    let dir = makeTempDir("buffer")
    let session = session_new(dir)
    let id = try session_open_scratch(session)
    try session_content_changed(session, id, "未按保存的编辑内容")

    let reopened = session_new(dir)
    XCTAssertEqual(try session_load_buffered(reopened, id).toString(), "未按保存的编辑内容")
    XCTAssertTrue(
      FileManager.default.fileExists(atPath: dir + "/buffer.sqlite"),
      "缓冲文件必须固定为 buffer.sqlite"
    )
  }

  /// T-043（ADR-013 v1.1）：崩溃恢复原语跨语言可用——哨兵 + 缓冲文档枚举。
  func testCrashRecoveryPrimitives() throws {
    let dir = makeTempDir("recovery")
    let session = session_new(dir)

    // 缺省 = 异常退出（崩溃语义）。
    XCTAssertFalse(try session_is_clean_exit(session))
    let id = try session_open_scratch(session)
    try session_content_changed(session, id, "崩溃前的编辑")
    XCTAssertEqual(Array(session_buffered_ids(session)), [id], "缓冲文档可枚举")
    try session_set_clean_exit(session, true)
    XCTAssertTrue(try session_is_clean_exit(session), "干净退出哨兵")
    XCTAssertEqual(
      try session_load_buffered(session, id).toString(), "崩溃前的编辑",
      "恢复入口可读回内容"
    )
  }

  /// T-045（ADR-013 v1.3）：合并 / 丢弃后缓冲行删除，幂等且不再枚举。
  func testDiscardRemovesRowAfterCommit() throws {
    let dir = makeTempDir("delete")
    let session = session_new(dir)
    let id = try session_open_scratch(session)
    try session_content_changed(session, id, "已提交内容")
    try session_discard(session, id)

    XCTAssertTrue(Array(session_buffered_ids(session)).isEmpty, "缓冲已无该文档")
    XCTAssertFalse(session_is_pending(session, id))
    XCTAssertThrowsError(try session_load_buffered(session, id), "删除后读回必须报错")
  }

  /// T-047（ADR-023 v1.6）：进程干净退出删除空快照，非空快照保留。
  func testPruneEmptyRemovesOnlyEmptySnapshots() throws {
    let dir = makeTempDir("prune")
    let session = session_new(dir)
    _ = try session_open_scratch(session)  // 001 空快照
    let second = try session_open_scratch(session)
    try session_content_changed(session, second, "有内容")
    try session_save(session, second)

    let deleted = try session_prune_empty(session)

    XCTAssertEqual(deleted, 1, "只删空快照")
    let names =
      (try FileManager.default.contentsOfDirectory(atPath: dir))
      .filter { $0.hasPrefix("aster-") }
    XCTAssertEqual(names.count, 1, "空快照文件已删除")
    XCTAssertTrue(names[0].contains("-002.txt"), "非空快照保留")
  }

  /// T-015（ADR-001 v1.1）：磁盘打开返回 id 且文本可读（含 CJK）；错误可见。
  func testOpenDiskReturnsIdAndText() throws {
    let dir = makeTempDir("disk")
    let path = dir + "/doc.txt"
    try "你好，世界\nHello Aster".write(toFile: path, atomically: true, encoding: .utf8)
    let session = session_new(dir)

    let id = try session_open_disk(session, path)

    XCTAssertEqual(id, 1, "首个文档 id 从 1 开始（ADR-001）")
    XCTAssertEqual(try session_text(session, id).toString(), "你好，世界\nHello Aster")
  }

  /// ADR-004：路径不存在必须 throws（失败可见，不允许静默空文档）。
  func testOpenNonexistentPathFailsVisible() {
    let dir = makeTempDir("diskfail")
    let session = session_new(dir)
    XCTAssertThrowsError(
      try session_open_disk(session, dir + "/nonexistent-\(UUID().uuidString).txt")
    )
  }

  /// T-041（ADR-001 v1.2）：Scratch 文档 id 唯一递增，作为保存键。
  func testOpenScratchAllocatesDistinctIds() throws {
    let dir = makeTempDir("scratchids")
    let session = session_new(dir)
    let a = try session_open_scratch(session)
    let b = try session_open_scratch(session)
    XCTAssertEqual(a, 1, "首个 Scratch id 从 1 开始（ADR-001）")
    XCTAssertEqual(b, 2)
    XCTAssertNotEqual(a, b)
  }

  /// BUG-011 / BUG-016（ADR-013 v1.4）：崩溃遗留行登记——分配快照序号 +
  /// 置未决；已登记保留原序号（幂等）。
  func testRegisterBufferedAssignsSeqAndPending() throws {
    let dir = makeTempDir("register")
    let session = session_new(dir)
    // 崩溃遗留行（无文档登记）：直接登记。
    let seq = try session_register_buffered(session, 5)
    XCTAssertTrue(session_is_pending(session, 5))
    XCTAssertEqual(try session_snapshot_seq(session, 5), seq)
    XCTAssertEqual(try session_register_buffered(session, 5), seq, "已登记保留原序号")
  }
}
