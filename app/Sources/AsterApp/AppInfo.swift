//! App 元信息（T-011，ADR-015）。
//!
//! 决策依据：版本号来自 Rust Core（Cargo.toml，经 Bridge）——单一事实来源，
//! 避免 App 与 Core 版本漂移（Rule 9：一份数据源）。

import AsterBridge

enum AppInfo {
    static let name = "Aster"
    static let version = core_version().toString()
}
