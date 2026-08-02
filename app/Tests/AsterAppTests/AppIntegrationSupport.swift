//! App 集成测试共享设施（T-050）。
//!
//! 决策依据：
//! - 每用例独立临时目录并经 `ASTER_STORE_DIR` 注入（既有机制，ADR-023 v1.2
//!   决策 3），测试间互不污染；目录随用例清理。
//! - `AppDelegate` 是 @MainActor；XCTestCase 全类标注 @MainActor 保持同步
//!   （应用编辑 / 保存链路全同步，无需 async）。
//! - 集成测试驱动真实 AppKit 对象：真实 NSWindow / MetalView / 存储落盘。
//!   无 GPU 的用例沿用 T-012 守卫（MTLCreateSystemDefaultDevice() == nil 跳过）。

import XCTest

@testable import AsterApp

/// 五组集成测试的基类：环境注入 + AppDelegate 组装 + 目录清理。
@MainActor
class AppIntegrationTestCase: XCTestCase {
  var storeDir: String!
  var appDelegate: AppDelegate!

  /// 模态提示 seam 注入器（docs/testing.md）：`AppDelegate` 的退出 / 恢复提示
  /// 经 `runModal()` 阻塞，测试以子类覆写注入决策。可选值：`pendingDocsReply`
  /// 1 = 保存全部 / 0 = 全部不保存 / nil = 取消；`recoveryReply` 1 = 恢复 /
  /// 0 = 忽略。
  final class SeamedAppDelegate: AppDelegate {
    var pendingDocsReply: Int?
    var recoveryReply: Int = 1
    /// 错误提示注入：记录调用次数，避免真实 NSAlert 阻塞测试进程
    /// （T-050 复审：saveAllPending 失败路径会弹 presentSaveError）。
    var saveErrorCount = 0

    override func presentPendingDocsAlert() -> Int? { pendingDocsReply }

    override func presentRecoveryAlert(count: Int) -> Int { recoveryReply }

    override func presentSaveError(_ message: String) {
      saveErrorCount += 1
    }
  }

  /// 当前用例的 seam 实例（注入决策入口）。
  var seamed: SeamedAppDelegate { appDelegate as! SeamedAppDelegate }

  override func setUp() {
    super.setUp()
    // 真实启动链路需要 NSApplication 存在（AppDelegate 用 NSApp 设菜单 /
    // activate）；测试进程默认没有，先实例化共享应用（不启动 run loop）。
    _ = NSApplication.shared
    storeDir = NSTemporaryDirectory() + "AsterIT-\(UUID().uuidString)"
    try? FileManager.default.createDirectory(
      atPath: storeDir, withIntermediateDirectories: true
    )
    setenv("ASTER_STORE_DIR", storeDir, 1)
    appDelegate = SeamedAppDelegate()
  }

  override func tearDown() {
    unsetenv("ASTER_STORE_DIR")
    appDelegate = nil
    storeDir = nil
    super.tearDown()
  }

  /// 启动真实生命周期路径（T-050 组 1）。
  func launchApp() {
    appDelegate.applicationDidFinishLaunching(
      Notification(name: NSApplication.didFinishLaunchingNotification))
  }

  /// 视图承载的 EditorModel（App 集成测试主断言入口）。
  var currentModel: EditorModel? {
    (appDelegate.mainWindow?.contentView as? MetalView)?.model
  }

  /// 快照目录内容（按文件名排序）。
  func snapshotFiles() -> [String] {
    (try? FileManager.default.contentsOfDirectory(atPath: storeDir))?
      .filter { $0.hasPrefix("aster-") && $0.hasSuffix(".txt") }
      .sorted() ?? []
  }

  /// 当日快照文件名（与 Core `Snapshot::path_for` 同构：UTC 日期 + 3 位序号）。
  func snapshotName(seq: Int) -> String {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "UTC")
    formatter.dateFormat = "yyyy-MM-dd"
    let today = formatter.string(from: Date())
    return String(format: "aster-%@-%03d.txt", today, seq)
  }
}
