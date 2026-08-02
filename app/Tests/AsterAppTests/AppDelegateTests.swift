//! AppDelegate 崩溃恢复决策测试（T-043，ADR-013 v1.1）。
//!
//! 决策依据：恢复提示 = 非干净退出 ∧ 缓冲有文档；纯函数抽离便于单测
//! （docs/testing.md：抽出的逻辑）。
import XCTest

@testable import AsterApp

final class AppDelegateTests: XCTestCase {
  func testNoRecoveryPromptOnCleanExit() {
    XCTAssertFalse(AppDelegate.shouldOfferRecovery(cleanExit: true, bufferedDocCount: 3))
  }

  func testNoRecoveryPromptWhenBufferEmpty() {
    XCTAssertFalse(AppDelegate.shouldOfferRecovery(cleanExit: false, bufferedDocCount: 0))
  }

  func testRecoveryPromptOnCrashWithBufferedDocuments() {
    XCTAssertTrue(AppDelegate.shouldOfferRecovery(cleanExit: false, bufferedDocCount: 2))
  }
}
