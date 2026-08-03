//! 保存状态机不变量测试（T-050 复审：属性化替代手写场景；T-058 扩展操作空间；
//! T-070 起经 Session 公共 API 断言）。
//!
//! 决策依据：手写用例永远追不上组合路径（BUG-010/011/012 都藏在组合里）。
//! 本文件用固定种子随机操作序列驱动**真实 AppDelegate**，每步断言守恒不变量
//! （ADR-013 v1.3 / BUG-011 泛化 / BUG-010 泛化）；种子固定 → 确定性可复现。
//! T-070：不变量由 Core Session 方法保证，本测试作为 App 层行为护栏 +
//! 变异门禁捕获网（M2 / M3 / M5 变异点依赖本文件）。

import AsterBridge
import XCTest

@testable import AsterApp

/// 确定性伪随机（LCG）：固定种子保证 CI 可复现。
struct SeededGenerator {
  private var state: UInt64

  init(seed: UInt64) {
    state = seed
  }

  mutating func nextInt(_ upperBound: Int) -> Int {
    state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
    return Int((state >> 33) % UInt64(max(1, upperBound)))
  }
}

@MainActor
final class SaveStateInvariantTests: AppIntegrationTestCase {
  func testSaveInvariantsSeed1() throws {
    try assertSaveInvariants(seed: 1)
  }

  func testSaveInvariantsSeed42() throws {
    try assertSaveInvariants(seed: 42)
  }

  func testSaveInvariantsSeed2026() throws {
    try assertSaveInvariants(seed: 2026)
  }

  func testSaveInvariantsSeed7() throws {
    try assertSaveInvariants(seed: 7)
  }

  func testSaveInvariantsSeed12345() throws {
    try assertSaveInvariants(seed: 12_345)
  }

  func testSaveInvariantsSeed20260803() throws {
    try assertSaveInvariants(seed: 20_260_803)
  }

  /// 随机操作序列（打开 / 同名打开 / 新建 / 编辑 / undo / redo / 保存 /
  /// 丢弃全部 / 崩溃恢复）下验证保存状态机守恒。
  private func assertSaveInvariants(seed: UInt64) throws {
    launchApp()
    let session = appSession
    var rng = SeededGenerator(seed: seed)
    var lastOpenedPath: String?

    for step in 0..<60 {
      switch rng.nextInt(9) {
      case 0:  // 打开一个新磁盘文件（切换当前文档）
        let path = storeDir + "/f\(rng.nextInt(1000)).txt"
        try "文件内容\(rng.nextInt(1000))".write(
          toFile: path, atomically: true, encoding: .utf8)
        appDelegate.open(URL(fileURLWithPath: path))
        lastOpenedPath = path
      case 1:  // 打开同名路径（BUG-010：每个打开必须独立快照序号，互不覆盖）
        if let path = lastOpenedPath {
          appDelegate.open(URL(fileURLWithPath: path))
        } else {
          let path = storeDir + "/f\(rng.nextInt(1000)).txt"
          try "同名内容".write(toFile: path, atomically: true, encoding: .utf8)
          appDelegate.open(URL(fileURLWithPath: path))
          lastOpenedPath = path
        }
      case 2:  // ⌘N 新建文档
        appDelegate.newDocument(nil)
      case 3:  // 编辑当前文档
        try currentModel?.typeText("x")
      case 4:  // undo（可能回退到已固化文本 → BUG-012 比较基线路径）
        try currentModel?.undo()
      case 5:  // redo
        try currentModel?.redo()
      case 6:  // 保存当前文档
        _ = appDelegate.saveCurrentDocument()
      case 7:  // 丢弃全部未决（退出「全部不保存」同款，ADR-013 v1.3 删除时机 3）
        appDelegate.discardAllPending()
      default:  // 崩溃恢复：经 Session 真实路径播种（T-070：不开假 id）——
        // 新文档编辑写缓冲 → 哨兵置非干净 → 恢复 / 忽略随机。
        let docId = UInt(try session_open_scratch(session, ""))
        let editor = try session_editor(session, docId)
        _ = try editor_type_text(editor, "崩溃内容\(step)")
        try session_content_changed(session, docId)
        try session_set_clean_exit(session, false)
        appDelegate.needsRecoveryPrompt = true
        let restore = rng.nextInt(2)
        seamed.recoveryReply = restore
        appDelegate.presentRecoveryIfNeeded()
        appDelegate.needsRecoveryPrompt = false
        if restore == 1 {
          // BUG-011 泛化（T-069 变异复验盲区）：恢复后当前视图文档必须已登记
          // 未决且缓冲行存在——恢复内容可被 ⌘S / 保存全部读取，不静默丢失。
          let recoveredId = UInt((try XCTUnwrap(currentModel)).bufferIdValue)
          XCTAssertTrue(
            session_is_pending(session, recoveredId),
            "step \(step)：恢复文档必须登记未决"
          )
          XCTAssertTrue(
            session_buffered_ids(session).contains(recoveredId),
            "step \(step)：恢复内容必须写入缓冲行"
          )
        }
      }

      // 不变量 1：每个未决文档都登记了快照序号（BUG-011 泛化——否则
      // 退出「保存全部」找不到合并目标）。
      let pending = Set(session_pending_ids(session).map { UInt($0) })
      for id in pending {
        XCTAssertNotNil(
          try? session_snapshot_seq(session, id),
          "step \(step)：未决文档 \(id) 缺少快照序号"
        )
      }
      // 不变量 2：缓冲行集合 == 未决登记集合（ADR-013 v1.3：缓冲行存在
      // ⟺ 存在未提交且未明确丢弃的编辑）。
      let buffered = Set(session_buffered_ids(session).map { UInt($0) })
      XCTAssertEqual(
        buffered, pending,
        "step \(step)：缓冲行与未决登记不一致"
      )
      // 不变量 3：快照序号全局唯一（BUG-010 泛化——两个文档共享同一快照
      // 时「保存全部」后写覆盖先写，先打开文档内容丢失）。
      let seqs = pending.compactMap { try? session_snapshot_seq(session, $0) }
      XCTAssertEqual(
        Set(seqs).count, seqs.count,
        "step \(step)：快照序号必须唯一"
      )
    }

    // 终局：退出「保存全部」必须成功，且全部缓冲清空（ADR-013 v1.4）。
    seamed.pendingDocsReply = 1
    XCTAssertEqual(appDelegate.applicationShouldTerminate(NSApp), .terminateNow)
    XCTAssertTrue(pendingSet().isEmpty, "保存全部后未决应清空")
    XCTAssertTrue(bufferedSet().isEmpty, "保存全部后缓冲应清空")
    XCTAssertEqual(seamed.saveErrorCount, 0, "随机序列下保存全部不应失败")
  }
}
