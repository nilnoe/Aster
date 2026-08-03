//! T-050 组 2 / 组 3：文档生命周期（⌘N / ⌘S / 打开）+ 退出流程三分支
//! （T-070 起经 Session 断言）。
//!
//! 决策依据：覆盖「编辑 → 缓冲自动保存 → ⌘S 合并 → 缓冲行删除」与未决退出
//! 保护（ADR-013 v1.3 / v1.4 / ADR-023 v1.3），全部经真实落盘断言
//! （ASTER_STORE_DIR 临时目录）。

import AsterBridge
import XCTest

@testable import AsterApp

final class DocumentLifecycleIntegrationTests: AppIntegrationTestCase {
  func testNewDocumentCreatesNumberedSnapshotFile() throws {
    launchApp()

    appDelegate.newDocument(nil)
    appDelegate.newDocument(nil)

    let currentId = UInt((try XCTUnwrap(currentModel)).bufferIdValue)
    XCTAssertEqual(try snapshotSeq(currentId), 3)
    XCTAssertEqual(
      snapshotFiles(),
      [snapshotName(seq: 1), snapshotName(seq: 2), snapshotName(seq: 3)]
    )
  }

  func testEditAutoSavesBufferAndMarksDirty() throws {
    launchApp()
    let model = try XCTUnwrap(currentModel)

    // typeText 在光标处（默认 0）插入；断言完整内容而非片段。
    try model.typeText("X")

    let id = UInt(model.bufferIdValue)
    XCTAssertEqual(
      try session_load_buffered(appSession, id).toString(),
      "X你好，世界。Hello, Aster!\nMetal 文本渲染 — 第二行 CJK"
    )
    XCTAssertTrue(pendingSet().contains(id))
  }

  func testSaveMergesBufferIntoSnapshotAndRemovesScratchRow() throws {
    launchApp()
    let model = try XCTUnwrap(currentModel)
    // 光标移到末尾再输入，快照内容 = 默认文本 + 输入（不依赖光标默认位置）。
    model.move(.docEnd, extend: false)
    try model.typeText("保存后的快照内容")
    let id = UInt(model.bufferIdValue)

    XCTAssertTrue(appDelegate.saveCurrentDocument())

    let saved = try String(
      contentsOfFile: storeDir + "/" + snapshotName(seq: Int(try snapshotSeq(id))),
      encoding: .utf8)
    XCTAssertEqual(saved, "你好，世界。Hello, Aster!\nMetal 文本渲染 — 第二行 CJK保存后的快照内容")
    XCTAssertFalse(pendingSet().contains(id))
    XCTAssertThrowsError(try session_load_buffered(appSession, id)) { error in
      XCTAssertTrue((error as? RustString)?.toString().contains("not found") == true)
    }
  }

  /// T-067：未保存指示必须用系统原生 `isDocumentEdited`（关闭按钮红点，
  /// Principle 4 / Rule 11）——编辑后为 true、保存后恢复 false；标题保持纯
  /// 文件名（不再手拼「●」前缀）。
  func testDirtyIndicatorUsesSystemDocumentEditedState() throws {
    launchApp()
    let window = try XCTUnwrap(appDelegate.currentFrame)
    let model = try XCTUnwrap(currentModel)
    XCTAssertFalse(window.isDocumentEdited, "初始文档不脏")
    XCTAssertEqual(window.title, "Aster", "初始标题为纯 App 名")

    try model.typeText("x")

    XCTAssertTrue(window.isDocumentEdited, "编辑后关闭按钮必须显示系统 dirty 点")
    XCTAssertEqual(window.title, "Aster", "标题不得手拼「●」前缀")

    XCTAssertTrue(appDelegate.saveCurrentDocument())

    XCTAssertFalse(window.isDocumentEdited, "保存后 dirty 指示必须复位")
    XCTAssertEqual(window.title, "Aster")
  }

  func testOpenDiskFileReplacesEditorContent() throws {
    launchApp()
    let diskFile = storeDir + "/opened.txt"
    try "来自磁盘的内容".write(toFile: diskFile, atomically: true, encoding: .utf8)

    appDelegate.open(URL(fileURLWithPath: diskFile))

    XCTAssertEqual(currentModel?.bufferText, "来自磁盘的内容")
    let frame = try XCTUnwrap(appDelegate.currentFrame)
    XCTAssertEqual(appDelegate.frameFileName[frame], "opened.txt")
  }

  /// T-059（T-024 前已知限制契约，ADR-013 v1.4）：打开第二个文件 = 视图切换，
  /// 但前一个文档的未决状态 / 缓冲行 / 快照序号必须保留——打开不得丢未保存
  /// 编辑；退出「保存全部」仍覆盖前一个文档。
  func testOpenSecondFileKeepsFirstDocsPendingState() throws {
    launchApp()
    let first = try XCTUnwrap(currentModel)
    let firstId = UInt(first.bufferIdValue)
    try first.typeText("第一个文档的未保存编辑")
    XCTAssertTrue(pendingSet().contains(firstId))
    let diskFile = storeDir + "/second.txt"
    try "第二个文档".write(toFile: diskFile, atomically: true, encoding: .utf8)

    appDelegate.open(URL(fileURLWithPath: diskFile))

    XCTAssertEqual(currentModel?.bufferText, "第二个文档", "视图切换到第二个文档")
    XCTAssertTrue(
      pendingSet().contains(firstId),
      "打开第二个文件不得丢失前一个文档的未决状态"
    )
    XCTAssertEqual(
      try session_load_buffered(appSession, firstId).toString(),
      "第一个文档的未保存编辑你好，世界。Hello, Aster!\nMetal 文本渲染 — 第二行 CJK",
      "前一个文档的缓冲行必须保留"
    )
    _ = try snapshotSeq(firstId)

    seamed.pendingDocsReply = 1
    XCTAssertEqual(appDelegate.applicationShouldTerminate(NSApp), .terminateNow)
    let seq = try snapshotSeq(firstId)
    let saved = try String(
      contentsOfFile: storeDir + "/" + snapshotName(seq: Int(seq)), encoding: .utf8)
    XCTAssertTrue(saved.contains("第一个文档的未保存编辑"), "退出保存全部必须固化前一个文档")
  }
}

/// 退出流程：覆写未决提示 seam（docs/testing.md），驱动三分支。
@MainActor
final class AppExitFlowIntegrationTests: AppIntegrationTestCase {
  /// 经 Session 真实路径播种未决文档（T-070：不再手写三张账本）。
  private func seedPendingDoc(_ text: String) throws -> UInt {
    let id = UInt(try session_open_scratch(appSession))
    try session_content_changed(appSession, id, text)
    return id
  }

  func testTerminateNowWithoutPendingDocs() {
    launchApp()
    XCTAssertEqual(
      appDelegate.applicationShouldTerminate(NSApp),
      .terminateNow
    )
  }

  func testSaveAllMergesEveryPendingDoc() throws {
    launchApp()
    let a = try seedPendingDoc("文档A")
    let b = try seedPendingDoc("文档B")
    seamed.pendingDocsReply = 1

    let reply = appDelegate.applicationShouldTerminate(NSApp)

    XCTAssertEqual(reply, .terminateNow)
    XCTAssertTrue(pendingSet().isEmpty)
    XCTAssertEqual(
      try String(
        contentsOfFile: storeDir + "/" + snapshotName(seq: Int(try snapshotSeq(a))),
        encoding: .utf8),
      "文档A"
    )
    XCTAssertEqual(
      try String(
        contentsOfFile: storeDir + "/" + snapshotName(seq: Int(try snapshotSeq(b))),
        encoding: .utf8),
      "文档B"
    )
  }

  func testDiscardAllClearsPendingAndTerminates() throws {
    launchApp()
    let id = try seedPendingDoc("丢弃内容")
    seamed.pendingDocsReply = 0

    let reply = appDelegate.applicationShouldTerminate(NSApp)

    XCTAssertEqual(reply, .terminateNow)
    XCTAssertTrue(pendingSet().isEmpty)
    XCTAssertThrowsError(try session_load_buffered(appSession, id)) { error in
      XCTAssertTrue((error as? RustString)?.toString().contains("not found") == true)
    }
  }

  func testCancelKeepsPendingDocsAndStopsTermination() throws {
    launchApp()
    let id = try seedPendingDoc("取消保留")
    seamed.pendingDocsReply = nil

    let reply = appDelegate.applicationShouldTerminate(NSApp)

    XCTAssertEqual(reply, .terminateCancel)
    XCTAssertTrue(pendingSet().contains(id))
  }
}
