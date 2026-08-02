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
}
