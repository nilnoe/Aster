//! 保存失败路径测试（T-050 复审，变异 M1 盲区）。
//!
//! 决策依据：变异测试注入「先删缓冲行再写快照」顺序颠倒时全量测试全绿——
//! 既有用例只覆盖写成功路径，无人验证「快照写失败时缓冲行与未决状态必须
//! 保留」（否则保存失败=静默丢数据）。本文件用「快照目标被同名目录占用」
//! 强制 snapshot_write 失败（Is a directory），断言失败可见且数据不丢。

import AsterBridge
import XCTest

@testable import AsterApp

@MainActor
final class SaveFailurePathTests: AppIntegrationTestCase {
  func testSnapshotWriteFailureKeepsBufferRowAndPendingState() throws {
    launchApp()
    let model = try XCTUnwrap(currentModel)
    model.move(.docEnd, extend: false)
    try model.typeText("必须不丢的内容")
    let id = UInt(model.bufferIdValue)
    XCTAssertTrue(appDelegate.pendingDocs.contains(id))

    // 快照目标被同名目录占用 → fs::write 到目录路径必失败（ADR-023 合并写
    // 非原子且无事务；失败必须可见，ADR-004）。
    let snapFile = storeDir + "/" + snapshotName(seq: 1)
    try FileManager.default.removeItem(atPath: snapFile)
    try FileManager.default.createDirectory(atPath: snapFile, withIntermediateDirectories: false)

    XCTAssertFalse(appDelegate.saveCurrentDocument(), "写失败必须返回失败（可见）")
    XCTAssertGreaterThan(seamed.saveErrorCount, 0, "必须弹保存错误提示")

    // 数据保全：缓冲行与未决状态一个都不能少。
    XCTAssertTrue(appDelegate.pendingDocs.contains(id), "未决状态必须保留")
    let store = try XCTUnwrap(appDelegate.bufferStore)
    XCTAssertEqual(
      try store_load_scratch(store, id).toString(),
      "你好，世界。Hello, Aster!\nMetal 文本渲染 — 第二行 CJK必须不丢的内容",
      "缓冲行必须保留（崩溃恢复的最后防线）"
    )
  }

  func testFailedSaveDoesNotPoisonLaterSuccessfulSave() throws {
    launchApp()
    let model = try XCTUnwrap(currentModel)
    model.move(.docEnd, extend: false)
    try model.typeText("先失败后成功")
    let id = UInt(model.bufferIdValue)

    // 第一次保存失败（目标被目录占用）。
    let snapFile = storeDir + "/" + snapshotName(seq: 1)
    try FileManager.default.removeItem(atPath: snapFile)
    try FileManager.default.createDirectory(atPath: snapFile, withIntermediateDirectories: false)
    XCTAssertFalse(appDelegate.saveCurrentDocument())

    // 障碍解除后重试必须成功，且快照内容完整。
    try FileManager.default.removeItem(atPath: snapFile)
    XCTAssertTrue(appDelegate.saveCurrentDocument(), "重试必须成功")
    XCTAssertTrue(appDelegate.pendingDocs.isEmpty)
    let saved = try String(contentsOfFile: storeDir + "/" + snapshotName(seq: 1), encoding: .utf8)
    XCTAssertEqual(saved, "你好，世界。Hello, Aster!\nMetal 文本渲染 — 第二行 CJK先失败后成功")
    let store = try XCTUnwrap(appDelegate.bufferStore)
    XCTAssertThrowsError(try store_load_scratch(store, id))
  }
}
