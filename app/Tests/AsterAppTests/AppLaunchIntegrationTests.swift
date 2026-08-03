//! T-050 组 1 / 组 4：启动链路 + 崩溃恢复（T-070 起经 Session 断言）。
//!
//! 决策依据：
//! - 组 1 覆盖真实 `applicationDidFinishLaunching`（存储 / 哨兵 / 默认文档 /
//!   onChange 接线），此前只靠手动验证；
//! - 组 4 通过伪造非干净哨兵 + 缓冲文档驱动恢复决策（ADR-013 v1.3 保留 /
//!   删除时机），模态提示经测试子类覆写 seam（docs/testing.md 接缝说明）。
//! - 崩溃播种经 Session 真实路径（seedCrashedDocs）：旧假 id（42 / 5 / 9）
//!   会掩盖「恢复新文档 id 复用崩溃旧 id」的碰撞（BUG-023），本组全部用
//!   真实 id 断言。

import AsterBridge
import XCTest

@testable import AsterApp

final class AppLaunchIntegrationTests: AppIntegrationTestCase {
  func testLaunchInitializesStorageAndDefaultDocument() throws {
    launchApp()

    XCTAssertNotNil(appDelegate.session)
    XCTAssertFalse(appDelegate.needsRecoveryPrompt)
    XCTAssertNotNil(appDelegate.currentFrame)
    let model = try XCTUnwrap(currentModel)
    XCTAssertEqual(try snapshotSeq(UInt(model.bufferIdValue)), 1)
    XCTAssertEqual(model.bufferText, "你好，世界。Hello, Aster!\nMetal 文本渲染 — 第二行 CJK")
  }

  func testLaunchWiresOnChangeToPendingDocs() throws {
    launchApp()
    let model = try XCTUnwrap(currentModel)
    XCTAssertTrue(pendingSet().isEmpty)

    try model.typeText("x")

    XCTAssertEqual(pendingSet().count, 1)
    XCTAssertTrue(pendingSet().contains(UInt(model.bufferIdValue)))
  }

  func testCleanExitSetsSentinelAndPrunesEmptySnapshots() throws {
    launchApp()

    appDelegate.applicationWillTerminate(
      Notification(name: NSApplication.willTerminateNotification))

    // 哨兵经独立 Session 连接读取（避开 AppDelegate 连接在同一文件的并发读）。
    let probe = session_new(storeDir)
    XCTAssertTrue(try session_is_clean_exit(probe))
    // 启动即建、从未输入的空快照在干净退出时被清理（ADR-023 v1.6）。
    XCTAssertTrue(snapshotFiles().isEmpty)
  }
}

/// 崩溃恢复集成测试：覆写恢复提示 seam，避免 runModal 阻塞。
@MainActor
final class AppRecoveryIntegrationTests: AppIntegrationTestCase {
  func testRecoveryPromptOnNonCleanExitWithBufferedDocs() throws {
    _ = try seedCrashedDocs(["崩溃前的编辑内容"])

    launchApp()

    XCTAssertTrue(appDelegate.needsRecoveryPrompt)
  }

  func testRestoreLoadsBufferedContentAndKeepsNewRow() throws {
    let crashed = try seedCrashedDocs(["崩溃前的编辑内容"])
    seamed.recoveryReply = 1

    launchApp()

    let model = try XCTUnwrap(currentModel)
    XCTAssertEqual(model.bufferText, "崩溃前的编辑内容")
    // 恢复 = 内容载入新文档并置脏（ADR-013 v1.3：恢复载入即未决）。
    XCTAssertTrue(pendingSet().contains(UInt(model.bufferIdValue)))
    // BUG-023：新文档行必须存在（旧实现先写后删，id 复用时行被误删）。
    XCTAssertEqual(
      try bufferedContent(UInt(model.bufferIdValue)),
      "崩溃前的编辑内容"
    )
    // 恢复后 ⌘S 必须成功（BUG-023 回归：旧实现报 scratch not found）。
    XCTAssertTrue(appDelegate.saveCurrentDocument())
    XCTAssertTrue(pendingSet().isEmpty)
  }

  func testIgnoreKeepsBufferedContentAndRegistersPending() throws {
    let crashed = try seedCrashedDocs(["保留在缓冲的内容"])
    seamed.recoveryReply = 0

    launchApp()

    let id = crashed[0]
    XCTAssertEqual(try bufferedContent(id), "保留在缓冲的内容")
    XCTAssertTrue(pendingSet().contains(id))
  }

  /// T-059（T-029 前已知限制契约，ADR-013 v1.3 / v1.4）：恢复只把**最新**
  /// 缓冲文档载入视图；其余缓冲文档必须登记未决 + 快照序号（BUG-011 泛化），
  /// 退出「保存全部」可一并固化——不得因只呈现一个而失管其他。
  func testRestorePresentsOnlyLatestBufferedDocAndKeepsOthersManaged() throws {
    let crashed = try seedCrashedDocs(["文档A内容", "文档B内容", "文档C内容"])
    seamed.recoveryReply = 1

    launchApp()

    let model = try XCTUnwrap(currentModel)
    XCTAssertEqual(model.bufferText, "文档C内容", "恢复只呈现最新缓冲文档")
    let restoredId = UInt(model.bufferIdValue)
    for id in [crashed[0], crashed[1]] {
      _ = try snapshotSeq(id)
      XCTAssertTrue(pendingSet().contains(id), "id \(id) 必须登记未决")
    }
    XCTAssertEqual(try bufferedContent(crashed[0]), "文档A内容")
    XCTAssertEqual(try bufferedContent(crashed[1]), "文档B内容")

    seamed.pendingDocsReply = 1
    XCTAssertEqual(appDelegate.applicationShouldTerminate(NSApp), .terminateNow)
    for id in [crashed[0], crashed[1], restoredId] {
      let seq = try snapshotSeq(id)
      let saved = try String(
        contentsOfFile: storeDir + "/" + snapshotName(seq: Int(seq)), encoding: .utf8)
      XCTAssertFalse(saved.isEmpty, "id \(id) 的内容必须固化进快照")
    }
    XCTAssertTrue(bufferedSet().isEmpty, "保存全部后缓冲清空")
  }

  /// T-059（BUG-016，ADR-013 v1.4 保留规则 3 / 4）：崩溃恢复选「忽略」后
  /// **全部**缓冲文档必须登记未决 + 快照序号——退出「保存全部」覆盖所有崩溃
  /// 遗留内容，不留「没被问过」的文档（旧实现只登记最新一个，其余内容困在
  /// 缓冲、干净退出后不再提示）。
  func testIgnoreKeepsAllBufferedDocsManagedAndSaveable() throws {
    let crashed = try seedCrashedDocs(["忽略A内容", "忽略B内容", "忽略C内容"])
    seamed.recoveryReply = 0

    launchApp()

    for id in crashed {
      XCTAssertTrue(pendingSet().contains(id), "忽略后 id \(id) 必须登记未决")
      _ = try snapshotSeq(id)
    }

    seamed.pendingDocsReply = 1
    XCTAssertEqual(appDelegate.applicationShouldTerminate(NSApp), .terminateNow)
    for (index, id) in crashed.enumerated() {
      let seq = try snapshotSeq(id)
      let saved = try String(
        contentsOfFile: storeDir + "/" + snapshotName(seq: Int(seq)), encoding: .utf8)
      XCTAssertTrue(
        saved.contains(["忽略A内容", "忽略B内容", "忽略C内容"][index]),
        "id \(id) 的内容必须固化进快照"
      )
    }
    XCTAssertTrue(bufferedSet().isEmpty, "保存全部后缓冲清空——没有文档被留在缓冲里")
  }
}
