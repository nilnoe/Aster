//! 主菜单壳测试（T-011，ADR-015）。
//!
//! 抽出逻辑验证：最小菜单契约——退出快捷键（Cmd+Q）、关于项、
//! 标准编辑动作、Window 最小化。View 层行为靠手动验证（docs/testing.md）。

import AppKit
import XCTest

@testable import AsterApp

final class AppMenuTests: XCTestCase {
  func testAppMenuHasQuitShortcut() {
    let menu = AppMenu.build(aboutTarget: NSObject())

    let quitItem = menu.items
      .flatMap { $0.submenu?.items ?? [] }
      .first { $0.keyEquivalent == "q" }

    XCTAssertEqual(quitItem?.action, #selector(NSApplication.terminate(_:)))
  }

  func testAppMenuAboutItemTargetsAboutHandler() {
    let menu = AppMenu.build(aboutTarget: NSObject())

    let aboutItem = menu.items
      .flatMap { $0.submenu?.items ?? [] }
      .first { $0.title == "关于 Aster" }

    XCTAssertEqual(aboutItem?.action, #selector(AppDelegate.showAbout(_:)))
  }

  func testAppMenuHasStandardEditActions() {
    let menu = AppMenu.build(aboutTarget: NSObject())

    let editItem = menu.items.first { $0.title == "编辑" }
    let selectors = editItem?.submenu?.items.compactMap { $0.action } ?? []

    XCTAssertTrue(selectors.contains(Selector(("selectAll:"))))
    XCTAssertTrue(selectors.contains(Selector(("paste:"))))
  }

  /// T-037（ADR-023）：File 菜单必须提供「保存」⌘S，指向 AppDelegate。
  func testFileMenuHasSaveShortcut() {
    let menu = AppMenu.build(aboutTarget: NSObject())

    let fileItem = menu.items.first { $0.title == "文件" }
    let saveItem = fileItem?.submenu?.items.first { $0.title == "保存" }

    XCTAssertEqual(saveItem?.keyEquivalent, "s")
    XCTAssertEqual(saveItem?.action, #selector(AppDelegate.saveDocument(_:)))
  }

  /// T-041（ADR-023 v1.3）：File 菜单必须提供「新建」⌘N（新快照）。
  func testFileMenuHasNewShortcut() {
    let menu = AppMenu.build(aboutTarget: NSObject())

    let fileItem = menu.items.first { $0.title == "文件" }
    let newItem = fileItem?.submenu?.items.first { $0.title == "新建" }

    XCTAssertEqual(newItem?.keyEquivalent, "n")
    XCTAssertEqual(newItem?.keyEquivalentModifierMask, [.command])
    XCTAssertEqual(newItem?.action, #selector(AppDelegate.newDocument(_:)))
  }

  /// T-069：File 菜单必须提供「新建 Frame」⌘⇧N。绑定只存在于菜单（单一
  /// 来源——按键将来可改，与动作解耦：动作是普通 selector，keyDown 不处理
  /// 菜单快捷键），且与「新建」⌘N 不冲突。
  func testFileMenuHasNewFrameShortcut() {
    let menu = AppMenu.build(aboutTarget: NSObject())

    let fileItem = menu.items.first { $0.title == "文件" }
    let newFrameItem = fileItem?.submenu?.items.first { $0.title == "新建 Frame" }

    XCTAssertEqual(newFrameItem?.keyEquivalent, "N")
    XCTAssertEqual(newFrameItem?.keyEquivalentModifierMask, [.command, .shift])
    XCTAssertEqual(newFrameItem?.action, #selector(AppDelegate.newFrame(_:)))
  }
}
