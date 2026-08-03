//! Frame（广义窗口）集成测试（T-069；T-070 起经 Session 断言）。
//!
//! 决策依据：⌘⇧N 新建 Frame = 新窗口 + 全新 Scratch 文档（frame 表述为将来
//! 窗内分窗预留）；多 Frame 下每个 frame 的文档状态必须隔离——编辑 frame B
//! 不得污染 frame A 的 dirty / 标题 / 缓冲行（onChange 按 frame 接线）。

import AsterBridge
import XCTest

@testable import AsterApp

@MainActor
final class FrameIntegrationTests: AppIntegrationTestCase {
  /// 启动后 ⌘⇧N（newFrame）：产生第二个 frame，持有全新文档（独立快照序号），
  /// 标题为纯 App 名。
  func testNewFrameCreatesSecondWindowWithFreshDocument() throws {
    launchApp()
    let first = try XCTUnwrap(appDelegate.currentFrame)
    let firstView = try XCTUnwrap(first.contentView as? MetalView)

    appDelegate.newFrame(nil)

    XCTAssertEqual(appDelegate.frames.count, 2, "新建 Frame 后必须有两个 frame")
    // 测试进程不跑 run loop，makeKeyAndOrderFront 不更新 NSApp.keyWindow——
    // currentFrame 回退到第一个；这里显式取第二个 frame（生产环境 keyWindow
    // 即新 frame，语义一致）。
    let second = appDelegate.frames[1]
    XCTAssertFalse(second === first, "新 frame 必须是不同窗口")
    XCTAssertTrue(second.isVisible)
    let secondView = try XCTUnwrap(second.contentView as? MetalView)
    XCTAssertNotEqual(
      secondView.model.bufferIdValue, firstView.model.bufferIdValue,
      "新 frame 必须持有全新文档（独立 BufferId）"
    )
    XCTAssertEqual(second.title, "Aster", "新 frame 标题为纯 App 名")
    XCTAssertEqual(snapshotFiles().count, 2, "启动 1 个快照 + 新 frame 1 个")
    _ = try snapshotSeq(UInt(secondView.model.bufferIdValue))
  }

  /// 多 Frame 状态隔离：编辑 frame B 只置 B 的文档未决、只污染 B 的标题 /
  /// isDocumentEdited，frame A 不受影响。
  func testEditInSecondFrameDoesNotDirtyFirstFrame() throws {
    launchApp()
    let first = try XCTUnwrap(appDelegate.currentFrame)
    let firstView = try XCTUnwrap(first.contentView as? MetalView)
    appDelegate.newFrame(nil)
    let second = appDelegate.frames[1]
    let secondView = try XCTUnwrap(second.contentView as? MetalView)
    let secondId = UInt(secondView.model.bufferIdValue)

    try secondView.model.typeText("frame B 编辑")

    XCTAssertTrue(pendingSet().contains(secondId), "编辑 B 必须置 B 的文档未决")
    XCTAssertFalse(
      pendingSet().contains(UInt(firstView.model.bufferIdValue)),
      "frame A 的文档不得被 B 的编辑污染"
    )
    XCTAssertTrue(second.isDocumentEdited)
    XCTAssertFalse(first.isDocumentEdited)
  }

  /// 新 frame 的文档必须接线自动保存：编辑 B → B 自己的缓冲行落盘。
  func testNewFrameDocumentAutoSavesToItsOwnBufferRow() throws {
    launchApp()
    appDelegate.newFrame(nil)
    let secondView = try XCTUnwrap(appDelegate.frames[1].contentView as? MetalView)
    try secondView.model.typeText("自动保存内容")
    let id = UInt(secondView.model.bufferIdValue)

    XCTAssertEqual(
      try session_load_buffered(appSession, id).toString(),
      "自动保存内容",
      "frame B 的文档必须自动保存到自己的缓冲行"
    )
  }

  /// 关闭 frame 必须从 frames 登记移除（最后窗口关闭仍退出，既有语义）。
  func testClosingFrameRemovesItFromFrames() throws {
    launchApp()
    appDelegate.newFrame(nil)
    let second = appDelegate.frames[1]
    XCTAssertEqual(appDelegate.frames.count, 2)

    appDelegate.windowWillClose(
      Notification(name: NSWindow.willCloseNotification, object: second))

    XCTAssertEqual(appDelegate.frames.count, 1, "关闭后 frame 必须从登记移除")
    let remaining = try XCTUnwrap(appDelegate.currentFrame)
    XCTAssertTrue(appDelegate.frames.first === remaining)
  }

  /// T-070（ADR-025）：关闭 frame 同时关闭其文档（Session 注册表移除）——
  /// 旧实现 DM 注册表随每次新建 / 打开永久增长（BUG-022）。
  func testClosingFrameClosesItsDocument() throws {
    launchApp()
    appDelegate.newFrame(nil)
    let second = appDelegate.frames[1]
    let secondId = UInt(
      (second.contentView as? MetalView)?.model.bufferIdValue ?? 0)

    appDelegate.windowWillClose(
      Notification(name: NSWindow.willCloseNotification, object: second))

    XCTAssertFalse(session_is_pending(appSession, secondId), "关闭后文档不再未决")
    XCTAssertThrowsError(try session_text(appSession, secondId), "关闭后文档不可再访问")
  }

  /// REPRO（临时）：模拟真实关闭按钮路径 performClose → windowShouldClose →
  /// close → windowWillClose，验证不挂起。
  func testClosingSecondFrameViaPerformCloseDoesNotHang() throws {
    launchApp()
    appDelegate.newFrame(nil)
    let second = appDelegate.frames[1]

    second.performClose(nil)

    XCTAssertEqual(appDelegate.frames.count, 1, "关闭后 frame 必须移除")
    XCTAssertTrue(appDelegate.frames[0].isVisible)
  }

  /// REPRO（临时）：B 有未决编辑时经 performClose 关闭（走保存决策）。
  func testClosingEditedSecondFrameViaPerformCloseDoesNotHang() throws {
    launchApp()
    appDelegate.newFrame(nil)
    let second = appDelegate.frames[1]
    let secondView = try XCTUnwrap(second.contentView as? MetalView)
    try secondView.model.typeText("未保存编辑")
    seamed.pendingDocsReply = 1

    second.performClose(nil)

    XCTAssertEqual(appDelegate.frames.count, 1)
    XCTAssertTrue(pendingSet().isEmpty, "保存后未决清空")
  }

  /// BUG-018：关闭的 frame 的 MetalView 光标闪烁必须停止——Timer 以 target/
  /// selector 强持有 view（保留环）且关闭后的窗口仍被 AppKit 保留（ARC 下
  /// isReleasedWhenClosed 不生效），旧实现定时器无限期存活（每 ⌘⇧N 泄漏一份
  /// 渲染资源 + 永续 needsDisplay）。windowWillClose 确定性停止。
  func testClosedFrameStopsCaretBlinkTimer() throws {
    launchApp()
    appDelegate.newFrame(nil)
    let secondView = try XCTUnwrap(appDelegate.frames[1].contentView as? MetalView)
    XCTAssertTrue(secondView.isCaretBlinkActive, "前置：光标闪烁激活")

    appDelegate.frames[1].performClose(nil)
    XCTAssertEqual(appDelegate.frames.count, 1)

    XCTAssertFalse(secondView.isCaretBlinkActive, "关闭后光标闪烁必须停止（保留环打断）")
  }
}
