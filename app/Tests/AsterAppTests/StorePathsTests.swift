//! 保存目录解析测试（T-040，ADR-023 v1.2 决策 3）。
//!
//! 决策依据：默认目录与 `ASTER_STORE_DIR` 覆盖是纯函数逻辑，可单测
//! （docs/testing.md：抽出的逻辑）；环境变量读取在测试内隔离设置。
import XCTest

@testable import AsterApp

final class StorePathsTests: XCTestCase {
  func testDefaultDirectoryPointsToApplicationSupportAster() {
    let dir = StorePaths.defaultDirectory()
    XCTAssertTrue(dir.hasSuffix("Application Support/Aster"), "默认目录：\(dir)")
  }

  func testEnvironmentOverrideWinsWhenSet() {
    setenv("ASTER_STORE_DIR", "/tmp/aster-test-store", 1)
    defer { unsetenv("ASTER_STORE_DIR") }
    XCTAssertEqual(StorePaths.defaultDirectory(), "/tmp/aster-test-store")
  }
}
