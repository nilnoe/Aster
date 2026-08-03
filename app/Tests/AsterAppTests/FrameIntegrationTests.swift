//! Frame（广义窗口）集成测试（T-069）。
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
    XCTAssertNotNil(appDelegate.snapshotSeqByDocId[UInt(secondView.model.bufferIdValue)])
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

    XCTAssertTrue(appDelegate.pendingDocs.contains(secondId), "编辑 B 必须置 B 的文档未决")
    XCTAssertFalse(
      appDelegate.pendingDocs.contains(UInt(firstView.model.bufferIdValue)),
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
    let store = try XCTUnwrap(appDelegate.bufferStore)
    let id = UInt(secondView.model.bufferIdValue)

    XCTAssertEqual(
      try store_load_scratch(store, id).toString(),
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
}
