//! 主菜单壳（T-011，ADR-015）。
//!
//! 决策依据：
//! - 最小集（项目哲学：空白、安静）：App（关于 / 隐藏 / 退出）、Edit（标准
//!   编辑动作，T-013 编辑循环接线复用）、Window（最小化 / 缩放）。
//! - 菜单与动作全部用系统能力（Principle 4：Do Not Fight The OS）。
//! - File（打开…，T-015）按切片需求加入；无 Sidebar / Toolbar 占位。

import AppKit

enum AppMenu {
  /// 构建主菜单；`aboutTarget` 接收关于动作（AppDelegate.showAbout）。
  static func build(aboutTarget: AnyObject) -> NSMenu {
    let main = NSMenu()
    main.addItem(appMenuItem(aboutTarget: aboutTarget))
    main.addItem(fileMenuItem(aboutTarget: aboutTarget))
    main.addItem(editMenuItem())
    main.addItem(windowMenuItem())
    return main
  }

  private static func appMenuItem(aboutTarget: AnyObject) -> NSMenuItem {
    let menu = NSMenu()
    let about = NSMenuItem(
      title: "关于 Aster",
      action: #selector(AppDelegate.showAbout(_:)),
      keyEquivalent: ""
    )
    about.target = aboutTarget
    menu.addItem(about)
    menu.addItem(.separator())
    menu.addItem(
      withTitle: "隐藏 Aster",
      action: #selector(NSApplication.hide(_:)),
      keyEquivalent: "h"
    )
    menu.addItem(.separator())
    menu.addItem(
      withTitle: "退出 Aster",
      action: #selector(NSApplication.terminate(_:)),
      keyEquivalent: "q"
    )
    let item = NSMenuItem(title: "Aster", action: nil, keyEquivalent: "")
    item.submenu = menu
    return item
  }

  private static func editMenuItem() -> NSMenuItem {
    let menu = NSMenu(title: "编辑")
    // 标准编辑动作：target 为 nil，走响应链（系统能力，T-013 接线编辑循环）。
    let actions: [(String, String, String)] = [
      ("撤销", "undo:", "z"),
      ("重做", "redo:", "Z"),
      ("剪切", "cut:", "x"),
      ("拷贝", "copy:", "c"),
      ("粘贴", "paste:", "v"),
      ("全选", "selectAll:", "a"),
    ]
    for (index, (title, selector, key)) in actions.enumerated() {
      if index == 2 {
        menu.addItem(.separator())
      }
      menu.addItem(
        withTitle: title,
        action: Selector(selector),
        keyEquivalent: key
      )
    }
    let item = NSMenuItem(title: "编辑", action: nil, keyEquivalent: "")
    item.submenu = menu
    return item
  }

  private static func fileMenuItem(aboutTarget: AnyObject) -> NSMenuItem {
    let menu = NSMenu(title: "文件")
    // 打开…：target 为 AppDelegate（DocumentManager 持有者，T-015，ADR-001）。
    menu.addItem(
      withTitle: "打开…",
      action: #selector(AppDelegate.openDocument(_:)),
      keyEquivalent: "o"
    )
    let item = NSMenuItem(title: "文件", action: nil, keyEquivalent: "")
    item.submenu = menu
    return item
  }

  private static func windowMenuItem() -> NSMenuItem {
    let menu = NSMenu(title: "窗口")
    menu.addItem(
      withTitle: "最小化",
      action: #selector(NSWindow.performMiniaturize(_:)),
      keyEquivalent: "m"
    )
    menu.addItem(
      withTitle: "缩放",
      action: #selector(NSWindow.performZoom(_:)),
      keyEquivalent: ""
    )
    let item = NSMenuItem(title: "窗口", action: nil, keyEquivalent: "")
    item.submenu = menu
    return item
  }
}
