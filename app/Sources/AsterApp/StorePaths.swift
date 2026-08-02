//! 保存存储默认路径（T-040，ADR-023 v1.2 决策 3）。
//!
//! 决策依据：默认目录 `~/Library/Application Support/Aster`（系统惯例，Principle 4）；
//! v1 经环境变量 `ASTER_STORE_DIR` 覆盖（无配置系统的最小实现），Config DSL / Lua
//! 配置切片落地后迁移为配置项。纯函数、可单测（docs/testing.md：抽出的逻辑）。
import Foundation

enum StorePaths {
  /// 保存库目录（App 模块内，非公共 API）。
  static func defaultDirectory() -> String {
    if let override = ProcessInfo.processInfo.environment["ASTER_STORE_DIR"],
      !override.isEmpty
    {
      return override
    }
    let appSupport =
      FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? FileManager.default.temporaryDirectory
    return appSupport.appendingPathComponent("Aster", isDirectory: true).path
  }
}
