//! 保存状态机不变量测试（T-050 复审：属性化替代手写场景）。
//!
//! 决策依据：手写用例永远追不上组合路径（BUG-010/011/012 都藏在组合里）。
//! 本文件用固定种子随机操作序列（打开 / 新建 / 编辑 / 保存）驱动**真实
//! AppDelegate**，每步断言守恒不变量（ADR-013 v1.3 / BUG-011 泛化），
//! 随机探索状态空间而非枚举场景；种子固定 → 确定性可复现。

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

  /// 随机操作序列（打开 / 新建 / 编辑 / 保存）下验证保存状态机守恒。
  private func assertSaveInvariants(seed: UInt64) throws {
    launchApp()
    let store = try XCTUnwrap(appDelegate.bufferStore)
    var rng = SeededGenerator(seed: seed)

    for step in 0..<50 {
      switch rng.nextInt(4) {
      case 0:  // 打开一个新磁盘文件（切换当前文档）
        let path = storeDir + "/f\(rng.nextInt(1000)).txt"
        try "文件内容\(rng.nextInt(1000))".write(
          toFile: path, atomically: true, encoding: .utf8)
        appDelegate.open(URL(fileURLWithPath: path))
      case 1:  // ⌘N 新建文档
        appDelegate.newDocument(nil)
      case 2:  // 编辑当前文档
        try currentModel?.typeText("x")
      default:  // 保存当前文档
        _ = appDelegate.saveCurrentDocument()
      }

      // 不变量 1：每个未决文档都登记了快照序号（BUG-011 泛化——否则
      // 退出「保存全部」找不到合并目标）。
      for id in appDelegate.pendingDocs.ids {
        XCTAssertNotNil(
          appDelegate.snapshotSeqByDocId[id],
          "step \(step)：未决文档 \(id) 缺少快照序号"
        )
      }
      // 不变量 2：缓冲行集合 == 未决登记集合（ADR-013 v1.3：缓冲行存在
      // ⟺ 存在未提交且未明确丢弃的编辑）。
      let scratchIds = Set(store_scratch_ids(store).map { UInt($0) })
      XCTAssertEqual(
        scratchIds, appDelegate.pendingDocs.ids,
        "step \(step)：缓冲行与未决登记不一致"
      )
    }

    // 终局：退出「保存全部」必须成功，且全部缓冲清空（ADR-013 v1.4）。
    seamed.pendingDocsReply = 1
    XCTAssertEqual(appDelegate.applicationShouldTerminate(NSApp), .terminateNow)
    XCTAssertTrue(appDelegate.pendingDocs.isEmpty, "保存全部后未决应清空")
    XCTAssertTrue(store_scratch_ids(store).isEmpty, "保存全部后缓冲应清空")
    XCTAssertEqual(seamed.saveErrorCount, 0, "随机序列下保存全部不应失败")
  }
}
