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

/// BUG-017：关闭按钮 / ⌘W 路径——未决文档必须「先决策后关窗」。
///
/// 决策依据（bug-workflow）：旧实现关闭事件直接关窗，未决提示在系统终止流程
/// （applicationShouldTerminate）里才弹——取消返回 terminateCancel 后应用处于
/// 无窗口状态，`applicationShouldTerminateAfterLastWindowClosed` 恒为 true，
/// AppKit 反复重新触发终止 = 弹窗死循环。修复：windowShouldClose 拦截，决策在
/// 窗口仍打开时进行。T-070：决策按**该窗口**文档（关 B 只问 B）。
@MainActor
final class AppWindowCloseFlowTests: AppIntegrationTestCase {
  func testCloseWithPendingSaveAllResolvesThenAllowsClose() throws {
    launchApp()
    let model = try XCTUnwrap(currentModel)
    try model.typeText("未保存内容")
    let window = try XCTUnwrap(appDelegate.currentFrame)
    seamed.pendingDocsReply = 1

    let allow = appDelegate.windowShouldClose(window)

    XCTAssertTrue(allow, "保存成功必须允许关窗")
    XCTAssertTrue(pendingSet().isEmpty)
    XCTAssertTrue(window.isVisible, "windowShouldClose 只放行，关窗由 AppKit 随后执行")
    let id = UInt(model.bufferIdValue)
    let seq = try snapshotSeq(id)
    let saved = try String(
      contentsOfFile: storeDir + "/" + snapshotName(seq: Int(seq)), encoding: .utf8)
    XCTAssertTrue(saved.contains("未保存内容"), "保存必须固化内容")
  }

  func testCloseWithPendingDiscardAllowsClose() throws {
    launchApp()
    try currentModel?.typeText("丢弃内容")
    let window = try XCTUnwrap(appDelegate.currentFrame)
    seamed.pendingDocsReply = 0

    XCTAssertTrue(appDelegate.windowShouldClose(window), "丢弃后必须允许关窗")
    XCTAssertTrue(pendingSet().isEmpty)
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
      pendingSet().contains(UInt((currentModel?.bufferIdValue)!)),
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

  /// T-070（BUG-019）：多 Frame 下关闭决策按窗口文档——关 frame B 只保存 /
  /// 丢弃 B，frame A 的未决状态不受影响（旧实现全局决策，关 B 会弹 A 的提示）。
  func testClosingSecondFrameOnlyResolvesItsOwnDocument() throws {
    launchApp()
    appDelegate.newFrame(nil)
    let first = appDelegate.frames[0]
    let second = appDelegate.frames[1]
    let firstId = UInt(
      (first.contentView as? MetalView)?.model.bufferIdValue ?? 0)
    let secondId = UInt(
      (second.contentView as? MetalView)?.model.bufferIdValue ?? 0)
    try (first.contentView as? MetalView)?.model.typeText("A 编辑")
    try (second.contentView as? MetalView)?.model.typeText("B 编辑")
    seamed.pendingDocsReply = 1

    XCTAssertTrue(appDelegate.windowShouldClose(second), "B 保存成功必须放行")

    XCTAssertFalse(pendingSet().contains(secondId), "B 保存后不再是未决")
    XCTAssertTrue(pendingSet().contains(firstId), "A 的未决不得被 B 的关闭决策影响")
  }

  /// BUG-018（用户补充：菊花旋转 = 主线程卡死）：关**最后一个**窗口时存在
  /// **无窗口的孤儿未决文档**（⌘N / ⌘O 替换当前模型后遗留，或崩溃忽略登记），
  /// 旧实现 windowShouldClose 只检查该窗口文档——孤儿漏过：窗口先关 → 终止流程
  /// 再弹提示 → 取消后无窗口，`applicationShouldTerminateAfterLastWindowClosed`
  /// 恒 true → AppKit 反复重触发终止 = 弹窗循环 / 菊花（BUG-017 同机制）。
  /// 修复：关最后窗口 = 退出，走**全局**未决决策（含孤儿）；取消时窗口保持，
  /// 不再进入无窗口重触发循环。
  func testCloseLastWindowWithOrphanPendingCancelKeepsWindowWithoutLoop() throws {
    launchApp()
    // 制造孤儿未决：编辑 doc1（待定）→ 打开文件（视图换 doc2，doc1 无窗口保留）。
    let first = try XCTUnwrap(currentModel)
    try first.typeText("孤儿未决内容")
    let orphanId = UInt(first.bufferIdValue)
    let diskFile = storeDir + "/replacement.txt"
    try "替代文档".write(toFile: diskFile, atomically: true, encoding: .utf8)
    appDelegate.open(URL(fileURLWithPath: diskFile))
    XCTAssertTrue(pendingSet().contains(orphanId), "前置：旧文档必须是无窗口未决孤儿")
    XCTAssertEqual(appDelegate.frames.count, 1, "前置：当前只有一个 frame")

    let window = try XCTUnwrap(appDelegate.currentFrame)
    seamed.pendingDocsReply = nil  // 用户点「取消」

    XCTAssertFalse(
      appDelegate.windowShouldClose(window),
      "取消必须保窗——否则无窗口反复重触发终止（BUG-018 菊花循环）"
    )
    XCTAssertEqual(seamed.pendingDocsAlertCount, 1, "只决策一次，不得循环弹窗")
    XCTAssertTrue(window.isVisible, "取消后窗口必须保持打开")
    XCTAssertTrue(pendingSet().contains(orphanId), "取消后孤儿未决保留")
  }

  /// BUG-018 同机制：关最后一个窗口且选「保存全部」时，孤儿未决必须在关窗前
  /// 一并固化（全局决策）——关窗后终止流程不再需要弹提示（干净 terminateNow）。
  func testCloseLastWindowWithOrphanPendingSaveAllResolvesAllBeforeClose() throws {
    launchApp()
    let first = try XCTUnwrap(currentModel)
    try first.typeText("孤儿待保存")
    let orphanId = UInt(first.bufferIdValue)
    let diskFile = storeDir + "/replacement.txt"
    try "替代文档".write(toFile: diskFile, atomically: true, encoding: .utf8)
    appDelegate.open(URL(fileURLWithPath: diskFile))

    let window = try XCTUnwrap(appDelegate.currentFrame)
    seamed.pendingDocsReply = 1  // 用户点「保存全部」

    XCTAssertTrue(appDelegate.windowShouldClose(window), "保存全部成功必须放行关窗")
    XCTAssertTrue(
      pendingSet().isEmpty,
      "关最后窗口 = 退出：孤儿未决必须在关窗前一并固化，终止时不再弹提示"
    )
    // 关窗后终止流程干净：无未决 → terminateNow 不弹窗（无窗口重触发循环）。
    seamed.pendingDocsReply = nil
    XCTAssertEqual(appDelegate.applicationShouldTerminate(NSApp), .terminateNow)
    XCTAssertEqual(
      seamed.pendingDocsAlertCount, 1,
      "只弹关窗决策一次；孤儿已在关窗前固化，终止流程无未决可弹（无循环）"
    )
    // 孤儿内容已固化进其快照。
    let seq = try snapshotSeq(orphanId)
    let saved = try String(
      contentsOfFile: storeDir + "/" + snapshotName(seq: Int(seq)), encoding: .utf8)
    XCTAssertTrue(saved.contains("孤儿待保存"), "孤儿内容必须固化进快照")
  }
}
