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
}
