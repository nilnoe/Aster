//! App 元信息测试（T-011，ADR-015）。
//!
//! 垂直线程验证：版本号来自 Rust Core（Cargo.toml，经 Bridge），
//! App 与 Core 版本单一来源（ADR-015 原因）。

import XCTest

@testable import AsterApp

final class AppInfoTests: XCTestCase {
  func testAppInfoVersionComesFromCore() {
    XCTAssertEqual(AppInfo.name, "Aster")
    // 版本号单一来源（core/Cargo.toml → Bridge → App）；硬编码具体版本会在发版时
    // 失效（T-048：0.1.1 → 0.1.2 CI 抓出），改为格式断言，一致性交给 CI-Release。
    XCTAssertNotNil(
      AppInfo.version.range(of: #"^\d+\.\d+\.\d+$"#, options: .regularExpression),
      "版本号必须是 x.y.z：\(AppInfo.version)"
    )
  }
}
