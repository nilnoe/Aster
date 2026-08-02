//! App 元信息测试（T-011，ADR-015）。
//!
//! 垂直线程验证：版本号来自 Rust Core（Cargo.toml，经 Bridge），
//! App 与 Core 版本单一来源（ADR-015 原因）。

import XCTest

@testable import AsterApp

final class AppInfoTests: XCTestCase {
  func testAppInfoVersionComesFromCore() {
    XCTAssertEqual(AppInfo.name, "Aster")
    XCTAssertEqual(AppInfo.version, "0.1.0")
  }
}
