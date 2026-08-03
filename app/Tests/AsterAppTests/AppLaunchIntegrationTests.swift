//! T-050 组 1 / 组 4：启动链路 + 崩溃恢复。
//!
//! 决策依据：
//! - 组 1 覆盖真实 `applicationDidFinishLaunching`（存储 / 哨兵 / 默认文档 /
//!   onChange 接线），此前只靠手动验证；
//! - 组 4 通过伪造非干净哨兵 + 缓冲文档驱动恢复决策（ADR-013 v1.3 保留 /
//!   删除时机），模态提示经测试子类覆写 seam（docs/testing.md 接缝说明）。

import AsterBridge
import XCTest

@testable import AsterApp

final class AppLaunchIntegrationTests: AppIntegrationTestCase {
  func testLaunchInitializesStorageAndDefaultDocument() throws {
    launchApp()

    XCTAssertNotNil(appDelegate.bufferStore)
    XCTAssertEqual(appDelegate.currentSnapshotSeq, 1)
    XCTAssertFalse(appDelegate.needsRecoveryPrompt)
    XCTAssertNotNil(appDelegate.mainWindow)
    let model = try XCTUnwrap(currentModel)
    XCTAssertEqual(model.bufferText, "你好，世界。Hello, Aster!\nMetal 文本渲染 — 第二行 CJK")
  }

  func testLaunchWiresOnChangeToPendingDocs() throws {
    launchApp()
    let model = try XCTUnwrap(currentModel)
    XCTAssertTrue(appDelegate.pendingDocs.isEmpty)

    try model.typeText("x")

    XCTAssertEqual(appDelegate.pendingDocs.count, 1)
    XCTAssertTrue(appDelegate.pendingDocs.contains(UInt(model.bufferIdValue)))
  }

  func testCleanExitSetsSentinelAndPrunesEmptySnapshots() throws {
    launchApp()

    appDelegate.applicationWillTerminate(
      Notification(name: NSApplication.willTerminateNotification))

    // 哨兵经独立连接读取（避开 AppDelegate 连接在同一文件的并发读）。
    let probe = try store_open_buffer(storeDir)
    XCTAssertTrue(try store_is_clean_exit(probe))
    // 启动即建、从未输入的空快照在干净退出时被清理（ADR-023 v1.6）。
    XCTAssertTrue(snapshotFiles().isEmpty)
  }
}

/// 崩溃恢复集成测试：覆写恢复提示 seam，避免 runModal 阻塞。
@MainActor
final class AppRecoveryIntegrationTests: AppIntegrationTestCase {
  private func seedCrashedBuffer(_ text: String, id: UInt) throws {
    // 崩溃状态必须在启动前播种（setupStorage 读哨兵即清）；此时 AppDelegate
    // 尚无连接，用独立连接写入后释放（无并发连接，落盘数据启动必可见）。
    let store = try store_open_buffer(storeDir)
    try store_set_clean_exit(store, false)
    try store_save_scratch(store, id, text)
  }

  func testRecoveryPromptOnNonCleanExitWithBufferedDocs() throws {
    try seedCrashedBuffer("崩溃前的编辑内容", id: 42)

    launchApp()

    XCTAssertTrue(appDelegate.needsRecoveryPrompt)
  }

  func testRestoreLoadsBufferedContentAndDeletesScratchRow() throws {
    try seedCrashedBuffer("崩溃前的编辑内容", id: 42)
    seamed.recoveryReply = 1

    launchApp()

    let model = try XCTUnwrap(currentModel)
    XCTAssertEqual(model.bufferText, "崩溃前的编辑内容")
    // 恢复 = 内容载入新文档并置脏（ADR-013 v1.3：恢复载入即未决）。
    XCTAssertTrue(appDelegate.pendingDocs.contains(UInt(model.bufferIdValue)))
    let store = try XCTUnwrap(appDelegate.bufferStore)
    // 恢复成功 = 被恢复的旧缓冲行删除（ADR-013 v1.3 删除时机 2）。
    XCTAssertThrowsError(try store_load_scratch(store, 42)) { error in
      XCTAssertTrue((error as? RustString)?.toString().contains("not found") == true)
    }
  }

  func testIgnoreKeepsBufferedContentAndRegistersPending() throws {
    try seedCrashedBuffer("保留在缓冲的内容", id: 7)
    seamed.recoveryReply = 0

    launchApp()

    let store = try XCTUnwrap(appDelegate.bufferStore)
    XCTAssertEqual(try store_load_scratch(store, 7).toString(), "保留在缓冲的内容")
    XCTAssertTrue(appDelegate.pendingDocs.contains(7))
  }

  /// T-059（T-029 前已知限制契约，ADR-013 v1.3 / v1.4）：恢复只把**最新**
  /// 缓冲文档载入视图；其余缓冲文档必须登记未决 + 快照序号（BUG-011 泛化），
  /// 退出「保存全部」可一并固化——不得因只呈现一个而失管其他。
  func testRestorePresentsOnlyLatestBufferedDocAndKeepsOthersManaged() throws {
    try seedCrashedBuffer("文档A内容", id: 42)
    try seedCrashedBuffer("文档B内容", id: 43)
    try seedCrashedBuffer("文档C内容", id: 44)
    seamed.recoveryReply = 1

    launchApp()

    let model = try XCTUnwrap(currentModel)
    XCTAssertEqual(model.bufferText, "文档C内容", "恢复只呈现最新缓冲文档")
    let store = try XCTUnwrap(appDelegate.bufferStore)
    for id in [42, 43] {
      XCTAssertNotNil(
        appDelegate.snapshotSeqByDocId[UInt(id)], "id \(id) 必须登记快照序号")
      XCTAssertTrue(
        appDelegate.pendingDocs.contains(UInt(id)), "id \(id) 必须登记未决")
    }
    XCTAssertEqual(try store_load_scratch(store, 42).toString(), "文档A内容")
    XCTAssertEqual(try store_load_scratch(store, 43).toString(), "文档B内容")

    seamed.pendingDocsReply = 1
    XCTAssertEqual(appDelegate.applicationShouldTerminate(NSApp), .terminateNow)
    for id in [UInt(42), UInt(43), UInt(model.bufferIdValue)] {
      let seq = try XCTUnwrap(appDelegate.snapshotSeqByDocId[id])
      let saved = try String(
        contentsOfFile: storeDir + "/" + snapshotName(seq: Int(seq)), encoding: .utf8)
      XCTAssertFalse(saved.isEmpty, "id \(id) 的内容必须固化进快照")
    }
    XCTAssertTrue(store_scratch_ids(store).isEmpty, "保存全部后缓冲清空")
  }

  /// T-059（BUG-016，ADR-013 v1.4 保留规则 3 / 4）：崩溃恢复选「忽略」后
  /// **全部**缓冲文档必须登记未决 + 快照序号——退出「保存全部」覆盖所有崩溃
  /// 遗留内容，不留「没被问过」的文档（旧实现只登记最新一个，其余内容困在
  /// 缓冲、干净退出后不再提示）。
  func testIgnoreKeepsAllBufferedDocsManagedAndSaveable() throws {
    try seedCrashedBuffer("忽略A内容", id: 42)
    try seedCrashedBuffer("忽略B内容", id: 43)
    try seedCrashedBuffer("忽略C内容", id: 44)
    seamed.recoveryReply = 0

    launchApp()

    let store = try XCTUnwrap(appDelegate.bufferStore)
    for id in [42, 43, 44] {
      XCTAssertTrue(
        appDelegate.pendingDocs.contains(UInt(id)),
        "忽略后 id \(id) 必须登记未决（ADR-013 v1.4：不因忽略而失管）"
      )
      XCTAssertNotNil(
        appDelegate.snapshotSeqByDocId[UInt(id)], "忽略后 id \(id) 必须登记快照序号")
    }

    seamed.pendingDocsReply = 1
    XCTAssertEqual(appDelegate.applicationShouldTerminate(NSApp), .terminateNow)
    let contents = try [42, 43, 44].map { id -> String in
      let seq = try XCTUnwrap(appDelegate.snapshotSeqByDocId[UInt(id)])
      return try String(
        contentsOfFile: storeDir + "/" + snapshotName(seq: Int(seq)), encoding: .utf8)
    }
    XCTAssertTrue(contents[0].contains("忽略A内容"))
    XCTAssertTrue(contents[1].contains("忽略B内容"))
    XCTAssertTrue(contents[2].contains("忽略C内容"))
    XCTAssertTrue(store_scratch_ids(store).isEmpty, "保存全部后缓冲清空——没有文档被留在缓冲里")
  }
}
