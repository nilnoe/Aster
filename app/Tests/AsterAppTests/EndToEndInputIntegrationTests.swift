//! T-050 组 5：端到端数据流——合成 NSEvent 按键 → MetalView.keyDown →
//! Bridge → Core 编辑 → onChange → 置脏 → 缓冲自动保存。
//!
//! 决策依据：这条链路是架构数据流（ARCHITECTURE.md）的最小端到端形态，
//! 此前只有各层独立测试；无 GPU 环境跳过（T-012 守卫惯例）。

import AppKit
import AsterBridge
import XCTest

@testable import AsterApp

final class EndToEndInputIntegrationTests: AppIntegrationTestCase {
  private func synthesizeKeyDown(_ character: String) -> NSEvent? {
    guard let window = appDelegate.currentFrame else { return nil }
    return NSEvent.keyEvent(
      with: .keyDown,
      location: .zero,
      modifierFlags: [],
      timestamp: 0,
      windowNumber: window.windowNumber,
      context: nil,
      characters: character,
      charactersIgnoringModifiers: character,
      isARepeat: false,
      keyCode: 0
    )
  }

  func testKeyDownFlowsThroughBridgeToCoreAndPersists() throws {
    guard MTLCreateSystemDefaultDevice() != nil else {
      throw XCTSkip("无 GPU，跳过 Metal 端到端用例")
    }
    launchApp()
    let model = try XCTUnwrap(currentModel)
    let id = UInt(model.bufferIdValue)
    let event = try XCTUnwrap(synthesizeKeyDown("x"))

    (appDelegate.currentFrame?.contentView as? MetalView)?.keyDown(with: event)

    XCTAssertEqual(model.bufferText, "x你好，世界。Hello, Aster!\nMetal 文本渲染 — 第二行 CJK")
    XCTAssertTrue(pendingSet().contains(id))
    XCTAssertEqual(
      try bufferedContent(id),
      "x你好，世界。Hello, Aster!\nMetal 文本渲染 — 第二行 CJK"
    )
  }
}
