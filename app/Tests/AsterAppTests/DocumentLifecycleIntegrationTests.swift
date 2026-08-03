//! T-050 组 2 / 组 3：文档生命周期（⌘N / ⌘S / 打开）+ 退出流程三分支。
//!
//! 决策依据：覆盖「编辑 → 缓冲自动保存 → ⌘S 合并 → 缓冲行删除」与
//! PendingDocs 退出保护（ADR-013 v1.3 / v1.4 / ADR-023 v1.3），
//! 全部经真实落盘断言（ASTER_STORE_DIR 临时目录）。

import AsterBridge
import XCTest

@testable import AsterApp

final class DocumentLifecycleIntegrationTests: AppIntegrationTestCase {
  func testNewDocumentCreatesNumberedSnapshotFile() throws {
    launchApp()

    appDelegate.newDocument(nil)
    appDelegate.newDocument(nil)

    let currentId = UInt((try XCTUnwrap(currentModel)).bufferIdValue)
    XCTAssertEqual(appDelegate.snapshotSeqByDocId[currentId], 3)
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

    let store = try XCTUnwrap(appDelegate.bufferStore)
    let id = UInt(model.bufferIdValue)
    XCTAssertEqual(
      try store_load_scratch(store, id).toString(),
      "X你好，世界。Hello, Aster!\nMetal 文本渲染 — 第二行 CJK"
    )
    XCTAssertTrue(appDelegate.pendingDocs.contains(id))
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
      contentsOfFile: storeDir + "/" + snapshotName(seq: 1), encoding: .utf8)
    XCTAssertEqual(saved, "你好，世界。Hello, Aster!\nMetal 文本渲染 — 第二行 CJK保存后的快照内容")
    XCTAssertFalse(appDelegate.pendingDocs.contains(id))
    let store = try XCTUnwrap(appDelegate.bufferStore)
    XCTAssertThrowsError(try store_load_scratch(store, id)) { error in
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
    XCTAssertTrue(appDelegate.pendingDocs.contains(firstId))
    let diskFile = storeDir + "/second.txt"
    try "第二个文档".write(toFile: diskFile, atomically: true, encoding: .utf8)

    appDelegate.open(URL(fileURLWithPath: diskFile))

    XCTAssertEqual(currentModel?.bufferText, "第二个文档", "视图切换到第二个文档")
    XCTAssertTrue(
      appDelegate.pendingDocs.contains(firstId),
      "打开第二个文件不得丢失前一个文档的未决状态"
    )
    let store = try XCTUnwrap(appDelegate.bufferStore)
    XCTAssertEqual(
      try store_load_scratch(store, firstId).toString(),
      "第一个文档的未保存编辑你好，世界。Hello, Aster!\nMetal 文本渲染 — 第二行 CJK",
      "前一个文档的缓冲行必须保留"
    )
    XCTAssertNotNil(appDelegate.snapshotSeqByDocId[firstId])

    seamed.pendingDocsReply = 1
    XCTAssertEqual(appDelegate.applicationShouldTerminate(NSApp), .terminateNow)
    let seq = try XCTUnwrap(appDelegate.snapshotSeqByDocId[firstId])
    let saved = try String(
      contentsOfFile: storeDir + "/" + snapshotName(seq: Int(seq)), encoding: .utf8)
    XCTAssertTrue(saved.contains("第一个文档的未保存编辑"), "退出保存全部必须固化前一个文档")
  }
}

/// 退出流程：覆写未决提示 seam（docs/testing.md），驱动三分支。
@MainActor
final class AppExitFlowIntegrationTests: AppIntegrationTestCase {
  private func seedPendingDoc(_ text: String, id: UInt) throws {
    // 必须经 AppDelegate 同一连接播种：不同连接写入对同一 SQLite 文件
    // 的可见性依赖提交时序，测试断言不稳定（T-050 踩坑）。
    let store = try XCTUnwrap(appDelegate.bufferStore)
    try store_save_scratch(store, id, text)
    appDelegate.pendingDocs.mark(id)
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
    try seedPendingDoc("文档A", id: 1)
    try seedPendingDoc("文档B", id: 2)
    appDelegate.snapshotSeqByDocId[1] = 11
    appDelegate.snapshotSeqByDocId[2] = 12
    seamed.pendingDocsReply = 1

    let reply = appDelegate.applicationShouldTerminate(NSApp)

    XCTAssertEqual(reply, .terminateNow)
    XCTAssertTrue(appDelegate.pendingDocs.isEmpty)
    XCTAssertEqual(
      try String(
        contentsOfFile: storeDir + "/" + snapshotName(seq: 11), encoding: .utf8),
      "文档A"
    )
    XCTAssertEqual(
      try String(
        contentsOfFile: storeDir + "/" + snapshotName(seq: 12), encoding: .utf8),
      "文档B"
    )
  }

  func testDiscardAllClearsPendingAndTerminates() throws {
    launchApp()
    try seedPendingDoc("丢弃内容", id: 3)
    seamed.pendingDocsReply = 0

    let reply = appDelegate.applicationShouldTerminate(NSApp)

    XCTAssertEqual(reply, .terminateNow)
    XCTAssertTrue(appDelegate.pendingDocs.isEmpty)
    let store = try XCTUnwrap(appDelegate.bufferStore)
    XCTAssertThrowsError(try store_load_scratch(store, 3)) { error in
      // swift-bridge 的 Result<String, String> 错误是 RustString 对象，
      // 需 toString() 取消息（T-050 踩坑；ADR-014 桥接惯例）。
      XCTAssertTrue((error as? RustString)?.toString().contains("not found") == true)
    }
  }

  func testCancelKeepsPendingDocsAndStopsTermination() throws {
    launchApp()
    try seedPendingDoc("取消保留", id: 4)
    seamed.pendingDocsReply = nil

    let reply = appDelegate.applicationShouldTerminate(NSApp)

    XCTAssertEqual(reply, .terminateCancel)
    XCTAssertTrue(appDelegate.pendingDocs.contains(4))
  }
}

/// BUG-017：关闭按钮 / ⌘W 路径——未决文档必须「先决策后关窗」。
///
/// 决策依据（bug-workflow）：旧实现关闭事件直接关窗，未决提示在系统终止流程
/// （applicationShouldTerminate）里才弹——取消返回 terminateCancel 后应用处于
/// 无窗口状态，`applicationShouldTerminateAfterLastWindowClosed` 恒为 true，
/// AppKit 反复重新触发终止 = 弹窗死循环（独立 repro 实测：取消后连续弹窗直到
/// watchdog）。修复：windowShouldClose 拦截，决策在窗口仍打开时进行。
@MainActor
final class AppWindowCloseFlowTests: AppIntegrationTestCase {
  func testCloseWithPendingSaveAllResolvesThenAllowsClose() throws {
    launchApp()
    let model = try XCTUnwrap(currentModel)
    try model.typeText("未保存内容")
    let window = try XCTUnwrap(appDelegate.currentFrame)
    seamed.pendingDocsReply = 1

    let allow = appDelegate.windowShouldClose(window)

    XCTAssertTrue(allow, "保存全部成功必须允许关窗")
    XCTAssertTrue(appDelegate.pendingDocs.isEmpty)
    XCTAssertTrue(window.isVisible, "windowShouldClose 只放行，关窗由 AppKit 随后执行")
    let id = UInt(model.bufferIdValue)
    let seq = try XCTUnwrap(appDelegate.snapshotSeqByDocId[id])
    let saved = try String(
      contentsOfFile: storeDir + "/" + snapshotName(seq: Int(seq)), encoding: .utf8)
    XCTAssertTrue(saved.contains("未保存内容"), "保存全部必须固化内容")
  }

  func testCloseWithPendingDiscardAllowsClose() throws {
    launchApp()
    try currentModel?.typeText("丢弃内容")
    let window = try XCTUnwrap(appDelegate.currentFrame)
    seamed.pendingDocsReply = 0

    XCTAssertTrue(appDelegate.windowShouldClose(window), "丢弃全部后必须允许关窗")
    XCTAssertTrue(appDelegate.pendingDocs.isEmpty)
  }

  func testCloseWithPendingCancelKeepsWindowOpen() throws {
    launchApp()
    try currentModel?.typeText("取消保留")
    let window = try XCTUnwrap(appDelegate.currentFrame)
    seamed.pendingDocsReply = nil

    XCTAssertFalse(
      appDelegate.windowShouldClose(window),
      "取消必须阻止关窗——否则无窗口状态反复重触发终止（BUG-017 死循环）"
    )
    XCTAssertTrue(
      appDelegate.pendingDocs.contains(UInt((currentModel?.bufferIdValue)!)),
      "取消后未决状态必须保留"
    )
    XCTAssertTrue(window.isVisible, "取消后窗口必须保持打开")
  }

  func testCloseWithoutPendingAllowsCloseWithoutPrompt() throws {
    launchApp()
    let window = try XCTUnwrap(appDelegate.currentFrame)

    XCTAssertTrue(appDelegate.windowShouldClose(window))
    XCTAssertEqual(seamed.pendingDocsAlertCount, 0, "无未决文档时不得弹提示")
  }
}
