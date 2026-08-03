//! BUG 复现探针（T-050 复审；T-070 起经 Session 断言）。
//!
//! 决策依据：这是「测试容易过」的反面证据——既有集成测试只覆盖单文档
//! 保存，未覆盖多文件打开 + 保存全部的组合路径；本文件复现 BUG-010 /
//! BUG-011 / BUG-012 并作为回归（docs/bug-workflow.md）。崩溃播种经
//! Session 真实路径（BUG-023：假 id 会掩盖恢复 id 复用碰撞）。

import AsterBridge
import XCTest

@testable import AsterApp

@MainActor
final class BugReproTests: AppIntegrationTestCase {
  func testTwoOpenedFilesShareSnapshotSeqAndOverwriteEachOther() throws {
    launchApp()
    let fileA = storeDir + "/A.txt"
    let fileB = storeDir + "/B.txt"
    try "内容A".write(toFile: fileA, atomically: true, encoding: .utf8)
    try "内容B".write(toFile: fileB, atomically: true, encoding: .utf8)

    appDelegate.open(URL(fileURLWithPath: fileA))
    let idA = UInt(try XCTUnwrap(currentModel).bufferIdValue)
    try currentModel?.typeText("+编辑A")

    appDelegate.open(URL(fileURLWithPath: fileB))
    let idB = UInt(try XCTUnwrap(currentModel).bufferIdValue)
    try currentModel?.typeText("+编辑B")

    XCTAssertNotEqual(idA, idB, "前置：两个文件必须是不同文档")
    // BUG-010 修复：每个打开的文件分配独立快照序号，不再共享。
    XCTAssertNotEqual(
      try snapshotSeq(idA), try snapshotSeq(idB),
      "两个文件不得共享快照序号"
    )

    seamed.pendingDocsReply = 1
    let reply = appDelegate.applicationShouldTerminate(NSApp)

    XCTAssertEqual(reply, .terminateNow)
    // 修复后：A、B 各自合并进独立快照，互不覆盖。
    let seqA = try snapshotSeq(idA)
    let seqB = try snapshotSeq(idB)
    let savedA = try String(
      contentsOfFile: storeDir + "/" + snapshotName(seq: Int(seqA)), encoding: .utf8)
    let savedB = try String(
      contentsOfFile: storeDir + "/" + snapshotName(seq: Int(seqB)), encoding: .utf8)
    XCTAssertTrue(savedA.contains("内容A"), "内容A 丢失，实际: \(savedA)")
    XCTAssertTrue(savedB.contains("内容B"), "内容B 丢失，实际: \(savedB)")
  }

  /// BUG-011：两个未决缓冲文档崩溃后恢复最新，旧文档保留在缓冲但未登记
  /// 快照序号 → 退出「保存全部」找不到 seq → 无法干净退出。修复后全部未决
  /// 文档都有归属快照，保存全部成功。
  func testRecoveryRestoresLatestButOlderBufferedDocBlocksExit() throws {
    // 崩溃状态：两个文档各有未决内容，哨兵非干净（真实 id：1 / 2）。
    let crashed = try seedCrashedDocs(["旧文档内容", "最新文档内容"])

    launchApp()
    seamed.recoveryReply = 1  // 选「恢复」

    // BUG-011 修复：恢复的文档内容已写入缓冲（新 id 的 scratch 行）。
    let restoredId = UInt(try XCTUnwrap(currentModel).bufferIdValue)
    XCTAssertEqual(
      try bufferedContent(restoredId), "最新文档内容")
    // 其余未决文档（id=旧文档）登记了快照序号并置为未决。
    let older = crashed[0]
    _ = try snapshotSeq(older)
    XCTAssertTrue(pendingSet().contains(older))

    seamed.pendingDocsReply = 1
    let reply = appDelegate.applicationShouldTerminate(NSApp)

    // 修复后：全部未决文档都有归属快照 → 保存全部成功 → 正常退出。
    XCTAssertEqual(reply, .terminateNow, "保存全部应成功，不允许卡在退出")
    XCTAssertEqual(seamed.saveErrorCount, 0, "不应弹出保存失败提示")
  }

  /// BUG-012：编辑 → ⌘S 保存（缓冲已清）→ 再输入 → undo 回到快照内容，
  /// 此时缓冲 == 快照，但 dirty 仍标记 → 退出仍提示「未保存更改」。
  func testUndoBackToSnapshotContentStillShowsDirty() throws {
    launchApp()
    let model = try XCTUnwrap(currentModel)
    model.move(.docEnd, extend: false)
    try model.typeText("X")
    XCTAssertTrue(appDelegate.saveCurrentDocument())
    XCTAssertTrue(pendingSet().isEmpty, "保存后不应有未决文档")

    // 再次编辑：选区替换（Replace 单独成步，不触发相邻 Insert 合并——
    // T-004 踩坑：连续插入会合并，undo 一步撤不掉单次输入）。
    model.selectAll()
    try model.typeText("Q")
    XCTAssertTrue(pendingSet().contains(UInt(model.bufferIdValue)), "编辑后应未保存")
    try model.undo()  // 回到快照内容（缓冲 == 快照）

    // 期望：内容与快照一致时不应提示未保存；实际：undo 触发 onChange → mark。
    let id = UInt(model.bufferIdValue)
    XCTAssertFalse(
      pendingSet().contains(id),
      "内容已与快照一致，不应标记为未保存（假 dirty）"
    )
  }
}
