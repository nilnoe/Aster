//! 保存失败路径测试（T-050 复审，变异 M1 盲区；T-070 起经 Session 断言）。
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
    XCTAssertTrue(pendingSet().contains(id))

    // 快照目标被同名目录占用 → fs::write 到目录路径必失败（ADR-023 合并写
    // 非原子且无事务；失败必须可见，ADR-004）。
    let snapFile = storeDir + "/" + snapshotName(seq: Int(try snapshotSeq(id)))
    try FileManager.default.removeItem(atPath: snapFile)
    try FileManager.default.createDirectory(atPath: snapFile, withIntermediateDirectories: false)

    XCTAssertFalse(appDelegate.saveCurrentDocument(), "写失败必须返回失败（可见）")
    XCTAssertGreaterThan(seamed.saveErrorCount, 0, "必须弹保存错误提示")

    // 数据保全：缓冲行与未决状态一个都不能少。
    XCTAssertTrue(pendingSet().contains(id), "未决状态必须保留")
    XCTAssertEqual(
      try session_load_buffered(appSession, id).toString(),
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
    let snapFile = storeDir + "/" + snapshotName(seq: Int(try snapshotSeq(id)))
    try FileManager.default.removeItem(atPath: snapFile)
    try FileManager.default.createDirectory(atPath: snapFile, withIntermediateDirectories: false)
    XCTAssertFalse(appDelegate.saveCurrentDocument())

    // 障碍解除后重试必须成功，且快照内容完整。
    try FileManager.default.removeItem(atPath: snapFile)
    XCTAssertTrue(appDelegate.saveCurrentDocument(), "重试必须成功")
    XCTAssertTrue(pendingSet().isEmpty)
    let saved = try String(
      contentsOfFile: storeDir + "/" + snapshotName(seq: Int(try snapshotSeq(id))),
      encoding: .utf8)
    XCTAssertEqual(saved, "你好，世界。Hello, Aster!\nMetal 文本渲染 — 第二行 CJK先失败后成功")
    XCTAssertThrowsError(try session_load_buffered(appSession, id))
  }

  /// T-054（BUG-015）：缓冲自动保存失败（崩溃保护失效）必须用户可见
  /// （ADR-004），但不能逐键弹窗——同一失败段落内只提示一次；障碍解除后
  /// 下一次成功保存复位，新失败段落再次提示。T-070：提示状态按**文档**隔离
  /// （BUG-020：旧全局单布尔会被另一文档的成功保存吞掉）。
  func testAutoSaveFailureIsVisibleOncePerEpisode() throws {
    launchApp()
    let model = try XCTUnwrap(currentModel)
    let id = UInt(model.bufferIdValue)
    model.move(.docEnd, extend: false)
    try model.typeText("正常保存")
    XCTAssertEqual(seamed.saveErrorCount, 0, "正常路径不提示")

    // 注入写失败：目录只读 → SQLite 无法创建 journal → upsert 失败。
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o555], ofItemAtPath: storeDir)
    defer {
      try? FileManager.default.setAttributes(
        [.posixPermissions: 0o755], ofItemAtPath: storeDir)
    }

    try model.typeText("追加一")
    XCTAssertEqual(seamed.saveErrorCount, 1, "自动保存失败必须可见一次")
    try model.typeText("追加二")
    XCTAssertEqual(seamed.saveErrorCount, 1, "同一失败段落内不逐键弹窗")
    XCTAssertTrue(pendingSet().contains(id), "失败不丢失未决标记")

    // 障碍解除后：成功保存复位提示状态，再失败会再次提示。
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o755], ofItemAtPath: storeDir)
    try model.typeText("恢复后")
    XCTAssertEqual(seamed.saveErrorCount, 1, "成功保存不提示")
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o555], ofItemAtPath: storeDir)
    try model.typeText("再次失败")
    XCTAssertEqual(seamed.saveErrorCount, 2, "新失败段落必须再次可见")
    XCTAssertEqual(
      seamed.lastSaveErrorMessage?.contains("自动保存失败"), true,
      "提示必须说明自动保存失败（崩溃保护失效）"
    )
  }

  /// T-054（BUG-015）：setupStorage 失败（如 ASTER_STORE_DIR 指向普通文件）
  /// 必须启动即提示（ADR-004），后续保存失败提示必须说明「存储未就绪」，
  /// 而非误导性的「文档没有可合并的快照」。
  func testSetupStorageFailureIsVisibleAndSaveStaysHonest() throws {
    // 存储目录指向一个普通文件：SQLite 无法建库 → Session 打开携带失败消息。
    let blocker = storeDir + "/blocker"
    try "not a directory".write(toFile: blocker, atomically: true, encoding: .utf8)
    setenv("ASTER_STORE_DIR", blocker, 1)

    launchApp()

    XCTAssertFalse(session_store_error(appDelegate.session!).toString().isEmpty, "存储未就绪")
    XCTAssertEqual(seamed.saveErrorCount, 1, "启动必须提示存储初始化失败")
    XCTAssertEqual(
      seamed.lastSaveErrorMessage?.contains("存储初始化失败"), true,
      "启动提示必须说明存储初始化失败"
    )

    let model = try XCTUnwrap(currentModel)
    try model.typeText("x")
    XCTAssertTrue(pendingSet().contains(UInt(model.bufferIdValue)))

    XCTAssertFalse(appDelegate.saveCurrentDocument(), "存储未就绪时保存必须失败")
    XCTAssertEqual(
      seamed.lastSaveErrorMessage?.contains("存储未就绪"), true,
      "保存失败提示必须说明存储未就绪，而非误导性消息"
    )
  }

  /// T-056：损坏的 buffer.sqlite（乱字节）启动必须不崩且失败可见（T-054 提示
  /// 路径）——崩溃保护文件损坏不得阻止编辑与启动。
  func testCorruptBufferFileAtLaunchFailsVisibleWithoutCrash() throws {
    try Data("这不是 SQLite 数据库文件".utf8).write(
      to: URL(fileURLWithPath: storeDir + "/buffer.sqlite"))

    launchApp()

    XCTAssertFalse(session_store_error(appDelegate.session!).toString().isEmpty, "损坏缓冲必须视为存储未就绪")
    XCTAssertEqual(seamed.saveErrorCount, 1, "启动必须提示存储初始化失败（T-054）")
    // 不崩溃（用例跑完即为证据）：可继续编辑（未决标记保留），保存失败可见。
    let model = try XCTUnwrap(currentModel)
    try model.typeText("x")
    XCTAssertTrue(pendingSet().contains(UInt(model.bufferIdValue)))
    XCTAssertFalse(appDelegate.saveCurrentDocument())
    XCTAssertEqual(
      seamed.lastSaveErrorMessage?.contains("存储未就绪"), true,
      "损坏缓冲下保存提示必须说明存储未就绪"
    )
  }
}
