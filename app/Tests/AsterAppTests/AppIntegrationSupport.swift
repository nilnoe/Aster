//! App 集成测试共享设施（T-050；T-070 起经 Session 单一入口）。
//!
//! 决策依据：
//! - 每用例独立临时目录并经 `ASTER_STORE_DIR` 注入（既有机制，ADR-023 v1.2
//!   决策 3），测试间互不污染；目录随用例清理。
//! - `AppDelegate` 是 @MainActor；XCTestCase 全类标注 @MainActor 保持同步。
//! - T-070（ADR-025）：断言一律走 Session 公共 API（pending / buffered /
//!   snapshot_seq / load_buffered），不再伸手进 AppDelegate 账本；崩溃播种用
//!   Session 真实路径（开文档 → 编辑写缓冲 → 哨兵置非干净 → 丢弃 = 崩溃），
//!   避免旧假 id（42 / 5 / 9）掩盖 id 复用碰撞（BUG-023）。

import AsterBridge
import XCTest

@testable import AsterApp

/// 五组集成测试的基类：环境注入 + AppDelegate 组装 + 目录清理。
@MainActor
class AppIntegrationTestCase: XCTestCase {
  var storeDir: String!
  var appDelegate: AppDelegate!

  /// 模态提示 seam 注入器（docs/testing.md）：`AppDelegate` 的退出 / 恢复提示
  /// 经 `runModal()` 阻塞，测试以子类覆写注入决策。可选值：`pendingDocsReply`
  /// 1 = 保存 / 0 = 不保存 / nil = 取消；`recoveryReply` 1 = 恢复 / 0 = 忽略。
  final class SeamedAppDelegate: AppDelegate {
    var pendingDocsReply: Int?
    var recoveryReply: Int = 1
    /// 错误提示注入：记录调用次数，避免真实 NSAlert 阻塞测试进程。
    var saveErrorCount = 0
    /// 最近一次错误提示文本（T-054：断言提示内容准确，不只数次数）。
    var lastSaveErrorMessage: String?
    /// 未决文档提示调用次数（BUG-017：无未决时关窗不得弹提示）。
    var pendingDocsAlertCount = 0

    override func presentPendingDocsAlert(closeDocumentId: UInt?) -> Int? {
      pendingDocsAlertCount += 1
      return pendingDocsReply
    }

    override func presentRecoveryAlert(count: Int) -> Int { recoveryReply }

    override func presentSaveError(_ message: String) {
      saveErrorCount += 1
      lastSaveErrorMessage = message
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

  /// 当前用例的 Session（AppDelegate 启动后唯一持有者；启动前为 nil）。
  var appSession: Session { appDelegate.session! }

  /// 视图承载的 EditorModel（App 集成测试主断言入口）。
  var currentModel: EditorModel? {
    (appDelegate.currentFrame?.contentView as? MetalView)?.model
  }

  /// 未决 id 集合（Session 查询，单一事实来源）。
  func pendingSet() -> Set<UInt> {
    Set(session_pending_ids(appSession).map { UInt($0) })
  }

  /// 缓冲行 id 集合（Session 查询）。
  func bufferedSet() -> Set<UInt> {
    Set(session_buffered_ids(appSession).map { UInt($0) })
  }

  /// 快照序号（未登记抛错）。
  func snapshotSeq(_ id: UInt) throws -> UInt {
    try session_snapshot_seq(appSession, id)
  }

  /// 崩溃状态播种（T-070 起经 Session 真实路径）：开 Scratch 文档 → 编辑写
  /// 缓冲 → 哨兵置非干净 → 丢弃 session 模拟崩溃（行与哨兵落盘，启动重建
  /// Session 时读到）。返回各文档 id（升序；最新 = 最后一个）。
  func seedCrashedDocs(_ texts: [String]) throws -> [UInt] {
    let session = session_new(storeDir)
    var ids: [UInt] = []
    for text in texts {
      let id = UInt(try session_open_scratch(session))
      try session_content_changed(session, id, text)
      ids.append(id)
    }
    try session_set_clean_exit(session, false)
    return ids
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
