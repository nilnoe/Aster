//! 关闭按钮 / ⌘W 路径测试（BUG-017 先决策后关窗；T-070 按窗口文档；
//! BUG-018 孤儿全局决策 + 停笔。Rule 3 拆分：原文件超 300 行）。
//!
//! 决策依据（bug-workflow）：旧实现关闭事件直接关窗，未决提示在系统终止流程
//! （applicationShouldTerminate）里才弹——取消返回 terminateCancel 后应用处于
//! 无窗口状态，`applicationShouldTerminateAfterLastWindowClosed` 恒为 true，
//! AppKit 反复重新触发终止 = 弹窗死循环。修复：windowShouldClose 拦截，决策在
//! 窗口仍打开时进行。T-070：非最后窗口按**该窗口**文档（关 B 只问 B）；
//! BUG-018：最后窗口走全局决策（含孤儿未决）+ 放行即停笔（over-release 修复）。

import AsterBridge
import XCTest

@testable import AsterApp

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

  /// BUG-018（菊花 = 主线程卡死）：关**最后一个**窗口时存在**无窗口的孤儿未决
  /// 文档**（⌘N / ⌘O 替换当前模型后遗留，或崩溃忽略登记），旧实现只检查该窗口
  /// 文档——孤儿漏过：窗口先关 → 终止流程再弹提示 → 取消后无窗口，恒 true →
  /// AppKit 反复重触发终止 = 弹窗循环。修复：关最后窗口 = 退出，走全局决策
  /// （含孤儿）；取消时窗口保持，不再进入无窗口重触发循环。
  func testCloseLastWindowWithOrphanPendingCancelKeepsWindowWithoutLoop() throws {
    launchApp()
    // 制造孤儿未决：编辑 doc1 → 打开文件（视图换 doc2，doc1 无窗口保留）。
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
